package com.kgeneye.eye.taxonomy

import android.content.Context
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Locale

/**
 * Kotlin mirror of `task_verbs.json` — per `task_category_code` verb lists in
 * PT / EN / ES. Indices are parallel across the three arrays, so the selected
 * set is simply a set of indices; the wizard then projects it to three
 * localised arrays when persisting the session taxonomy.
 */
@Serializable
data class TaskVerbsBundle(
    @SerialName("schema_version") val schemaVersion: String,
    @SerialName("generated_at") val generatedAt: String,
    val entries: List<Entry>,
) {
    @Serializable
    data class Entry(
        @SerialName("task_category_code") val taskCategoryCode: String,
        @SerialName("verbs_pt") val verbsPt: List<String>,
        @SerialName("verbs_en") val verbsEn: List<String>,
        @SerialName("verbs_es") val verbsEs: List<String>,
    )
}

object TaskVerbsLoader {
    private const val ASSET_NAME = "task_verbs.json"

    @Volatile private var cached: Map<String, TaskVerbsBundle.Entry>? = null

    @OptIn(ExperimentalSerializationApi::class)
    fun load(context: Context): Map<String, TaskVerbsBundle.Entry> {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val json = Json {
                ignoreUnknownKeys = true
                isLenient = true
            }
            val data = context.assets.open(ASSET_NAME).bufferedReader().use { it.readText() }
            val bundle = json.decodeFromString(TaskVerbsBundle.serializer(), data)
            val index = bundle.entries.associateBy { it.taskCategoryCode }
            cached = index
            return index
        }
    }

    fun verbs(context: Context, taskCategoryCode: String): TaskVerbsBundle.Entry? =
        load(context)[taskCategoryCode]
}

/** Uppercases only the first character of a verb token for on-screen use. */
fun String.verbDisplayCased(): String =
    if (isEmpty()) this else substring(0, 1).uppercase() + substring(1)

/** Returns the localised verb list for the current locale (falls back to EN). */
fun TaskVerbsBundle.Entry.localizedList(): List<String> {
    val lang = Locale.getDefault().language.lowercase()
    return when {
        lang.startsWith("pt") -> verbsPt
        lang.startsWith("es") -> verbsEs
        else -> verbsEn
    }
}
