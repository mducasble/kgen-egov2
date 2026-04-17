import Foundation
import CryptoKit

/// AWS Signature Version 4 signer for S3 PUT requests.
/// Pure Swift, no SDK dependency.
enum AWSSigner {

    static func signedPutRequest(
        config: S3Config,
        objectKey: String,
        fileURL: URL,
        contentType: String
    ) throws -> URLRequest {
        let fileData = try Data(contentsOf: fileURL)
        let payloadHash = SHA256.hash(data: fileData).hexString

        let now = Date()
        let amzDate = Self.amzDateFormatter.string(from: now)
        let dateStamp = Self.dateStampFormatter.string(from: now)

        let url = URL(string: "\(config.baseURL)/\(objectKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? objectKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(config.host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")

        let signedHeaders = "content-length;content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "content-length:\(fileData.count)",
            "content-type:\(contentType)",
            "host:\(config.host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            "PUT",
            "/\(objectKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? objectKey)",
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(config.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        let signingKey = Self.deriveSigningKey(
            secretKey: config.secretAccessKey,
            dateStamp: dateStamp,
            region: config.region,
            service: "s3"
        )

        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: signingKey
        ).hexString

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        return request
    }

    /// For background URLSession uploads we need to write the file, not set httpBody.
    /// This returns (signedRequest, fileURL) — the caller uploads the file at fileURL.
    static func signedUploadPutRequest(
        config: S3Config,
        objectKey: String,
        fileURL: URL,
        contentType: String
    ) throws -> URLRequest {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attrs[.size] as? Int ?? 0

        let payloadHash = "UNSIGNED-PAYLOAD"

        let now = Date()
        let amzDate = Self.amzDateFormatter.string(from: now)
        let dateStamp = Self.dateStampFormatter.string(from: now)

        let encodedKey = objectKey
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        let url = URL(string: "\(config.baseURL)/\(encodedKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(config.host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        let signedHeaders = "content-length;content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "content-length:\(fileSize)",
            "content-type:\(contentType)",
            "host:\(config.host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            "PUT",
            "/\(encodedKey)",
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(config.region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        ].joined(separator: "\n")

        let signingKey = Self.deriveSigningKey(
            secretKey: config.secretAccessKey,
            dateStamp: dateStamp,
            region: config.region,
            service: "s3"
        )

        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: signingKey
        ).hexString

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Private

    private static func deriveSigningKey(
        secretKey: String, dateStamp: String, region: String, service: String
    ) -> SymmetricKey {
        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return SymmetricKey(data: kSigning)
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let k = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: k)
        return Data(mac)
    }

    private static let amzDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension HMAC<SHA256>.MAC {
    var hexString: String {
        Data(self).map { String(format: "%02x", $0) }.joined()
    }
}
