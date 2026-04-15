import Foundation

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
    
    /// Create a new session directory with UUID-based ID.
    func createSession() -> (id: String, directory: URL) {
        let id = UUID().uuidString
        let dir = sessionsRoot.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
