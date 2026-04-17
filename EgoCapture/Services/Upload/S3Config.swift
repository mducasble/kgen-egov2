import Foundation

struct S3Config {
    let bucket: String
    let region: String
    let accessKeyId: String
    let secretAccessKey: String

    var isValid: Bool {
        !bucket.isEmpty && !region.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
    }

    var host: String { "\(bucket).s3.\(region).amazonaws.com" }
    var baseURL: String { "https://\(host)" }

    /// Uses credentials from `EmbeddedAWSCredentials` (compile-time constants).
    static func embedded() -> S3Config {
        S3Config(
            bucket: EmbeddedAWSCredentials.bucket,
            region: EmbeddedAWSCredentials.region,
            accessKeyId: EmbeddedAWSCredentials.accessKeyId,
            secretAccessKey: EmbeddedAWSCredentials.secretAccessKey
        )
    }
}
