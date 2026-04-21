import Foundation

/// Bundle mirror of `Resources/task_verbs.json` — per-`task_category_code`
/// verb lists in PT / EN / ES (parallel indices).
struct TaskVerbsBundle: Codable {
    let schemaVersion: String
    let generatedAt: String
    let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case entries
    }

    struct Entry: Codable, Hashable {
        let taskCategoryCode: String
        let verbsPt: [String]
        let verbsEn: [String]
        let verbsEs: [String]

        enum CodingKeys: String, CodingKey {
            case taskCategoryCode = "task_category_code"
            case verbsPt = "verbs_pt"
            case verbsEn = "verbs_en"
            case verbsEs = "verbs_es"
        }
    }
}

enum TaskVerbsLoader {
    /// Lazily-loaded index keyed by `task_category_code`.
    static let shared: [String: TaskVerbsBundle.Entry] = {
        guard let url = Bundle.main.url(forResource: "task_verbs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[TaskVerbsLoader] task_verbs.json missing from bundle.")
            return [:]
        }
        do {
            let bundle = try JSONDecoder().decode(TaskVerbsBundle.self, from: data)
            return Dictionary(uniqueKeysWithValues: bundle.entries.map { ($0.taskCategoryCode, $0) })
        } catch {
            print("[TaskVerbsLoader] Decode failed: \(error)")
            return [:]
        }
    }()

    static func verbs(for taskCategoryCode: String) -> TaskVerbsBundle.Entry? {
        shared[taskCategoryCode]
    }
}

// MARK: - Display casing

extension String {
    /// Uppercases only the first character of a verb token for on-screen use.
    /// Underlying `task_verbs.json` and `taxonomy.json` stay lowercased.
    var verbDisplayCased: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}
