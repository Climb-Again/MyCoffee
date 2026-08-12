import Foundation

/// Abstracts where a `CoffeeIndex` comes from. `RemoteCoffeeRepository`
/// (backlog #22) delta-syncs against `/api/snapshot`; `SampleCoffeeRepository`
/// stays available for previews and any UX work that wants realistic fixture
/// data without a live backend.
protocol CoffeeRepository: Sendable {
    /// The most recently loaded index, without triggering a fetch.
    func currentIndex() async -> CoffeeIndex

    /// Loads (or reloads) the index and returns it.
    func refresh() async throws -> CoffeeIndex

    /// Optimistic local favorite toggle, published immediately; the remote
    /// conformer enqueues it for the outbox to flush when online.
    func setFavorite(coffeeId: String, isFavorite: Bool) async -> CoffeeIndex

    /// Fetches and merges one coffee's detail payload (notes, raw text,
    /// signed image URLs) without a full resync.
    func loadDetail(coffeeId: String) async throws -> Coffee

    /// Records a review-task resolution for the outbox to flush when online,
    /// the same offline-durable pattern `setFavorite` uses (PLAN.md §5).
    func resolveReview(taskId: Int, value: String) async

    /// Records a review-task dismissal ("not on the bag") the same way.
    func dismissReview(taskId: Int) async

    /// Applies a per-field edit via the backend's locked/human-decided
    /// resolve path (PLAN.md §12 #40/#41) — queued through the same durable
    /// outbox `resolveReview` uses, then re-fetches detail so any
    /// backend-derived side effect (e.g. editing `roaster` also derives
    /// `roasterCountryId`) lands exactly as the server computed it, instead
    /// of being guessed at with a local optimistic merge. Returns the
    /// refreshed `Coffee` once the edit round-trips; `nil` while it's still
    /// queued (offline) or was rejected (a 422 never applies, so there's
    /// nothing new to merge).
    func editField(coffeeId: String, field: String, value: String) async -> Coffee?

    /// Same as `editField`, but applies every edit in `edits` in one request
    /// (PLAN.md §12, closing the atomicity gap #42's edit sheet flagged) —
    /// use this instead of N `editField` calls whenever a single save
    /// changes more than one field.
    func editFields(coffeeId: String, edits: [CoffeeFieldEdit]) async -> Coffee?
}
