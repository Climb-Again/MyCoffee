import Foundation

/// The result of `CoffeeIndex.facets(for:)` — one entry per distinct value
/// present in each dimension, counted against the filter with that dimension
/// itself cleared (PLAN.md §5). Every value the dataset contains gets an
/// entry even when its count comes out to 0 — the filter sheet renders those
/// disabled at 30% opacity rather than hiding them.
struct FacetCounts: Sendable {
    struct Entry: Identifiable, Sendable {
        let key: FacetKey
        let count: Int
        /// Mean rating among matching, rated coffees — the trailing "★ 4.31"
        /// hint in the filter sheet (PLAN.md §6.2). `nil` if none are rated.
        let averageRating: Double?

        var id: FacetKey { key }
    }

    let entries: [FilterDimension: [Entry]]

    subscript(dimension: FilterDimension) -> [Entry] {
        entries[dimension] ?? []
    }
}
