package com.kgeneye.eye.taxonomy

import kotlinx.serialization.Serializable
import java.util.Calendar

/**
 * Session-side annotation — serialised next to `metadata.json` as
 * `taxonomy_<code>.json`. Matches the iOS `SessionTaxonomy` shape so both
 * clients produce the same payload for the downstream pipeline.
 *
 * Property names are chosen to align with the Swift `CodingKeys` (camelCase).
 */
@Serializable
data class SessionTaxonomy(
    val schemaVersion: String,
    val viewpointCode: String = "egocentric",
    val scenarioCode: String,
    val scenarioBucket: String,
    val domainCode: String,
    val locationCode: String,
    val locationLabelPt: String,
    val locationLabelEn: String,
    val taskCategoryCode: String,
    val taskCategoryGroup: String,
    val taskCategoryLabelPt: String,
    val taskCategoryLabelEn: String,
    val selectedVerbsPt: List<String> = emptyList(),
    val selectedVerbsEn: List<String> = emptyList(),
    val selectedVerbsEs: List<String> = emptyList(),
    val timeOfDay: String,
    val recordingHour: Int,
) {
    companion object {
        fun dayOrNight(calendar: Calendar = Calendar.getInstance()): Pair<String, Int> {
            val hour = calendar.get(Calendar.HOUR_OF_DAY)
            val label = if (hour in 6..17) "day" else "night"
            return label to hour
        }
    }
}
