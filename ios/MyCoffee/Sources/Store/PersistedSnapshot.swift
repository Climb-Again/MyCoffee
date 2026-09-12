import Foundation

/// The on-disk form of PLAN.md §5's "one versioned JSON file" — written
/// atomically after every successful sync, decoded off-main at cold start so
/// the listing never shows blank while the network catches up.
struct PersistedSnapshot: Codable {
    let schemaVersion: Int
    let lastSyncAt: Date
    let coffees: [Coffee]
    let vocabulary: Vocabulary
    let searchTexts: [String: String]
    let profilesByID: [Int: Profile]
    /// When `sync` last fetched with `since: nil` (a full snapshot, not a
    /// delta). `Optional` so an old persisted file with no such key decodes
    /// fine — `nil` reads as "force one now" (#175(d)). Forces a fresh full
    /// sync every 14 days so every coffee's signed `thumbUrl` (which expires
    /// after 30 days, `coffees.js:62`) gets renewed before it goes stale, even
    /// for a coffee a delta sync would otherwise never re-send.
    let lastFullSyncAt: Date?
    /// The `ETag` `/api/snapshot/text` returned last time, so `sync` can send
    /// `If-None-Match` and skip re-decoding the ~300 KB text blob when nothing
    /// changed (#175(a)). `Optional`/schema-safe the same way.
    let searchTextsETag: String?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCoffee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }

    /// Synchronous, but cheap: PLAN.md §5 estimates ~25 ms for ~900 rows.
    /// Callers should still invoke this off the main actor (e.g. from
    /// `SyncEngine`'s own actor context) to keep it off the UI thread.
    static func load() -> PersistedSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.coffeeAPI.decode(PersistedSnapshot.self, from: data)
    }

    /// `Data.write(options: .atomic)` already writes to a temp file and
    /// renames into place, so a crash mid-write never leaves a truncated
    /// snapshot the next launch would fail to decode.
    func save() {
        guard let data = try? JSONEncoder.coffeeAPI.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
