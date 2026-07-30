import Foundation

/// The seam between the iOS-shell and iOS-UX lanes (status/README.md): shell
/// publishes this API surface, UX consumes it. Holds the current
/// `CoffeeIndex` plus the active filter/sort; `filteredCoffees`/`facets`/
/// `topFilterCards` are plain computed properties, not `@Published`, because
/// they're cheap enough (microseconds at ~900 rows, PLAN.md §5) to recompute
/// on every view-body evaluation rather than cache and invalidate by hand.
///
/// Backed by `SampleCoffeeRepository` until the real sync engine (#22) lands —
/// swapping the repository is the only change `load()`/`refresh()` will need.
@MainActor
final class CoffeeStore: ObservableObject {
    @Published private(set) var index: CoffeeIndex = .empty
    @Published var filter = CoffeeFilter()
    @Published var sort: SortOption = .dateBought

    private let repository: CoffeeRepository

    init(repository: CoffeeRepository = SampleCoffeeRepository()) {
        self.repository = repository
    }

    /// Loads the initial index. Call once, e.g. from a root view's `.task`.
    func load() async {
        index = await repository.currentIndex()
    }

    func refresh() async {
        if let refreshed = try? await repository.refresh() {
            index = refreshed
        }
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
