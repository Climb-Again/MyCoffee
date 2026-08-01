import Foundation
import CryptoKit
import CoreGraphics
import ImageIO

enum ImageStoreError: Error {
    case badURL
    case httpError
    case decodeFailed
}

/// Disk-backed, downsample-on-write image cache — deliberately not
/// `URLCache` (PLAN.md §5): `URLCache`'s `diskCapacity` is a soft LRU budget
/// that would happily evict a ten-year photo archive's only local copy, and
/// it gives no hook to downsample on write, so a 12 MP JPEG would decode to a
/// ~48 MB bitmap in a scrolling list. In-flight requests for the same URL are
/// coalesced so a fast scroll can't launch duplicate downloads.
///
/// Not yet wired into `DesignSystem/Thumbnail.swift` (UX-owned) — that view
/// still uses a plain `AsyncImage`, and the compact snapshot doesn't carry a
/// per-row image URL at all today (only `GET /api/coffees/:publicId` does;
/// see the batch-media-URL gap noted in `status/BACKLOG.md`). This actor is
/// the reusable engine for whenever both land; flagged in
/// `status/ios-shell.md` as follow-up wiring for the UX lane.
actor ImageStore {
    static let shared = ImageStore()

    private static let maxFullBytes = 250 * 1024 * 1024
    private static let maxAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    private let session: URLSession
    private let cacheDirectory: URL
    private var inFlight: [String: Task<Data, Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = base.appendingPathComponent("CoffeeImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// A downsampled `CGImage`, decoded via `CGImageSourceCreateThumbnailAtIndex`
    /// rather than `UIImage(data:)` + resize — the latter fully decodes the
    /// source bitmap before scaling it down, defeating the point.
    /// `maxPixelSize` is already display-scale-adjusted; the caller (a
    /// SwiftUI view, once wired) knows `@Environment(\.displayScale)`.
    func thumbnail(for urlString: String, maxPixelSize: CGFloat) async throws -> CGImage {
        let data = try await loadData(for: urlString)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.decodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageStoreError.decodeFailed
        }
        return thumbnail
    }

    private func loadData(for urlString: String) async throws -> Data {
        let key = Self.cacheKey(for: urlString)
        let fileURL = cacheDirectory.appendingPathComponent(key)

        if let cached = try? Data(contentsOf: fileURL) {
            touch(fileURL)
            return cached
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            guard let url = URL(string: urlString) else { throw ImageStoreError.badURL }
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ImageStoreError.httpError
            }
            try? data.write(to: fileURL, options: .atomic)
            return data
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    // The `exp`/`sig` query rotates every sync (PLAN.md §3's signed URLs), so
    // keying the cache on the full URL string would cache-miss on every
    // refresh — strip the query before hashing.
    private static func cacheKey(for urlString: String) -> String {
        let unsigned: String
        if let url = URL(string: urlString), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.query = nil
            unsigned = components.string ?? urlString
        } else {
            unsigned = urlString
        }
        let digest = SHA256.hash(data: Data(unsigned.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Purges fulls untouched for 30+ days and, if still over the 250 MB
    /// budget, the oldest-touched files until it's under (PLAN.md §5). Call
    /// from the BGTask handler, not on every launch.
    func evictStaleEntries() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let now = Date()
        var kept: [(url: URL, date: Date, size: Int)] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            if now.timeIntervalSince(date) > Self.maxAgeSeconds {
                try? fm.removeItem(at: entry)
            } else {
                kept.append((entry, date, size))
            }
        }

        var totalBytes = kept.reduce(0) { $0 + $1.size }
        guard totalBytes > Self.maxFullBytes else { return }
        for item in kept.sorted(by: { $0.date < $1.date }) {
            guard totalBytes > Self.maxFullBytes else { break }
            try? fm.removeItem(at: item.url)
            totalBytes -= item.size
        }
    }
}
