import Foundation

/// AWS credentials embedded at build time. End users never see or edit these.
/// Replace the two key strings below before shipping internal / TestFlight builds.
enum EmbeddedAWSCredentials {
    static let bucket = "kaivideo"
    static let region = "us-east-1"

    /// IAM user access key ID (starts with AKIA…).
    static let accessKeyId = ""

    /// IAM secret access key (paired with accessKeyId).
    static let secretAccessKey = ""
}
