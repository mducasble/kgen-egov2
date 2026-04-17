import Foundation

/// Uploads individual files to S3 with retry and exponential backoff.
/// Uses foreground URLSession with async/await (background session is managed by UploadManager).
actor S3UploadService {

    private let config: S3Config
    private let session: URLSession
    private let maxRetries = 3

    init(config: S3Config) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Upload a single file to S3. Returns true on success.
    func uploadFile(localURL: URL, s3Key: String) async -> UploadResult {
        let contentType = Self.contentType(for: localURL.pathExtension)

        for attempt in 1...maxRetries {
            do {
                let request = try AWSSigner.signedUploadPutRequest(
                    config: config,
                    objectKey: s3Key,
                    fileURL: localURL,
                    contentType: contentType
                )

                let (_, response) = try await session.upload(for: request, fromFile: localURL)

                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(attempt: attempt, error: "Invalid response")
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return .success(attempt: attempt)
                }

                let errorMsg = "HTTP \(httpResponse.statusCode)"
                if attempt < maxRetries {
                    let delay = Self.backoffDelay(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                return .failure(attempt: attempt, error: errorMsg)

            } catch {
                if attempt < maxRetries {
                    let delay = Self.backoffDelay(attempt: attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                return .failure(attempt: attempt, error: error.localizedDescription)
            }
        }

        return .failure(attempt: maxRetries, error: "Max retries exceeded")
    }

    enum UploadResult {
        case success(attempt: Int)
        case failure(attempt: Int, error: String)

        var succeeded: Bool {
            if case .success = self { return true }
            return false
        }
    }

    private static func backoffDelay(attempt: Int) -> Double {
        pow(2.0, Double(attempt)) + Double.random(in: 0...1)
    }

    private static func contentType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp4": return "video/mp4"
        case "json": return "application/json"
        case "jsonl": return "application/x-ndjson"
        default: return "application/octet-stream"
        }
    }
}
