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
}
