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
/// Wired into `DesignSystem/Thumbnail.swift` (UX-owned), which calls
/// `ImageStore.shared.thumbnail(for:maxPixelSize:)` directly. The compact
/// snapshot row carries a signed `thumbUrl` (backend `toCompactCoffee`,
/// `SNAPSHOT_VERSION=2`), so no separate batch media-URL endpoint was needed
/// after all — the URL rides along in the row itself.
actor ImageStore {
    static let shared = ImageStore()

    // Hard rule (CLAUDE.md): app + on-device data stays under 50 MB, always.
    // The binary + persisted snapshot are small and fixed; this image cache is
    // the only thing that grows, so it's the budget that matters — capped at
    // 30 MB to leave headroom under 50 MB total. `evictStaleEntries()` is run at
    // launch (see `RootView`) so this ceiling is actually enforced, not just
    // declared.
    private static let maxFullBytes = 30 * 1024 * 1024
    private static let maxAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// #177: the "display" size tier — for the hero/zoom/review images that
    /// today bypass this cache entirely via a raw `AsyncImage` at full
    /// 1080-px resolution (`CoffeeDetailView`/`ZoomableImageView`/
    /// `ReviewCardView`), each re-decoding on every appearance with no cache
    /// hit possible since the URL's `exp`/`sig` query rotates every sync.
    /// Wiring call sites through `thumbnail(for:maxPixelSize:)` with this
    /// constant (#180, iOS UX) gives them the same on-disk + in-memory
    /// caching the row thumbnails already have, one shared cache key per
    /// image rather than one per screen's own pixel size. Per CLAUDE.md's
    /// 30 MB cache budget, adding this tier must stay under the cap — the
    /// budget note in #177 estimates thumbs alone at ~5 MB today.
    static let displayMaxPixelSize: CGFloat = 1080

    private let session: URLSession
    private let cacheDirectory: URL
    private var inFlight: [String: Task<Data, Error>] = [:]

    /// #177: in-memory decoded-thumbnail cache, keyed by `(cacheKey,
    /// maxPixelSize)` — `Thumbnail.swift` re-requests on every `.task(id:)`,
    /// so the same (url, size) pair is decoded over and over on every
    /// scroll-in even though the on-disk bytes never changed. `NSCache` is
    /// safe to read/write concurrently, so it needs no actor isolation itself.
    private let decodedCache = NSCache<NSString, CGImage>()

    /// #177: keys already mtime-touched this launch. `loadData` used to call
    /// `touch` on every cache hit — every visible row, every scroll frame —
    /// turning a read into a disk read *and* an attribute write. Since
    /// eviction only needs "was this used recently, this launch or the last,"
    /// one touch per key per launch is enough.
    private var touchedThisLaunch: Set<String> = []

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
        let memoKey = Self.decodedCacheKey(for: urlString, maxPixelSize: maxPixelSize)
        if let cached = decodedCache.object(forKey: memoKey) {
            return cached
        }
        let data = try await loadData(for: urlString)
        // #177: decode off this actor's serial executor. `thumbnail` used to
        // decode inline, so two requests in flight — from two different rows
        // — decoded one at a time no matter how many CPU cores were idle;
        // `decodeThumbnail` is `static`/non-isolated, so `Task.detached` can
        // run it on the concurrent pool instead.
        let thumbnail = try await Task.detached(priority: .userInitiated) {
            try Self.decodeThumbnail(data: data, maxPixelSize: maxPixelSize)
        }.value
        decodedCache.setObject(thumbnail, forKey: memoKey)
        return thumbnail
    }

    private static func decodeThumbnail(data: Data, maxPixelSize: CGFloat) throws -> CGImage {
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

    private static func decodedCacheKey(for urlString: String, maxPixelSize: CGFloat) -> NSString {
        "\(cacheKey(for: urlString))@\(Int(maxPixelSize))" as NSString
    }

    private func loadData(for urlString: String) async throws -> Data {
        let key = Self.cacheKey(for: urlString)
        let fileURL = cacheDirectory.appendingPathComponent(key)

        if let cached = try? Data(contentsOf: fileURL) {
            touchOncePerLaunch(fileURL, key: key)
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

    private func touchOncePerLaunch(_ fileURL: URL, key: String) {
        guard !touchedThisLaunch.contains(key) else { return }
        touchedThisLaunch.insert(key)
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

    /// Purges files untouched for 30+ days and, if still over the 30 MB budget,
    /// the oldest-touched files until it's under (PLAN.md §5 / the CLAUDE.md
    /// 50 MB rule). Cheap — a single directory scan — so it runs at launch
    /// (`RootView`); there is no BGTask to run it in the background (#175(e):
    /// the placeholder identifier was removed rather than wired up).
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
