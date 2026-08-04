import Foundation

/// A pending client-side write not yet acknowledged by the server (PLAN.md
/// §5). `favorite` is the only mutable field in the app today; the enum
/// leaves room for the review lane (#27) to add its own without a new outbox.
enum PendingMutation: Codable, Sendable {
    case favorite(coffeeId: String, isFavorite: Bool)

    var coffeeId: String {
        switch self {
        case let .favorite(coffeeId, _): return coffeeId
        }
    }
}

/// Persisted queue of writes the server hasn't confirmed yet. `SyncEngine`
/// consults `pendingFavorite(for:)` while merging a sync response so a fresh
/// server row never clobbers a tap the user made moments ago but that hasn't
/// round-tripped (PLAN.md §5: "the server row wins unless a pending mutation
/// for that (id, field) is un-acked").
actor MutationOutbox {
    private var pending: [PendingMutation] = []
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCoffee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("outbox.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([PendingMutation].self, from: data) {
            pending = decoded
        }
    }

    /// The most recent un-acked favorite value for `id`, if any.
    func pendingFavorite(for id: String) -> Bool? {
        for mutation in pending.reversed() {
            if case let .favorite(coffeeId, isFavorite) = mutation, coffeeId == id {
                return isFavorite
            }
        }
        return nil
    }

    func enqueueFavorite(coffeeId: String, isFavorite: Bool) {
        pending.removeAll { $0.coffeeId == coffeeId }
        pending.append(.favorite(coffeeId: coffeeId, isFavorite: isFavorite))
        persist()
    }

    /// Drains the queue against the server. A mutation that fails (network
    /// down, token revoked, …) stays queued for the next flush; one that
    /// succeeds is removed so `pendingFavorite` stops overriding the
    /// server's row on the following sync.
    func flush(using client: APIClient) async {
        guard !pending.isEmpty else { return }
        var remaining: [PendingMutation] = []
        for mutation in pending {
            switch mutation {
            case let .favorite(coffeeId, isFavorite):
                do {
                    _ = try await client.setFavorite(publicId: coffeeId, favorite: isFavorite)
                } catch {
                    remaining.append(mutation)
                }
            }
        }
        pending = remaining
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
