import Foundation

/// The current shape `CompactCoffeeDTO`/`CoffeeDetailDTO`/`VocabDTO` know how
/// to decode. Bumped only when the backend's `SNAPSHOT_VERSION`
/// (`routes/coffees.js`) bumps in lockstep with a client update — see
/// `SyncEngine.sync`'s schema-mismatch handling.
enum SnapshotSchema {
    static let currentVersion = 2
}

/// Delta-syncs against `/api/snapshot` and persists the result to disk
/// (PLAN.md §5). Owns the single in-memory `[id: Coffee]` map that every
/// operation — sync merge, favorite toggle, detail enrichment — mutates
/// through, so "server row wins unless a pending mutation is un-acked"
/// (PLAN.md §5) has exactly one place to hold true.
actor SyncEngine {
    private var coffees: [String: Coffee] = [:]
    private var vocabulary: Vocabulary = .empty
    private var searchTexts: [String: String] = [:]
    private var profilesByID: [Int: Profile] = [:]
    private var lastSyncAt: Date?
    private var schemaVersion: Int?

    private let outbox = MutationOutbox()

    init() {
        guard let persisted = PersistedSnapshot.load() else { return }
        coffees = Dictionary(uniqueKeysWithValues: persisted.coffees.map { ($0.id, $0) })
        vocabulary = persisted.vocabulary
        searchTexts = persisted.searchTexts
        profilesByID = persisted.profilesByID
        lastSyncAt = persisted.lastSyncAt
        schemaVersion = persisted.schemaVersion
    }

    /// The most recently loaded index — from disk if this is a cold start and
    /// `sync` hasn't run yet. Never touches the network.
    func currentIndex() -> CoffeeIndex {
        CoffeeIndex(coffees: Array(coffees.values), vocabulary: vocabulary, searchTexts: searchTexts)
    }

    /// Delta sync per PLAN.md §5: `since = lastSyncAt − 60s` (clock skew),
    /// apply upserts + `deleted`, rebuild once, persist atomically. A
    /// schema-version mismatch drops the local cache and forces one full
    /// refetch rather than trying to merge two shapes.
    func sync(using client: APIClient) async throws -> CoffeeIndex {
        let requestedSince = (schemaVersion != nil) ? lastSyncAt?.addingTimeInterval(-60) : nil
        var response = try await client.snapshot(since: requestedSince)

        if let schemaVersion, schemaVersion != response.version {
            coffees = [:]
            response = try await client.snapshot(since: nil)
        }

        profilesByID = profileMap(from: response.vocab.profiles)
        for dto in response.coffees {
            var coffee = dto.makeCoffee(profilesByID: profilesByID)
            if let pending = await outbox.pendingFavorite(for: dto.id) {
                coffee = coffee.withFavorite(pending, setBy: "human")
            }
            coffees[dto.id] = coffee
        }
        for deletedID in response.deleted {
            coffees.removeValue(forKey: deletedID)
        }
        vocabulary = Vocabulary(
            countryList: response.vocab.countries,
            roasterList: response.vocab.roasters,
            farmList: response.vocab.farms
        )
        schemaVersion = response.version
        lastSyncAt = response.generatedAt

        if let textResponse = try? await client.snapshotText() {
            searchTexts = textResponse
        }

        await outbox.flush(using: client)
        persist()
        return currentIndex()
    }

    /// Fetches and merges one coffee's detail payload — notes, raw text,
    /// signed image URLs — without a full resync (PLAN.md §4).
    func loadDetail(coffeeId: String, using client: APIClient) async throws -> Coffee {
        let dto = try await client.coffeeDetail(publicId: coffeeId)
        var coffee = dto.makeCoffee(profilesByID: profilesByID)
        if let pending = await outbox.pendingFavorite(for: coffeeId) {
            coffee = coffee.withFavorite(pending, setBy: "human")
        }
        coffees[coffeeId] = coffee
        persist()
        return coffee
    }

    /// Optimistic local favorite toggle (PLAN.md §5: "tap heart -> mutate in
    /// memory and publish immediately, enqueue, flush when online").
    func setFavorite(coffeeId: String, isFavorite: Bool, client: APIClient?) async -> CoffeeIndex {
        if let coffee = coffees[coffeeId] {
            coffees[coffeeId] = coffee.withFavorite(isFavorite, setBy: "human")
            persist()
        }
        await outbox.enqueueFavorite(coffeeId: coffeeId, isFavorite: isFavorite)
        if let client {
            await outbox.flush(using: client)
        }
        return currentIndex()
    }

    /// Queues a review-task resolution and flushes immediately if online —
    /// same shape as `setFavorite`, but a review task isn't part of the
    /// coffee index, so there's no local state to mutate here beyond the
    /// outbox itself.
    /// Sends the resolution directly and **throws** on failure (offline, HTTP
    /// error, rejected value) — NOT through the outbox, whose fire-and-forget
    /// flush made a review accept "advance now, maybe persist later," so a
    /// partial review session silently lost items until a later full sync
    /// flushed the backlog (Radu: "saves only when I finish all"). Confirmed
    /// per-item now, same shape as `editField`. Also drains any review
    /// mutations a prior (outbox-era) build left queued.
    func resolveReview(taskId: Int, value: String, client: APIClient?) async throws {
        guard let client else { throw APIClient.APIError.notConfigured }
        _ = try await client.resolveReview(id: String(taskId), value: value)
        await outbox.flush(using: client)
    }

    func dismissReview(taskId: Int, client: APIClient?) async throws {
        guard let client else { throw APIClient.APIError.notConfigured }
        _ = try await client.dismissReview(id: String(taskId))
        await outbox.flush(using: client)
    }

    /// Persisted photo rotation (#57/#73). Confirmed then applied: the local
    /// coffee is only rotated once the write round-trips, so a failed save
    /// leaves the shown orientation unchanged and the caller can surface the
    /// error — no optimistic flicker to revert.
    func setRotation(coffeeId: String, quarterTurns: Int, client: APIClient?) async throws -> CoffeeIndex {
        guard let client else { throw APIClient.APIError.notConfigured }
        _ = try await client.setRotation(publicId: coffeeId, quarterTurns: quarterTurns)
        if let coffee = coffees[coffeeId] {
            coffees[coffeeId] = coffee.withRotation(quarterTurns)
            persist()
        }
        return currentIndex()
    }

    /// Queues the edit and flushes immediately if online (same shape as
    /// `setFavorite`/`resolveReview`), then re-fetches detail so any
    /// backend-derived side effect lands exactly as the server computed it —
    /// unlike a favorite toggle, an edit's effect on the coffee row (e.g. a
    /// re-derived `roasterCountryId`) can't be guessed at locally. Returns
    /// `nil` while offline (still queued after the flush attempt) — there's
    /// nothing new on the server to fetch yet.
    func editField(coffeeId: String, field: String, value: String, client: APIClient?) async throws -> Coffee {
        guard let client else { throw APIClient.APIError.notConfigured }
        // Send directly and let a non-2xx throw `APIError.http` — do NOT route
        // through the outbox, whose `shouldKeep` drops a 4xx as "done" and made
        // a rejected edit indistinguishable from a saved one.
        _ = try await client.editCoffeeField(publicId: coffeeId, field: field, value: value)
        return try await loadDetail(coffeeId: coffeeId, using: client)
    }

    /// Same shape as `editField`, but for >1 field applied in one request
    /// (PLAN.md §12, the #42-flagged atomicity gap) — the backend resolves
    /// every edit before writing the coffees row once, so there's no
    /// ordering hazard between e.g. an explicit `roasterCountry` and the
    /// `roasterCountryId` a same-save `roaster` edit derives.
    func editFields(coffeeId: String, edits: [CoffeeFieldEdit], client: APIClient?) async throws -> Coffee {
        guard let client else { throw APIClient.APIError.notConfigured }
        _ = try await client.editCoffeeFields(publicId: coffeeId, edits: edits)
        return try await loadDetail(coffeeId: coffeeId, using: client)
    }

    /// Uploads each Add Coffee wizard photo (#75/#76): registers all of them
    /// in one `POST /api/photos/manifest` call — the primary/front photo's
    /// entry carries `fullText` as its `description`, since #75 has no
    /// separate text parameter — then PUTs each one's bytes. Returns the
    /// assigned photoIds in the same order as `images`, so the caller's first
    /// id is the primary photo `extractDraft`/`createCoffee` key off.
    func uploadPhotos(_ images: [Data], fullText: String, client: APIClient?) async throws -> [String] {
        guard let client else { throw APIClient.APIError.notConfigured }
        guard !images.isEmpty else { return [] }

        let capturedAt = Date()
        let shas = images.map(\.sha256Hex)
        let entries = images.indices.map { i in
            PhotoManifestEntry(
                sourceId: UUID().uuidString,
                contentSha256: shas[i],
                capturedAt: capturedAt,
                description: i == 0 ? fullText : nil
            )
        }

        let results = try await client.uploadPhotoManifest(entries: entries)
        let photoIdBySourceId = Dictionary(uniqueKeysWithValues: results.map { ($0.sourceId, $0.photoId) })

        var photoIds: [String] = []
        for (i, entry) in entries.enumerated() {
            guard let photoId = photoIdBySourceId[entry.sourceId] else {
                throw APIClient.APIError.http(status: -1, body: "manifest response missing sourceId \(entry.sourceId)")
            }
            _ = try await client.uploadPhotoImage(sourceId: entry.sourceId, sha256: shas[i], jpegData: images[i])
            photoIds.append(photoId)
        }
        return photoIds
    }

    /// Runs the wizard's light extraction ensemble over already-uploaded
    /// photos (#75/#76) — a stateless read, nothing here touches `coffees`.
    func extractDraft(photoIds: [String], client: APIClient?) async throws -> ExtractedDraft {
        guard let client else { throw APIClient.APIError.notConfigured }
        return ExtractedDraft(dto: try await client.extractDraft(photoIds: photoIds))
    }

    /// Persists the wizard's confirmed fields as a brand-new coffee (#75/#76),
    /// then merges it into the index the same way `editField` does — a fresh
    /// `loadDetail` fetch, so any backend-derived side effect (e.g. a resolved
    /// `roaster` deriving `roasterCountryId`) lands exactly as the server
    /// computed it.
    func createCoffee(photoIds: [String], fields: [CoffeeFieldEdit], client: APIClient?) async throws -> Coffee {
        guard let client else { throw APIClient.APIError.notConfigured }
        let created = try await client.createCoffee(photoIds: photoIds, fields: fields)
        return try await loadDetail(coffeeId: created.id, using: client)
    }

    private func persist() {
        PersistedSnapshot(
            schemaVersion: schemaVersion ?? SnapshotSchema.currentVersion,
            lastSyncAt: lastSyncAt ?? Date(),
            coffees: Array(coffees.values),
            vocabulary: vocabulary,
            searchTexts: searchTexts,
            profilesByID: profilesByID
        ).save()
    }
}
