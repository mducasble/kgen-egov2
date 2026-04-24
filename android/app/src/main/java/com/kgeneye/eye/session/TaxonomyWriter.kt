package com.kgeneye.eye.session

import com.kgeneye.eye.taxonomy.SessionTaxonomy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import java.io.File

/** Serialises [SessionTaxonomy] into `taxonomy_<code>.json`. */
@OptIn(ExperimentalSerializationApi::class)
object TaxonomyWriter {
    private val json = Json {
        prettyPrint = true
        prettyPrintIndent = "  "
        encodeDefaults = true
    }

    fun write(sessionDir: File, taxonomy: SessionTaxonomy) {
        val file = SessionFiles.file("taxonomy", "json", sessionDir)
        file.writeText(json.encodeToString(SessionTaxonomy.serializer(), taxonomy))
    }
}
