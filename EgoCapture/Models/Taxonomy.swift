import Foundation

/// Codable mirror of `Resources/taxonomy.json`.
///
/// The JSON is loaded once (lazily) and cached for the lifetime of the
/// process — it's small (~17 KB) and read-only.
struct Taxonomy: Codable, Hashable {
    let schemaVersion: String
    let generatedAt: String
    let descriptionPt: String
    let descriptionEn: String
    let descriptionEs: String
    let viewpoints: [Viewpoint]
    let domains: [Domain]
    let scenarios: [Scenario]
    let locations: [Location]
    let taskCategories: [TaskCategory]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case descriptionPt = "description_pt"
        case descriptionEn = "description_en"
        case descriptionEs = "description_es"
        case viewpoints
        case domains
        case scenarios
        case locations
        case taskCategories = "task_categories"
    }

    struct Viewpoint: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let descriptionPt: String
        let descriptionEn: String
        let descriptionEs: String

        var id: String { code }

        var localizedDescription: String {
            TaxonomyLocalizedDescription.pick(pt: descriptionPt, en: descriptionEn, es: descriptionEs)
        }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case descriptionPt = "description_pt"
            case descriptionEn = "description_en"
            case descriptionEs = "description_es"
        }
    }

    struct Domain: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let descriptionPt: String
        let descriptionEn: String
        let descriptionEs: String

        var id: String { code }

        var localizedDescription: String {
            TaxonomyLocalizedDescription.pick(pt: descriptionPt, en: descriptionEn, es: descriptionEs)
        }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case descriptionPt = "description_pt"
            case descriptionEn = "description_en"
            case descriptionEs = "description_es"
        }
    }

    struct Scenario: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let descriptionPt: String
        let descriptionEn: String
        let descriptionEs: String

        var id: String { code }

        var localizedDescription: String {
            TaxonomyLocalizedDescription.pick(pt: descriptionPt, en: descriptionEn, es: descriptionEs)
        }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case descriptionPt = "description_pt"
            case descriptionEn = "description_en"
            case descriptionEs = "description_es"
        }
    }

    struct Location: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let domain: String
        let scenario: String

        var id: String { code }

        /// Display-ready label resolved through the `Localizable.xcstrings`
        /// key `location.<code>`. Falls back to ``labelPt`` when the key is
        /// missing from the catalog, so new codes still render before the
        /// catalog is updated. `labelPt` remains the canonical serialised
        /// label that goes into `taxonomy.json` next to the bucket.
        var localizedLabel: String {
            TaxonomyLocalization.resolve(key: "location.\(code)", fallback: labelPt)
        }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case domain
            case scenario
        }
    }

    struct TaskCategory: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let descriptionPt: String
        let descriptionEn: String
        let descriptionEs: String
        let group: String

        var id: String { code }

        /// Display-ready label resolved through the `Localizable.xcstrings`
        /// key `task.<code>`, with ``labelPt`` as the fallback. See
        /// ``Location/localizedLabel`` for the same rationale.
        var localizedLabel: String {
            TaxonomyLocalization.resolve(key: "task.\(code)", fallback: labelPt)
        }

        /// Long-form explanation of the activity, in the current UI language.
        var localizedDescription: String {
            TaxonomyLocalizedDescription.pick(pt: descriptionPt, en: descriptionEn, es: descriptionEs)
        }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case descriptionPt = "description_pt"
            case descriptionEn = "description_en"
            case descriptionEs = "description_es"
            case group
        }
    }
}

// MARK: - Localization helper

/// Thin wrapper around `Bundle.localizedString(forKey:value:table:)` that
/// treats the fallback as both the "value if missing" and the returned
/// string when no translation exists for the current locale. The built-in
/// `String(localized:)` APIs require the key to be a `StaticString`, which
/// doesn't work for dynamic keys like `location.\(code)`.
enum TaxonomyLocalization {
    static func resolve(key: String, fallback: String) -> String {
        let translated = Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
        return translated
    }
}

/// Picks among PT / EN / ES strings bundled in `taxonomy.json` based on the
/// device's primary UI language (`Locale.current`). Falls back to English
/// for any language other than Portuguese or Spanish.
enum TaxonomyLocalizedDescription {
    static func pick(pt: String, en: String, es: String) -> String {
        let lang = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if lang.hasPrefix("pt") { return pt }
        if lang.hasPrefix("es") { return es }
        return en
    }
}

// MARK: - Bundle loader

enum TaxonomyLoader {
    /// Lazily-loaded shared instance. Falls back to a minimal stub if the
    /// resource is missing, so the picker UI keeps working even if the
    /// bundle inclusion was forgotten.
    static let shared: Taxonomy = {
        if let url = Bundle.main.url(forResource: "taxonomy", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            do {
                return try JSONDecoder().decode(Taxonomy.self, from: data)
            } catch {
                print("[TaxonomyLoader] Decode failed: \(error)")
            }
        } else {
            print("[TaxonomyLoader] taxonomy.json not found in main bundle.")
        }
        return Taxonomy.empty
    }()
}

extension Taxonomy {
    static let empty = Taxonomy(
        schemaVersion: "0.0.0",
        generatedAt: "",
        descriptionPt: "Stub — taxonomy.json missing from bundle",
        descriptionEn: "Stub — taxonomy.json missing from bundle",
        descriptionEs: "Stub — taxonomy.json missing from bundle",
        viewpoints: [],
        domains: [],
        scenarios: [],
        locations: [],
        taskCategories: []
    )
}

// MARK: - Wizard helpers

extension Taxonomy {
    /// User-facing scenario buckets after collapsing the 4 raw scenarios into
    /// a binary indoor/outdoor choice (per product decision). `semi_outdoor`
    /// and `transition` map to outdoor.
    enum BinaryScenario: String, CaseIterable, Identifiable, Codable {
        case indoor
        case outdoor

        var id: String { rawValue }

        var labelPt: String {
            switch self {
            case .indoor: return "Interno"
            case .outdoor: return "Externo"
            }
        }

        /// Localized label resolved via the current UI locale. Prefer this over
        /// ``labelPt`` in any on-screen context — ``labelPt`` is kept for JSON
        /// serialization compatibility (downstream pipeline still expects the
        /// Portuguese name as the canonical wizard label).
        var localizedLabel: String {
            switch self {
            case .indoor: return String(localized: "Indoor")
            case .outdoor: return String(localized: "Outdoor")
            }
        }

        var iconName: String {
            switch self {
            case .indoor: return "house.fill"
            case .outdoor: return "tree.fill"
            }
        }

        /// Raw taxonomy scenario codes that fold into this bucket.
        var rawScenarioCodes: Set<String> {
            switch self {
            case .indoor: return ["indoor"]
            case .outdoor: return ["outdoor", "semi_outdoor", "transition"]
            }
        }
    }

    /// All locations belonging to the given user-facing scenario bucket.
    func locations(matching bucket: BinaryScenario) -> [Location] {
        let codes = bucket.rawScenarioCodes
        return locations.filter { codes.contains($0.scenario) }
    }

    /// Localized label for the raw scenario code (e.g. "indoor" → "Interno").
    func scenarioLabelPt(for code: String) -> String? {
        scenarios.first { $0.code == code }?.labelPt
    }
}
