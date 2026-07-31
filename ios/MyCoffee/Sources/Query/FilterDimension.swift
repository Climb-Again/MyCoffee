import Foundation

/// One axis of the filter sheet. `CoffeeIndex.postings` is keyed by this so
/// facet counts can clear exactly one dimension at a time (PLAN.md §5: "for
/// dimension D, counts are computed over `matches(filter.clearing(D))`").
enum FilterDimension: Hashable, CaseIterable, Sendable {
    case roaster
    case roasterCountry
    case originCountry
    case farm
    case profile
    case decaf
    case favorite
    case ratingBand
    case priceBand
    case pricePer100gBand
    case altitudeBand
    case year
}

/// A single facet value within a dimension. Heterogeneous by design — vocab
/// ids, enum cases, bands and booleans all need to live in one postings map —
/// but kept a closed, type-checked enum rather than `AnyHashable` so a typo
/// can't silently produce an empty facet.
enum FacetKey: Hashable, Sendable {
    case vocabID(Int)
    case profile(Profile)
    case bool(Bool)
    case ratingBand(RatingBand)
    case priceBand(PriceBand)
    case altitudeBand(AltitudeBand)
    case year(Int)
    /// A dimension's "Unknown" bucket — e.g. no `profile_id`, no `origin_farm_id`.
    case unknown
}
