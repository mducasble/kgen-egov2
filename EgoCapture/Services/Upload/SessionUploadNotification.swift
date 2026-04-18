import Foundation

extension Notification.Name {
    /// Posted when a session is packaged and ready for S3 upload (must match observer in UploadManager).
    static let egocaptureSessionReadyForUpload = Notification.Name("egocaptureSessionReadyForUpload")
}
