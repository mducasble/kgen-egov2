import Foundation

extension Notification.Name {
    /// Posted when a session is finalized on disk and should be queued for S3 upload.
    /// `userInfo`: `sessionId` (String), `sessionDir` (URL)
    static let egocaptureSessionReadyForUpload = Notification.Name("egocaptureSessionReadyForUpload")
}
