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
    private var lastFullSyncAt: Date?
    private var searchTextsETag: String?

    /// #175(d): force a full (`since: nil`) resync at least this often, even
    /// when a delta would otherwise suffice, so every coffee's signed
    /// `thumbUrl` — which a delta sync only re-sends for rows that changed —
    /// gets renewed well inside its 30-day expiry (`coffees.js:62`).
    private static let fullSyncMaxAge: TimeInterval = 14 * 24 * 60 * 60

    private let outbox = MutationOutbox()

    init() {
        guard let persisted = PersistedSnapshot.load() else { return }
        coffees = Dictionary(uniqueKeysWithValues: persisted.coffees.map { ($0.id, $0) })
        vocabulary = persisted.vocabulary
        searchTexts = persisted.searchTexts
        profilesByID = persisted.profilesByID
        lastSyncAt = persisted.lastSyncAt
        schemaVersion = persisted.schemaVersion
        lastFullSyncAt = persisted.lastFullSyncAt
        searchTextsETag = persisted.searchTextsETag
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
        let isStale = lastFullSyncAt.map { Date().timeIntervalSince($0) >= Self.fullSyncMaxAge } ?? true
        var requestedSince = (schemaVersion != nil && !isStale) ? lastSyncAt?.addingTimeInterval(-60) : nil
        var response = try await client.snapshot(since: requestedSince)

        if let schemaVersion, schemaVersion != response.version {
            coffees = [:]
            requestedSince = nil
            response = try await client.snapshot(since: nil)
        }

        profilesByID = profileMap(from: response.vocab.profiles)
        vocabulary = Vocabulary(
            countryList: response.vocab.countries,
            roasterList: response.vocab.roasters,
            farmList: response.vocab.farms,
            brewOptionList: response.vocab.brewOptions.compactMap { BrewOption(dto: $0) }
        )
        for dto in response.coffees {
            var coffee = dto.makeCoffee(profilesByID: profilesByID)
            if let pending = await outbox.pendingFavorite(for: dto.id) {
                coffee = coffee.withFavorite(pending, setBy: "human")
            }
            coffee = applyPendingBrewStates(to: coffee, pending: await outbox.pendingBrewStates(for: dto.id))
            coffees[dto.id] = coffee
        }
        for deletedID in response.deleted {
            coffees.removeValue(forKey: deletedID)
        }
        schemaVersion = response.version
        lastSyncAt = response.generatedAt
        if requestedSince == nil {
            lastFullSyncAt = response.generatedAt
        }

        // #175(a): ~95% of sync bytes and unchanged far more often than the
        // coffees themselves — send the last ETag and skip the ~300 KB decode
        // on a 304 rather than fetching and replacing `searchTexts` every time.
        if let (texts, etag) = try? await client.snapshotText(ifNoneMatch: searchTextsETag) {
            if let texts {
                searchTexts = texts
            }
            searchTextsETag = etag ?? searchTextsETag
        }

        await flushOutbox(using: client)
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
        coffee = applyPendingBrewStates(to: coffee, pending: await outbox.pendingBrewStates(for: coffeeId))
        coffees[coffeeId] = coffee
        persist()
        return coffee
    }

    /// Applies every un-flushed brew-state mutation queued for `coffee`
    /// (PLAN.md §14's "pending mutation wins" rule, same as the favorite
    /// merge above) over a freshly-fetched server row, so a sync or detail
    /// fetch racing an un-acked tap never clobbers it. `pending` is keyed by
    /// optionId; each is applied through the same optimistic state machine
    /// `setBrewState` uses, including the recipe → grind/temp auto-tick
    /// mirror, so re-applying it here can't drift from a live tap's result.
    private func applyPendingBrewStates(to coffee: Coffee, pending: [Int: BrewTrialState]) -> Coffee {
        guard !pending.isEmpty else { return coffee }
        var result = coffee
        for (optionId, state) in pending {
            guard let option = vocabulary.brewOptions[optionId] else { continue }
            result = applyOptimisticBrewState(to: result, option: option, state: state)
        }
        return result
    }

    /// Optimistic local favorite toggle (PLAN.md §5: "tap heart -> mutate in
    /// memory and publish immediately, enqueue, flush when online"). #175(c):
    /// the flush itself is detached rather than awaited — awaiting it here
    /// held the returned (already-mutated) index hostage behind the outbox's
    /// full network round trip, so offline the heart didn't visibly flip
    /// until that call's ~60 s timeout elapsed.
    func setFavorite(coffeeId: String, isFavorite: Bool, client: APIClient?) async -> CoffeeIndex {
        if let coffee = coffees[coffeeId] {
            coffees[coffeeId] = coffee.withFavorite(isFavorite, setBy: "human")
            persist()
        }
        await outbox.enqueueFavorite(coffeeId: coffeeId, isFavorite: isFavorite)
        let result = currentIndex()
        if let client {
            Task { await self.flushOutbox(using: client) }
        }
        return result
    }

    /// Optimistic local brew-state toggle (PLAN.md §14) — same shape as
    /// `setFavorite`: mutate + publish immediately, enqueue, flush when
    /// online. This is a tap-tap-tap surface (check tried, tap the trophy for
    /// best), so a spinner per tap would kill it.
    func setBrewState(coffeeId: String, optionId: Int, state: BrewTrialState, client: APIClient?) async -> CoffeeIndex {
        if let coffee = coffees[coffeeId], let option = vocabulary.brewOptions[optionId] {
            coffees[coffeeId] = applyOptimisticBrewState(to: coffee, option: option, state: state)
            persist()
        }
        await outbox.enqueueBrewState(coffeeId: coffeeId, optionId: optionId, state: state)
        if let client {
            await flushOutbox(using: client)
        }
        return currentIndex()
    }

    /// Creates (or get-or-creates, per the backend's dedup rule) a catalogue
    /// option and inserts it into the vocabulary immediately, rather than
    /// waiting for the next sync — a trial needs a real server id right away,
    /// and a catalogue add is rare, so this is confirmed + throwing like
    /// `editField`, not routed through the outbox.
    func createBrewOption(
        kind: BrewKind, label: String?, detail: String?, valueNum: Double?, recipe: BrewRecipeSpec?,
        client: APIClient?
    ) async throws -> BrewOption {
        guard let client else { throw APIClient.APIError.notConfigured }
        let dto = try await client.createBrewOption(kind: kind, label: label, detail: detail, valueNum: valueNum, recipe: recipe)
        guard let option = BrewOption(dto: dto) else {
            throw APIClient.APIError.http(status: -1, body: "unrecognized brew kind \(dto.kind)")
        }
        vocabulary = vocabulary.insertingBrewOption(option)
        persist()
        return option
    }

    /// Renames/re-values/archives a catalogue option — same confirmed +
    /// throwing shape as `createBrewOption`.
    func updateBrewOption(id: Int, patch: BrewOptionPatch, client: APIClient?) async throws -> BrewOption {
        guard let client else { throw APIClient.APIError.notConfigured }
        let dto = try await client.updateBrewOption(id: id, patch: patch)
        guard let option = BrewOption(dto: dto) else {
            throw APIClient.APIError.http(status: -1, body: "unrecognized brew kind \(dto.kind)")
        }
        vocabulary = vocabulary.insertingBrewOption(option)
        persist()
        return option
    }

    /// The optimistic state machine for one (coffee, option) tap — mirrors the
    /// server's `nextTrialRows`/`impliedTrials` (`backend/src/lib/brewState.js`):
    /// `.best` demotes any other best of the same kind, and setting a
    /// **recipe** tried/best also optimistically ticks its nominal grind/temp
    /// options as `tried` (never demoting an existing best of THOSE kinds),
    /// one-way, so the UI doesn't flicker before the flush response confirms
    /// it. Skips the grind/temp tick when that numeric option isn't known
    /// locally yet — the flush response (or next sync) will add it.
    private func applyOptimisticBrewState(to coffee: Coffee, option: BrewOption, state: BrewTrialState) -> Coffee {
        var tried = Set(coffee.triedBrewOptionIds)
        var best = Set(coffee.bestBrewOptionIds)

        switch state {
        case .untried:
            tried.remove(option.id)
            best.remove(option.id)
        case .tried:
            tried.insert(option.id)
            best.remove(option.id)
        case .best:
            tried.insert(option.id)
            for id in best where id != option.id && vocabulary.brewOptions[id]?.kind == option.kind {
                best.remove(id)
            }
            best.insert(option.id)
        }

        if option.kind == .recipe, state != .untried, let recipe = option.recipe {
            if let grindOption = vocabulary.brewOption(kind: .grind, value: Double(recipe.grindClicks)) {
                tried.insert(grindOption.id)
            }
            if let tempOption = vocabulary.brewOption(kind: .temp, value: Double(recipe.waterTempC)) {
                tried.insert(tempOption.id)
            }
        }

        return coffee.withBrew(tried: tried.sorted(), best: best.sorted())
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
        await flushOutbox(using: client)
    }

    func dismissReview(taskId: Int, client: APIClient?) async throws {
        guard let client else { throw APIClient.APIError.notConfigured }
        _ = try await client.dismissReview(id: String(taskId))
        await flushOutbox(using: client)
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

    /// Scores a not-yet-owned bag against the rated corpus (#106/#136) — a
    /// stateless read, same as `extractDraft`.
    func evaluateCoffee(photoIds: [String], client: APIClient?) async throws -> EvaluateResult {
        guard let client else { throw APIClient.APIError.notConfigured }
        return EvaluateResult(dto: try await client.evaluateCoffee(photoIds: photoIds))
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

    /// Add Coffee: create instantly, extract in the background (#118/#130) —
    /// unlike `createCoffee` above, does **not** call `loadDetail`/wait on
    /// anything: the whole point is returning before extraction runs. Builds
    /// a placeholder `Coffee` straight from the `{id, reviewState}` response
    /// and merges it into `coffees` directly, so it's visible in the listing
    /// immediately; the backend's background pass fills in every other field
    /// via the next normal delta sync, same as any other worker-processed
    /// photo (no new client-sync logic needed).
    func quickCreateCoffee(photoIds: [String], client: APIClient?) async throws -> Coffee {
        guard let client else { throw APIClient.APIError.notConfigured }
        let response = try await client.quickCreateCoffee(photoIds: photoIds)
        let placeholder = Coffee.pendingPlaceholder(id: response.id, reviewState: response.reviewState)
        coffees[response.id] = placeholder
        persist()
        return placeholder
    }

    /// Drains the outbox and reconciles any brew-state responses into
    /// `coffees` — a brew POST's response carries the coffee's WHOLE brew
    /// state (PLAN.md §14), which may include auto-ticked grind/temp ids the
    /// optimistic local update couldn't have known about, so every call site
    /// that used to call `outbox.flush(using:)` directly now goes through
    /// this instead of duplicating the reconciliation per call site.
    private func flushOutbox(using client: APIClient) async {
        let flushedBrewStates = await outbox.flush(using: client)
        guard !flushedBrewStates.isEmpty else { return }
        for flushed in flushedBrewStates {
            if let coffee = coffees[flushed.coffeeId] {
                coffees[flushed.coffeeId] = coffee.withBrew(tried: flushed.response.brewTried, best: flushed.response.brewBest)
            }
        }
        persist()
    }

    private func persist() {
        PersistedSnapshot(
            schemaVersion: schemaVersion ?? SnapshotSchema.currentVersion,
            lastSyncAt: lastSyncAt ?? Date(),
            coffees: Array(coffees.values),
            vocabulary: vocabulary,
            searchTexts: searchTexts,
            profilesByID: profilesByID,
            lastFullSyncAt: lastFullSyncAt,
            searchTextsETag: searchTextsETag
        ).save()
    }
}
