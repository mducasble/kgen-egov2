import Foundation

/// Thread-safe JSONL file writer that streams records to disk.
/// Each call to `append` writes one JSON line immediately to avoid data loss.
final class JSONLWriter {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private let queue = DispatchQueue(label: "com.egocapture.jsonlwriter", qos: .utility)
    private(set) var rowCount: Int = 0
    
    let fileURL: URL
    
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        self.fileHandle.seekToEndOfFile()
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        // No pretty printing — each row must be a single line
    }
    
    /// Append a Codable record as a single JSON line.
    func append<T: Codable>(_ record: T) {
        queue.sync {
            do {
                let data = try encoder.encode(record)
                self.fileHandle.write(data)
                self.fileHandle.write("\n".data(using: .utf8)!)
                self.rowCount += 1
            } catch {
                print("[JSONLWriter] Failed to encode record: \(error)")
            }
        }
    }
    
    /// Flush and close the file.
    func close() {
        queue.sync {
            self.fileHandle.synchronizeFile()
            self.fileHandle.closeFile()
        }
    }
    
    /// Current file size in bytes.
    var fileSize: Int64 {
        queue.sync {
            let offset = fileHandle.offsetInFile
            return Int64(offset)
        }
    }
}

/// Helper to write a single JSON file (not JSONL).
enum JSONFileWriter {
    static func write<T: Codable>(_ value: T, to url: URL, prettyPrinted: Bool = true) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
