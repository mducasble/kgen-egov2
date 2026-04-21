import Foundation

/// Codable mirror of `Resources/taxonomy.json`.
///
/// The JSON is loaded once (lazily) and cached for the lifetime of the
/// process — it's small (~17 KB) and read-only.
struct Taxonomy: Codable, Hashable {
    let schemaVersion: String
    let generatedAt: String
    let description: String
    let viewpoints: [Viewpoint]
    let domains: [Domain]
    let scenarios: [Scenario]
    let locations: [Location]
    let taskCategories: [TaskCategory]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case description
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
        let description: String

        var id: String { code }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case description
        }
    }

    struct Domain: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let description: String

        var id: String { code }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case description
        }
    }

    struct Scenario: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let description: String

        var id: String { code }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case description
        }
    }

    struct Location: Codable, Hashable, Identifiable {
        let code: String
        let labelPt: String
        let labelEn: String
        let domain: String
        let scenario: String

        var id: String { code }

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
        let description: String
        let group: String

        var id: String { code }

        enum CodingKeys: String, CodingKey {
            case code
            case labelPt = "label_pt"
            case labelEn = "label_en"
            case description
            case group
        }
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
        description: "Stub — taxonomy.json missing from bundle",
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
