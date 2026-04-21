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

    /// Verbs the contributor selected for this activity (step 4). The three
    /// arrays are aligned by index — same semantic token in PT / EN / ES.
    /// Empty when recorded before this feature shipped or when the verb list
    /// was missing for the category.
    let selectedVerbsPt: [String]
    let selectedVerbsEn: [String]
    let selectedVerbsEs: [String]

    /// `"day"` or `"night"` — derived from the device clock at the moment
    /// recording finalises. Day = 06:00–17:59, Night = 18:00–05:59.
    let timeOfDay: String

    /// Hour-of-day [0, 23] used to compute `timeOfDay`. Captured so the
    /// downstream pipeline can recompute the bucket with a different rule
    /// without losing the original signal.
    let recordingHour: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case viewpointCode
        case scenarioCode
        case scenarioBucket
        case domainCode
        case locationCode
        case locationLabelPt
        case locationLabelEn
        case taskCategoryCode
        case taskCategoryGroup
        case taskCategoryLabelPt
        case taskCategoryLabelEn
        case selectedVerbsPt
        case selectedVerbsEn
        case selectedVerbsEs
        case timeOfDay
        case recordingHour
    }

    init(
        schemaVersion: String,
        viewpointCode: String,
        scenarioCode: String,
        scenarioBucket: String,
        domainCode: String,
        locationCode: String,
        locationLabelPt: String,
        locationLabelEn: String,
        taskCategoryCode: String,
        taskCategoryGroup: String,
        taskCategoryLabelPt: String,
        taskCategoryLabelEn: String,
        selectedVerbsPt: [String] = [],
        selectedVerbsEn: [String] = [],
        selectedVerbsEs: [String] = [],
        timeOfDay: String,
        recordingHour: Int
    ) {
        self.schemaVersion = schemaVersion
        self.viewpointCode = viewpointCode
        self.scenarioCode = scenarioCode
        self.scenarioBucket = scenarioBucket
        self.domainCode = domainCode
        self.locationCode = locationCode
        self.locationLabelPt = locationLabelPt
        self.locationLabelEn = locationLabelEn
        self.taskCategoryCode = taskCategoryCode
        self.taskCategoryGroup = taskCategoryGroup
        self.taskCategoryLabelPt = taskCategoryLabelPt
        self.taskCategoryLabelEn = taskCategoryLabelEn
        self.selectedVerbsPt = selectedVerbsPt
        self.selectedVerbsEn = selectedVerbsEn
        self.selectedVerbsEs = selectedVerbsEs
        self.timeOfDay = timeOfDay
        self.recordingHour = recordingHour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        viewpointCode = try c.decode(String.self, forKey: .viewpointCode)
        scenarioCode = try c.decode(String.self, forKey: .scenarioCode)
        scenarioBucket = try c.decode(String.self, forKey: .scenarioBucket)
        domainCode = try c.decode(String.self, forKey: .domainCode)
        locationCode = try c.decode(String.self, forKey: .locationCode)
        locationLabelPt = try c.decode(String.self, forKey: .locationLabelPt)
        locationLabelEn = try c.decode(String.self, forKey: .locationLabelEn)
        taskCategoryCode = try c.decode(String.self, forKey: .taskCategoryCode)
        taskCategoryGroup = try c.decode(String.self, forKey: .taskCategoryGroup)
        taskCategoryLabelPt = try c.decode(String.self, forKey: .taskCategoryLabelPt)
        taskCategoryLabelEn = try c.decode(String.self, forKey: .taskCategoryLabelEn)
        selectedVerbsPt = try c.decodeIfPresent([String].self, forKey: .selectedVerbsPt) ?? []
        selectedVerbsEn = try c.decodeIfPresent([String].self, forKey: .selectedVerbsEn) ?? []
        selectedVerbsEs = try c.decodeIfPresent([String].self, forKey: .selectedVerbsEs) ?? []
        timeOfDay = try c.decode(String.self, forKey: .timeOfDay)
        recordingHour = try c.decode(Int.self, forKey: .recordingHour)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(viewpointCode, forKey: .viewpointCode)
        try c.encode(scenarioCode, forKey: .scenarioCode)
        try c.encode(scenarioBucket, forKey: .scenarioBucket)
        try c.encode(domainCode, forKey: .domainCode)
        try c.encode(locationCode, forKey: .locationCode)
        try c.encode(locationLabelPt, forKey: .locationLabelPt)
        try c.encode(locationLabelEn, forKey: .locationLabelEn)
        try c.encode(taskCategoryCode, forKey: .taskCategoryCode)
        try c.encode(taskCategoryGroup, forKey: .taskCategoryGroup)
        try c.encode(taskCategoryLabelPt, forKey: .taskCategoryLabelPt)
        try c.encode(taskCategoryLabelEn, forKey: .taskCategoryLabelEn)
        try c.encode(selectedVerbsPt, forKey: .selectedVerbsPt)
        try c.encode(selectedVerbsEn, forKey: .selectedVerbsEn)
        try c.encode(selectedVerbsEs, forKey: .selectedVerbsEs)
        try c.encode(timeOfDay, forKey: .timeOfDay)
        try c.encode(recordingHour, forKey: .recordingHour)
    }

    /// Display-ready activity label for UI surfaces, resolved through the
    /// same `task.<code>` catalog key used by ``Taxonomy/TaskCategory``.
    /// Falls back to ``taskCategoryLabelPt`` (the serialised canonical
    /// label) when the current locale has no translation.
    var taskCategoryLabelLocalized: String {
        TaxonomyLocalization.resolve(
            key: "task.\(taskCategoryCode)",
            fallback: taskCategoryLabelPt
        )
    }

    /// Display-ready location label. See ``taskCategoryLabelLocalized`` for
    /// the resolution strategy.
    var locationLabelLocalized: String {
        TaxonomyLocalization.resolve(
            key: "location.\(locationCode)",
            fallback: locationLabelPt
        )
    }

    /// Comma-separated verbs in the current UI language for chrome / recap.
    var selectedVerbsLocalizedLine: String {
        let lang = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let list: [String]
        if lang.hasPrefix("pt") {
            list = selectedVerbsPt
        } else if lang.hasPrefix("es") {
            list = selectedVerbsEs
        } else {
            list = selectedVerbsEn
        }
        return list.joined(separator: ", ")
    }

    /// Display title for UI surfaces (briefing chrome, recording overlay).
    /// Uses the localized variants so the chrome follows the UI locale,
    /// while the serialised `locationLabelPt` / `taskCategoryLabelPt` stay
    /// fixed for the downstream pipeline.
    var displayTitle: String {
        "\(taskCategoryLabelLocalized) · \(locationLabelLocalized)"
    }

    static func dayOrNight(for date: Date = Date(), calendar: Calendar = .current) -> (label: String, hour: Int) {
        let hour = calendar.component(.hour, from: date)
        let label = (hour >= 6 && hour < 18) ? "day" : "night"
        return (label, hour)
    }
}
