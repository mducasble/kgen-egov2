import Foundation

/// What the wizard hands off to the recording pipeline and what the
/// orchestrator serialises into `taxonomy.json` next to the session's
/// `metadata.json`.
///
/// Intentionally lives outside the MCAP scope — it's a session-side
/// annotation file, not a synchronised data stream.
struct SessionTaxonomy: Codable, Hashable {
    /// Schema version of the taxonomy this selection was made against.
    let schemaVersion: String

    /// Always `"egocentric"` — the first wizard step is hidden because the
    /// app only ever produces egocentric captures.
    let viewpointCode: String

    /// Raw scenario from the taxonomy (`indoor`, `outdoor`, `semi_outdoor`, `transition`).
    let scenarioCode: String

    /// User-facing binary bucket the wizard surfaces (`indoor` or `outdoor`).
    let scenarioBucket: String

    /// Domain inferred from the chosen location (e.g. `residential`).
    let domainCode: String

    let locationCode: String
    let locationLabelPt: String
    let locationLabelEn: String

    let taskCategoryCode: String
    let taskCategoryGroup: String
    let taskCategoryLabelPt: String
    let taskCategoryLabelEn: String

    /// `"day"` or `"night"` — derived from the device clock at the moment
    /// recording finalises. Day = 06:00–17:59, Night = 18:00–05:59.
    let timeOfDay: String

    /// Hour-of-day [0, 23] used to compute `timeOfDay`. Captured so the
    /// downstream pipeline can recompute the bucket with a different rule
    /// without losing the original signal.
    let recordingHour: Int

    /// Display title for UI surfaces (briefing chrome, recording overlay).
    /// Defaults to the task label, prefixed by the location for context.
    var displayTitle: String {
        "\(taskCategoryLabelPt) · \(locationLabelPt)"
    }

    static func dayOrNight(for date: Date = Date(), calendar: Calendar = .current) -> (label: String, hour: Int) {
        let hour = calendar.component(.hour, from: date)
        let label = (hour >= 6 && hour < 18) ? "day" : "night"
        return (label, hour)
    }
}
