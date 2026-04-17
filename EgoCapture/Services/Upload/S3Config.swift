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

    static func fromUserDefaults() -> S3Config {
        let ud = UserDefaults.standard
        return S3Config(
            bucket: ud.string(forKey: "s3_bucket") ?? "kaivideo",
            region: ud.string(forKey: "s3_region") ?? "us-east-1",
            accessKeyId: ud.string(forKey: "s3_access_key") ?? "",
            secretAccessKey: ud.string(forKey: "s3_secret_key") ?? ""
        )
    }
}
