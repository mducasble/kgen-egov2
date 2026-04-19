import Foundation

/// Public-facing AWS credentials used by the upload pipeline.
///
/// The access key / secret are kept in a sibling file `EmbeddedAWSSecrets.swift`
/// which is **gitignored**. If you just cloned this repo, copy
/// `EmbeddedAWSSecrets.swift.example` to `EmbeddedAWSSecrets.swift` and fill in
/// the real IAM credentials before building.
enum EmbeddedAWSCredentials {
    static let bucket = "kaivideo"
    static let region = "us-east-1"

    static let accessKeyId = EmbeddedAWSSecrets.accessKeyId
    static let secretAccessKey = EmbeddedAWSSecrets.secretAccessKey
}
