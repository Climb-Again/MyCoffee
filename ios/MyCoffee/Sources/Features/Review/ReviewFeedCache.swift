import Foundation

/// Which coffees currently have at least one *client-reviewable* open item
/// (PLAN.md §11 #37). `GET /api/review` already filters to reviewable fields
/// server-side (`routes/review.js`'s `FIELD_TO_CLIENT`), so any `coffeeId`
/// that shows up in the feed genuinely has something this app can act on — a
/// coffee whose only open item is a non-reviewable field (e.g. a `desc_*`
/// prose split) never appears here, even though its coarse
/// `Coffee.reviewState` column still reads `needs_review`. That mismatch is
/// exactly what made the per-coffee Review button open an empty "All set"
/// sheet, and inflated the Review tab's badge count.
///
/// One shared cache rather than a per-view fetch: the coffee detail page and
/// the tab badge both just need a yes/no per coffee, and both `ReviewQueueView`
/// and `CoffeeReviewSheet` already fetch this same feed for their own queues —
/// `adopt(_:)` lets them share that result instead of a second round-trip.
@MainActor
final class ReviewFeedCache: ObservableObject {
    static let shared = ReviewFeedCache()

    /// `nil` until a feed fetch has actually succeeded. Sample/demo builds
    /// with no backend configured (`APIClient.APIError.notConfigured`) or a
    /// transient network failure leave this `nil`, so `hasReviewableTasks`
    /// falls back to "don't suppress" — the affordance behaves exactly as it
    /// did before this cache existed until a real answer is confirmed. That
    /// keeps `BundledSampleRepository`-only runs (no backend at all) unaffected.
    @Published private(set) var reviewableCoffeeIds: Set<String>?

    /// One feed item is one (coffeeId, field) pair, so counting items per
    /// coffee is the field count the `#88` detail-page review pill needs
    /// ("2 fields to review") — no separate endpoint required.
    @Published private(set) var reviewableFieldCounts: [String: Int] = [:]

    private var inFlight: Task<Void, Never>?

    private init() {}

    /// Fetches once; a later screen that also calls this is free until
    /// `refresh()` is asked for explicitly.
    func ensureLoaded() async {
        guard reviewableCoffeeIds == nil else { return }
        await refresh()
    }

    /// Re-fetches `GET /api/review` and replaces the cached set. Call after an
    /// accept/dismiss flow finishes so a coffee whose last actionable item was
    /// just resolved stops showing the Review affordance right away.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            guard let client = try? await APIClient(config: AppConfig.shared) else { return }
            guard let feed = try? await client.reviewFeed() else { return }
            self.adopt(feed)
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    func adopt(_ feed: ReviewFeedDTO) {
        let coffeeIds = feed.items.compactMap(\.coffeeId)
        reviewableCoffeeIds = Set(coffeeIds)
        reviewableFieldCounts = coffeeIds.reduce(into: [:]) { counts, id in counts[id, default: 0] += 1 }
    }

    func hasReviewableTasks(for coffeeId: String) -> Bool {
        guard let reviewableCoffeeIds else { return true }
        return reviewableCoffeeIds.contains(coffeeId)
    }

    /// `0` once a feed fetch has succeeded and found nothing for this coffee;
    /// also `0` before any fetch succeeds — callers should gate display on
    /// `hasReviewableTasks(for:)` first, same as today, and only use this for
    /// the pill's copy once that gate is already `true`.
    func reviewableFieldCount(for coffeeId: String) -> Int {
        reviewableFieldCounts[coffeeId] ?? 0
    }
}
