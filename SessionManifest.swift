import Foundation

/// Manifest listing all artifacts produced in a session.
struct SessionManifest: Codable {
    let sessionId: String
    let createdAtEpochMs: Double
    let artifacts: [Artifact]
    
    struct Artifact: Codable {
        let filename: String
        let type: String  // "video", "jsonl", "json"
        let description: String
        let sizeBytes: Int64
        let rowCount: Int? // for JSONL files
    }
}
