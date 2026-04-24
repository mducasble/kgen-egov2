package com.kgeneye.eye.taxonomy

import android.content.Context
import android.util.Log
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Locale

/**
 * Kotlin mirror of the iOS `Taxonomy` struct. Parsed once from the bundled
 * `assets/taxonomy.json` (shared byte-for-byte with the iOS app) so the two
 * clients expose the same set of activities and locations.
 */
@Serializable
data class Taxonomy(
    @SerialName("schema_version") val schemaVersion: String,
    @SerialName("generated_at") val generatedAt: String = "",
    @SerialName("description_pt") val descriptionPt: String = "",
    @SerialName("description_en") val descriptionEn: String = "",
    @SerialName("description_es") val descriptionEs: String = "",
    val viewpoints: List<Viewpoint> = emptyList(),
    val domains: List<Domain> = emptyList(),
    val scenarios: List<Scenario> = emptyList(),
    val locations: List<Location> = emptyList(),
    @SerialName("task_categories") val taskCategories: List<TaskCategory> = emptyList(),
) {

    @Serializable
    data class Viewpoint(
        val code: String,
        @SerialName("label_pt") val labelPt: String,
        @SerialName("label_en") val labelEn: String,
        @SerialName("description_pt") val descriptionPt: String = "",
        @SerialName("description_en") val descriptionEn: String = "",
        @SerialName("description_es") val descriptionEs: String = "",
    )

    @Serializable
    data class Domain(
        val code: String,
        @SerialName("label_pt") val labelPt: String,
        @SerialName("label_en") val labelEn: String,
        @SerialName("description_pt") val descriptionPt: String = "",
        @SerialName("description_en") val descriptionEn: String = "",
        @SerialName("description_es") val descriptionEs: String = "",
    )

    @Serializable
    data class Scenario(
        val code: String,
        @SerialName("label_pt") val labelPt: String,
        @SerialName("label_en") val labelEn: String,
        @SerialName("description_pt") val descriptionPt: String = "",
        @SerialName("description_en") val descriptionEn: String = "",
        @SerialName("description_es") val descriptionEs: String = "",
    )

    @Serializable
    data class Location(
        val code: String,
        @SerialName("label_pt") val labelPt: String,
        @SerialName("label_en") val labelEn: String,
        val domain: String,
        val scenario: String,
    )

    @Serializable
    data class TaskCategory(
        val code: String,
        @SerialName("label_pt") val labelPt: String,
        @SerialName("label_en") val labelEn: String,
        @SerialName("description_pt") val descriptionPt: String = "",
        @SerialName("description_en") val descriptionEn: String = "",
        @SerialName("description_es") val descriptionEs: String = "",
        val group: String = "",
    )

    /**
     * User-facing scenario buckets — collapses the raw 4 scenarios into the
     * indoor/outdoor binary the product shows in the wizard. Mirrors the iOS
     * `BinaryScenario` enum.
     */
    enum class BinaryScenario(val code: String, val matchingRaw: Set<String>) {
        INDOOR("indoor", setOf("indoor")),
        OUTDOOR("outdoor", setOf("outdoor", "semi_outdoor", "transition"));
    }

    fun locationsMatching(bucket: BinaryScenario): List<Location> =
        locations.filter { bucket.matchingRaw.contains(it.scenario) }

    fun scenarioByCode(code: String): Scenario? = scenarios.firstOrNull { it.code == code }
    fun domainByCode(code: String): Domain? = domains.firstOrNull { it.code == code }
    fun taskCategoryByCode(code: String): TaskCategory? = taskCategories.firstOrNull { it.code == code }

    companion object {
        val empty: Taxonomy = Taxonomy(schemaVersion = "0.0.0")
    }
}

/**
 * Lazy shared loader. Decodes `assets/taxonomy.json` on first access and
 * caches the result for the life of the process. Falls back to an empty
 * taxonomy on any failure so the UI never crashes on a corrupt bundle.
 */
object TaxonomyLoader {

    private const val TAG = "TaxonomyLoader"

    @Volatile private var cached: Taxonomy? = null

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    fun load(context: Context): Taxonomy {
        cached?.let { return it }
        return try {
            val raw = context.assets.open("taxonomy.json").bufferedReader().use { it.readText() }
            val parsed = json.decodeFromString<Taxonomy>(raw)
            cached = parsed
            parsed
        } catch (t: Throwable) {
            Log.e(TAG, "Taxonomy parse failed", t)
            Taxonomy.empty
        }
    }
}

/** Picks PT / EN / ES based on device locale; defaults to EN for any other language. */
fun pickLocalized(pt: String, en: String, es: String): String {
    val lang = Locale.getDefault().language.lowercase()
    return when {
        lang.startsWith("pt") -> pt
        lang.startsWith("es") -> es
        else -> en
    }
}

fun Taxonomy.Location.localizedLabel(): String = pickLocalized(labelPt, labelEn, labelPt)
fun Taxonomy.TaskCategory.localizedLabel(): String = pickLocalized(labelPt, labelEn, labelPt)
fun Taxonomy.TaskCategory.localizedDescription(): String = pickLocalized(descriptionPt, descriptionEn, descriptionEs)
