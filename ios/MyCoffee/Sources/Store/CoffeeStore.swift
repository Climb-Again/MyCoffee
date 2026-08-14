import Foundation

/// The seam between the iOS-shell and iOS-UX lanes (status/README.md): shell
/// publishes this API surface, UX consumes it. Holds the current
/// `CoffeeIndex` plus the active filter/sort; `filteredCoffees`/`facets`/
/// `topFilterCards` are plain computed properties, not `@Published`, because
/// they're cheap enough (microseconds at ~900 rows, PLAN.md §5) to recompute
/// on every view-body evaluation rather than cache and invalidate by hand.
///
/// Backed by `RemoteCoffeeRepository` (#22) by default; `SampleCoffeeRepository`
/// remains available for previews. Swapping the repository is the only
/// change `load()`/`refresh()` need.
@MainActor
final class CoffeeStore: ObservableObject {
    @Published private(set) var index: CoffeeIndex = .empty
    @Published var filter = CoffeeFilter()
    @Published var sort: SortOption = .dateBought

    /// The Review-tab badge count. This is the count of items the review queue
    /// can actually action (`GET /api/review`, already filtered to
    /// app-reviewable fields with usable candidates) — NOT every coffee whose
    /// `reviewState` is non-clean. The two diverge: a coffee can be
    /// `needs_review` only for fields the app can't review (farm, prose,
    /// roasted-date), which the queue omits — so a badge counting non-clean
    /// coffees never drops as you clear the queue. The badge follows the queue.
    @Published private(set) var reviewQueueCount: Int = 0

    private let repository: CoffeeRepository

    init(repository: CoffeeRepository = RemoteCoffeeRepository()) {
        self.repository = repository
    }

    /// Loads the initial index. Call once, e.g. from a root view's `.task`.
    /// Publishes whatever's persisted from a prior sync immediately (never
    /// blank), then kicks off a background delta sync (PLAN.md §5) rather
    /// than blocking on the network.
    func load() async {
        index = await repository.currentIndex()
        Task { await self.refresh() }
    }

    func refresh() async {
        if let refreshed = try? await repository.refresh() {
            index = refreshed
        }
    }

    /// Tap heart -> mutate in memory and publish immediately, enqueue, flush
    /// when online (PLAN.md §5). Fire-and-forget: the repository publishes
    /// the optimistically-updated index back through `index` once the local
    /// mutation lands, without waiting for the network round-trip.
    func toggleFavorite(_ coffee: Coffee) {
        let newValue = !coffee.isFavorite
        Task {
            index = await repository.setFavorite(coffeeId: coffee.id, isFavorite: newValue)
        }
    }

    /// Fetches the richer detail payload (notes, raw text, signed image
    /// URLs — PLAN.md §4) for one coffee and merges it into the index. The
    /// compact snapshot doesn't carry these fields, so `CoffeeDetailView`
    /// should call this from a `.task` to populate them; returns the merged
    /// `Coffee` directly too, in case the caller doesn't want to wait for
    /// the next `index` publish.
    @discardableResult
    func loadDetail(for coffee: Coffee) async -> Coffee? {
        guard let detailed = try? await repository.loadDetail(coffeeId: coffee.id) else { return nil }
        index = index.replacingCoffee(detailed)
        return detailed
    }

    /// Accept a review task's value — durable through the same offline outbox
    /// favorites use (PLAN.md §5), unlike a raw `APIClient.resolveReview` call:
    /// this survives app restart or a dropped connection instead of leaving a
    /// failed write to be silently forgotten.
    func resolveReview(taskId: Int, value: String) {
        Task { await repository.resolveReview(taskId: taskId, value: value) }
    }

    /// Dismiss a review task ("not on the bag"), same durability.
    func dismissReview(taskId: Int) {
        Task { await repository.dismissReview(taskId: taskId) }
    }

    /// Applies a per-field edit (PLAN.md §12 #41) — durable through the same
    /// outbox `resolveReview` uses, but unlike a review task an edited field
    /// IS part of the coffee index, so a successful round trip re-fetches
    /// detail and merges it in, the same way `loadDetail` does.
    ///
    /// Returns whether the edit was confirmed saved by the server. The caller
    /// (the edit sheet) awaits this and only dismisses on `true`, showing an
    /// error otherwise — a `false` means the write did not round-trip (offline,
    /// a rejected value, an auth problem), and silently dropping it is exactly
    /// what made edits look like they "saved but reverted."
    /// Human-readable reason the last edit save failed, for the edit sheet's
    /// alert. `nil` after a success. `APIError` is a `LocalizedError`, so this
    /// carries the real server message ("HTTP 422: …", "Backend URL or token
    /// not set", …) rather than a generic "couldn't save."
    @Published var editErrorText: String?

    @discardableResult
    func editField(coffeeId: String, field: String, value: String) async -> Bool {
        do {
            let updated = try await repository.editField(coffeeId: coffeeId, field: field, value: value)
            // Refresh FIRST — a roaster/farm edit may have get-or-created a new
            // vocab row (#40), and the delta sync pulls the full vocab so the
            // new name isn't "Unknown". Then re-apply the detailed edited coffee
            // ON TOP: the sync replaces every coffee with the compact snapshot
            // row, which omits the full source text / notes; `updated` (from the
            // detail re-fetch) still has them, so applying it last keeps the
            // coffee page's full-text section from vanishing until the next
            // detail fetch.
            await refresh()
            index = index.replacingCoffee(updated)
            editErrorText = nil
            return true
        } catch {
            editErrorText = error.localizedDescription
            return false
        }
    }

    /// Same as `editField`, but for a save that changes more than one field —
    /// sends one request instead of N with no ordering guarantee between them
    /// (PLAN.md §12, closing the gap #42's edit sheet flagged). Prefer this
    /// over calling `editField` in a loop whenever `edits.count > 1`.
    @discardableResult
    func editFields(coffeeId: String, edits: [CoffeeFieldEdit]) async -> Bool {
        do {
            let updated = try await repository.editFields(coffeeId: coffeeId, edits: edits)
            // Refresh first (fresh vocab), then re-apply the detailed coffee on
            // top so its full text/notes aren't clobbered by the compact
            // snapshot row — see editField above.
            await refresh()
            index = index.replacingCoffee(updated)
            editErrorText = nil
            return true
        } catch {
            editErrorText = error.localizedDescription
            return false
        }
    }

    /// Fetches the editorial "This month" brief (PLAN.md §6.4) for the
    /// Insights screen. A once-a-day read, not part of the coffee snapshot —
    /// no local caching, mirrors `loadDetail`'s fetch-and-return shape.
    func loadBrief() async -> Brief? {
        try? await APIClient(config: AppConfig.shared).brief()
    }

    /// Refresh the Review-tab badge from the same feed the Review page renders,
    /// so badge and page always agree. Called on launch; the Review view also
    /// updates it live via `setReviewQueueCount` as items are cleared.
    func refreshReviewCount() async {
        guard let client = try? await APIClient(config: AppConfig.shared),
              let feed = try? await client.reviewFeed() else { return }
        reviewQueueCount = feed.items.count
    }

    func setReviewQueueCount(_ count: Int) {
        reviewQueueCount = count
    }

    var filteredCoffees: [Coffee] {
        index.coffees(matching: filter, sortedBy: sort)
    }

    var facets: FacetCounts {
        index.facets(for: filter)
    }

    var topFilterCards: [TopFilterCard] {
        index.topFilterCards()
    }
}
