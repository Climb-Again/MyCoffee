import Foundation

/// The current shape `CompactCoffeeDTO`/`CoffeeDetailDTO`/`VocabDTO` know how
/// to decode. Bumped only when the backend's `SNAPSHOT_VERSION`
/// (`routes/coffees.js`) bumps in lockstep with a client update — see
/// `SyncEngine.sync`'s schema-mismatch handling.
enum SnapshotSchema {
    static let currentVersion = 1
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
