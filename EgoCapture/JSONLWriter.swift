import Foundation

/// Thread-safe JSONL file writer with batched async writes.
///
/// Records are buffered in memory and flushed to disk periodically
/// or when the buffer exceeds a threshold. This ensures that capture
/// callback threads are NEVER blocked by disk I/O.
///
/// Flush strategy:
///   - Every 50 records OR
///   - Every 1 second (whichever comes first)
///   - Immediately on close()
final class JSONLWriter {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    
    /// Dedicated queue for file I/O — capture queues never wait on this
    private let ioQueue = DispatchQueue(label: "com.egocapture.jsonlwriter.io", qos: .utility)
    /// Queue for buffer access (fast, in-memory only)
    private let bufferQueue = DispatchQueue(label: "com.egocapture.jsonlwriter.buffer", qos: .userInteractive)
    
    private var buffer: [Data] = []
    private let flushThreshold = 50
    private var flushTimer: DispatchSourceTimer?
    
    private(set) var rowCount: Int = 0
    
    let fileURL: URL
    
    init(fileURL: URL) throws {
        self.fileURL = fileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        self.fileHandle.seekToEndOfFile()
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        
        // Periodic flush timer (1 second)
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.flushBuffer()
        }
        timer.resume()
        self.flushTimer = timer
    }
    
    /// Append a Codable record. Non-blocking — buffers in memory.
    func append<T: Codable>(_ record: T) {
        bufferQueue.sync {
            do {
                let data = try encoder.encode(record)
                buffer.append(data)
                rowCount += 1
                
                if buffer.count >= flushThreshold {
                    let batch = buffer
                    buffer = []
                    ioQueue.async { [weak self] in
                        self?.writeBatch(batch)
                    }
                }
            } catch {
                print("[JSONLWriter] Encode failed: \(error)")
            }
        }
    }
    
    /// Flush remaining buffer and close the file.
    func close() {
        flushTimer?.cancel()
        flushTimer = nil
        
        // Final flush — synchronous to ensure all data is written
        bufferQueue.sync {
            let batch = buffer
            buffer = []
            ioQueue.sync {
                self.writeBatch(batch)
                self.fileHandle.synchronizeFile()
                self.fileHandle.closeFile()
            }
        }
    }
    
    /// Current file size in bytes.
    var fileSize: Int64 {
        ioQueue.sync {
            return Int64(fileHandle.offsetInFile)
        }
    }
    
    // MARK: - Private
    
    private func flushBuffer() {
        let batch: [Data] = bufferQueue.sync {
            let b = buffer
            buffer = []
            return b
        }
        if !batch.isEmpty {
            writeBatch(batch)
        }
    }
    
    /// Write a batch of pre-encoded JSON lines to disk.
    private func writeBatch(_ batch: [Data]) {
        guard !batch.isEmpty else { return }
        let newline = "\n".data(using: .utf8)!
        var combined = Data()
        for item in batch {
            combined.append(item)
            combined.append(newline)
        }
        fileHandle.write(combined)
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
