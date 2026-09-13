import Foundation

/// A pending client-side write not yet acknowledged by the server (PLAN.md
/// §5). `reviewResolve`/`reviewDismiss` are the review lane's (#27) own cases,
/// added without a new outbox per this enum's original reserved-room comment.
/// `edit` is #41's — a generic per-field edit (PLAN.md §12 #40), same
/// raw-string-value shape as `reviewResolve`. `editBatch` sends >1 field edit
/// in one request (the #42-flagged atomicity gap) instead of one `.edit` per
/// field with no ordering guarantee between them.
enum PendingMutation: Codable, Sendable {
    case favorite(coffeeId: String, isFavorite: Bool)
    case reviewResolve(taskId: Int, value: String)
    case reviewDismiss(taskId: Int)
    case edit(coffeeId: String, field: String, value: String)
    case editBatch(coffeeId: String, edits: [CoffeeFieldEdit])
    /// Brew lab (PLAN.md §14, #156) — a tri-state tap for one (coffee, option)
    /// pair. Unlike `favorite`, more than one can be pending for the same
    /// coffee at once (different options), so this is keyed by (coffeeId,
    /// optionId), not just coffeeId.
    case brewState(coffeeId: String, optionId: Int, state: BrewTrialState)
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
        case .favorite, .edit, .editBatch, .brewState: return false
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

    /// The most recent un-acked batch edit for `coffeeId`, if any — same
    /// purpose as `pendingEdit`, keyed by coffee since a batch covers >1 field.
    func pendingEditBatch(coffeeId: String) -> [CoffeeFieldEdit]? {
        for mutation in pending.reversed() {
            if case let .editBatch(id, edits) = mutation, id == coffeeId {
                return edits
            }
        }
        return nil
    }

    /// One outstanding batch edit per coffeeId at a time. Does not touch any
    /// single-field `.edit` mutations already queued for the same coffee —
    /// `editField` and `editFields` are separate call paths the UX layer
    /// chooses between, not meant to merge with each other.
    func enqueueEditBatch(coffeeId: String, edits: [CoffeeFieldEdit]) {
        pending.removeAll {
            if case let .editBatch(id, _) = $0 { return id == coffeeId } else { return false }
        }
        pending.append(.editBatch(coffeeId: coffeeId, edits: edits))
        persist()
    }

    /// The most recent un-acked brew state for every (coffeeId, optionId) pair
    /// still queued for `coffeeId` — same purpose as `pendingFavorite`, but
    /// keyed by optionId since several can be pending for one coffee at once.
    /// Forward iteration (not `.reversed()`, unlike `pendingFavorite`) so a
    /// later mutation for the same optionId simply overwrites the dictionary
    /// entry an earlier one set.
    func pendingBrewStates(for coffeeId: String) -> [Int: BrewTrialState] {
        var result: [Int: BrewTrialState] = [:]
        for mutation in pending {
            if case let .brewState(id, optionId, state) = mutation, id == coffeeId {
                result[optionId] = state
            }
        }
        return result
    }

    /// One outstanding mutation per (coffeeId, optionId) at a time — same
    /// replace-not-accumulate rule `enqueueFavorite` uses.
    func enqueueBrewState(coffeeId: String, optionId: Int, state: BrewTrialState) {
        pending.removeAll {
            if case let .brewState(id, oid, _) = $0 { return id == coffeeId && oid == optionId } else { return false }
        }
        pending.append(.brewState(coffeeId: coffeeId, optionId: optionId, state: state))
        persist()
    }

    /// One brew POST's response, flushed successfully — `SyncEngine` applies
    /// this to replace the coffee's local `brewTriedIds`/`brewBestIds` with
    /// the server's authoritative whole-state, which may include extra
    /// auto-ticked grind/temp ids the optimistic local update didn't know
    /// about (PLAN.md §14's recipe auto-tick).
    struct FlushedBrewState: Sendable {
        let coffeeId: String
        let response: BrewStateResponseDTO
    }

    /// Applying one mutation either finishes it (terminal — success or a 4xx
    /// rejection) or leaves it queued (transient failure); a finished brew
    /// state additionally carries the server's response for the caller to
    /// reconcile.
    private enum MutationOutcome {
        case keep
        case done
        case doneWithBrewState(FlushedBrewState)
    }

    /// Drains the queue against the server. A mutation that fails (network
    /// down, token revoked, …) stays queued for the next flush; one that
    /// succeeds is removed so `pendingFavorite`/`pendingBrewStates` stop
    /// overriding the server's row on the following sync. Returns every brew
    /// state that flushed successfully, for the caller to reconcile.
    @discardableResult
    func flush(using client: APIClient) async -> [FlushedBrewState] {
        guard !pending.isEmpty else { return [] }
        var remaining: [PendingMutation] = []
        var flushedBrewStates: [FlushedBrewState] = []
        for mutation in pending {
            switch await applyMutation(mutation, using: client) {
            case .keep:
                remaining.append(mutation)
            case .done:
                break
            case let .doneWithBrewState(flushed):
                flushedBrewStates.append(flushed)
            }
        }
        pending = remaining
        persist()
        return flushedBrewStates
    }

    /// Applies one mutation against the server. A 4xx response (e.g.
    /// `resolveReview`'s 422 for a value the backend can't canonicalize) is a
    /// terminal rejection, not a transient failure — same as the
    /// fire-and-forget behavior this replaces, the item just stays open
    /// server-side for the next review-feed load rather than being retried
    /// forever. Anything else (offline, 5xx) keeps it queued.
    private func applyMutation(_ mutation: PendingMutation, using client: APIClient) async -> MutationOutcome {
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
            case let .editBatch(coffeeId, edits):
                _ = try await client.editCoffeeFields(publicId: coffeeId, edits: edits)
            case let .brewState(coffeeId, optionId, state):
                let response = try await client.setBrewState(publicId: coffeeId, optionId: optionId, state: state)
                return .doneWithBrewState(FlushedBrewState(coffeeId: coffeeId, response: response))
            }
            return .done
        } catch let APIClient.APIError.http(status, _) where (400..<500).contains(status) {
            return .done
        } catch {
            return .keep
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
