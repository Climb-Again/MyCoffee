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
