import Foundation

/// A pending client-side write not yet acknowledged by the server (PLAN.md
/// §5). `reviewResolve`/`reviewDismiss` are the review lane's (#27) own cases,
/// added without a new outbox per this enum's original reserved-room comment.
/// `edit` is #41's — a generic per-field edit (PLAN.md §12 #40), same
/// raw-string-value shape as `reviewResolve`.
enum PendingMutation: Codable, Sendable {
    case favorite(coffeeId: String, isFavorite: Bool)
    case reviewResolve(taskId: Int, value: String)
    case reviewDismiss(taskId: Int)
    case edit(coffeeId: String, field: String, value: String)
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
        pending.removeAll { if case let .favorite(id, _) = $0 { return id == coffeeId } else { return false } }
        pending.append(.favorite(coffeeId: coffeeId, isFavorite: isFavorite))
        persist()
    }

    /// A review task only ever has one outstanding resolution/dismissal at a
    /// time, so a fresh one replaces whatever was queued for the same `taskId`.
    func enqueueReviewResolve(taskId: Int, value: String) {
        pending.removeAll { isReviewMutation($0, forTaskId: taskId) }
        pending.append(.reviewResolve(taskId: taskId, value: value))
        persist()
    }

    func enqueueReviewDismiss(taskId: Int) {
        pending.removeAll { isReviewMutation($0, forTaskId: taskId) }
        pending.append(.reviewDismiss(taskId: taskId))
        persist()
    }

    private func isReviewMutation(_ mutation: PendingMutation, forTaskId taskId: Int) -> Bool {
        switch mutation {
        case let .reviewResolve(id, _): return id == taskId
        case let .reviewDismiss(id): return id == taskId
        case .favorite, .edit: return false
        }
    }

    /// The most recent un-acked edit value for (id, field), if any — same
    /// purpose as `pendingFavorite`: tells a caller whether an edit is still
    /// waiting to flush.
    func pendingEdit(coffeeId: String, field: String) -> String? {
        for mutation in pending.reversed() {
            if case let .edit(id, f, value) = mutation, id == coffeeId, f == field {
                return value
            }
        }
        return nil
    }

    /// One outstanding edit per (coffeeId, field) at a time — same
    /// replace-not-accumulate rule `enqueueFavorite`/`enqueueReviewResolve` use.
    func enqueueEdit(coffeeId: String, field: String, value: String) {
        pending.removeAll {
            if case let .edit(id, f, _) = $0 { return id == coffeeId && f == field } else { return false }
        }
        pending.append(.edit(coffeeId: coffeeId, field: field, value: value))
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
            if await shouldKeep(mutation, using: client) {
                remaining.append(mutation)
            }
        }
        pending = remaining
        persist()
    }

    /// Applies one mutation; returns whether it should stay queued. A 4xx
    /// response (e.g. `resolveReview`'s 422 for a value the backend can't
    /// canonicalize) is a terminal rejection, not a transient failure — same
    /// as the fire-and-forget behavior this replaces, the item just stays
    /// open server-side for the next review-feed load rather than being
    /// retried forever. Anything else (offline, 5xx) keeps it queued.
    private func shouldKeep(_ mutation: PendingMutation, using client: APIClient) async -> Bool {
        do {
            switch mutation {
            case let .favorite(coffeeId, isFavorite):
                _ = try await client.setFavorite(publicId: coffeeId, favorite: isFavorite)
            case let .reviewResolve(taskId, value):
                _ = try await client.resolveReview(id: String(taskId), value: value)
            case let .reviewDismiss(taskId):
                _ = try await client.dismissReview(id: String(taskId))
            case let .edit(coffeeId, field, value):
                _ = try await client.editCoffeeField(publicId: coffeeId, field: field, value: value)
            }
            return false
        } catch let APIClient.APIError.http(status, _) where (400..<500).contains(status) {
            return false
        } catch {
            return true
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
