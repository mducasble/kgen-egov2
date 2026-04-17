import Foundation

/// Shared notification name for the S3 upload pipeline (avoids `Notification.Name` extension clashes).
enum UploadNotificationName {
    static let sessionReady = Notification.Name("egocaptureSessionReadyForUpload")
}
