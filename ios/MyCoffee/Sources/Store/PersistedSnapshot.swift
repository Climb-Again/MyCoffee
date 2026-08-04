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
