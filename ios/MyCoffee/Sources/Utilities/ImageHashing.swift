import CryptoKit
import Foundation

extension Data {
    /// Lowercase hex SHA-256, the content-addressing shape the photo upload
    /// endpoints require (`POST /api/photos/manifest`'s `contentSha256`,
    /// `PUT /api/photos/:sourceId/image?sha256=`) — PLAN.md §6.8, #75/#76.
    /// `CryptoKit` is an Apple system framework, not an SPM dependency.
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
