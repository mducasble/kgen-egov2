import Foundation
import Security

// MARK: - Session Code Generator

/// Generates short, URL-safe, filesystem-safe session identifiers.
///
/// Default: 12 characters Base64url (`A–Z`, `a–z`, `0–9`, `-`, `_`).
/// Entropy: 72 bits → collision probability < 10⁻⁶ for 10⁸ sessions.
enum SessionCodeGenerator {

    /// Length of the emitted code in characters.
    static let length: Int = 12

    /// 9 random bytes encode exactly to 12 Base64 chars with zero padding.
    private static let rawByteCount: Int = 9

    /// Generate a new code using the cryptographic RNG.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: rawByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fallback: arc4random (still CSPRNG-backed on Darwin).
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Detect whether a given id is in the new short-code format
    /// (vs. a legacy UUID like `550E8400-E29B-41D4-A716-446655440000`).
    static func isShortCode(_ id: String) -> Bool {
        guard id.count == length else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return id.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Session Files

/// Centralized filename conventions for artifacts inside a session directory.
/// All "new-format" filenames end with `_{sessionCode}.{ext}` so every artifact
/// is self-identifying when extracted from its directory.
enum SessionFiles {

    /// Build the new-format filename for a given session.
    ///   `name("video", "mp4", for: "qB7nX3_mL9Vz")` → `"video_qB7nX3_mL9Vz.mp4"`
    static func name(_ base: String, _ ext: String, for code: String) -> String {
        return "\(base)_\(code).\(ext)"
    }

    /// Build the URL of a new-format artifact.
    static func url(_ base: String, _ ext: String, in sessionDir: URL) -> URL {
        let code = sessionDir.lastPathComponent
        return sessionDir.appendingPathComponent(name(base, ext, for: code))
    }

    /// Resolve an artifact URL, preferring the new-format filename but falling
    /// back to the legacy un-suffixed name for sessions recorded before the migration.
    ///
    /// Returns `nil` only if neither form exists on disk.
    static func resolveExisting(_ base: String, _ ext: String, in sessionDir: URL) -> URL? {
        let fm = FileManager.default
        let newURL = url(base, ext, in: sessionDir)
        if fm.fileExists(atPath: newURL.path) { return newURL }
        let legacyURL = sessionDir.appendingPathComponent("\(base).\(ext)")
        if fm.fileExists(atPath: legacyURL.path) { return legacyURL }
        return nil
    }

    /// Canonical list of metadata artifacts produced per session (excludes chunks and video).
    static let metadataBases: [(base: String, ext: String)] = [
        ("imu",                        "jsonl"),
        ("video_timestamps",           "jsonl"),
        ("metadata",                   "json"),
        ("technical_validation",       "json"),
        ("session_manifest",           "json"),
        ("camera_format_diagnostics",  "json"),
    ]

    /// Dynamic metadata filename list for upload, tailored to the session's code.
    /// For legacy sessions (UUID dir + un-suffixed files), also returns the legacy names
    /// so the upload list matches whatever is actually on disk.
    static func metadataFilenames(in sessionDir: URL) -> [String] {
        let fm = FileManager.default
        let code = sessionDir.lastPathComponent
        return metadataBases.compactMap { (base, ext) in
            let newName = name(base, ext, for: code)
            if fm.fileExists(atPath: sessionDir.appendingPathComponent(newName).path) {
                return newName
            }
            let legacyName = "\(base).\(ext)"
            if fm.fileExists(atPath: sessionDir.appendingPathComponent(legacyName).path) {
                return legacyName
            }
            return nil
        }
    }
}

// MARK: - Session Manager

/// Manages session directories under the app's Documents folder.
final class SessionManager {

    static let shared = SessionManager()

    /// Root sessions directory
    var sessionsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("sessions", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
    }

    /// Create a new session directory with a short Base64url id.
    /// Retries on the astronomically unlikely chance of collision with an existing directory.
    func createSession() -> (id: String, directory: URL) {
        let fm = FileManager.default
        for _ in 0..<4 {
            let id = SessionCodeGenerator.generate()
            let dir = sessionsRoot.appendingPathComponent(id, isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                return (id, dir)
            }
        }
        // Give up after 4 retries — still return a fresh id (caller will likely fail writing if colliding).
        let id = SessionCodeGenerator.generate()
        let dir = sessionsRoot.appendingPathComponent(id, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return (id, dir)
    }

    /// List all existing session IDs sorted by creation date (newest first).
    func listSessions() -> [(id: String, directory: URL, date: Date)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.compactMap { url in
            let id = url.lastPathComponent
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return (id, url, date)
        }.sorted { $0.date > $1.date }
    }

    /// Delete a session and all its artifacts.
    func deleteSession(id: String) throws {
        let dir = sessionsRoot.appendingPathComponent(id)
        try FileManager.default.removeItem(at: dir)
    }

    /// Get total size of a session directory.
    func sessionSize(id: String) -> Int64 {
        let dir = sessionsRoot.appendingPathComponent(id)
        return directorySize(at: dir)
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
