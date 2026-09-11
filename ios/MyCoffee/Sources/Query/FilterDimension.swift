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
    /// Cheap-for-quality standing (#113) — the same five bands the listing and
    /// detail value meters already paint, promoted to a filter axis so
    /// "show me only GREAT VALUE bags" is one tap. Derived from the whole
    /// library (`CoffeeIndex.valueBand(for:)`), not stored on `Coffee`, so its
    /// postings are built from the index's own value scores.
    case valueBand
    case altitudeBand
    case year
    /// Brew lab (PLAN.md §14, #156/#158) — one dimension per catalogue kind,
    /// postings keyed `.vocabID(optionId)` over **tried** ids (best ⊆ tried,
    /// so "coffees I made on the V60" is the natural read).
    case brewDevice
    case brewRecipe
    case brewGrind
    case brewTemp
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
    case valueBand(ValueRating.Band)
    case year(Int)
    /// A dimension's "Unknown" bucket — e.g. no `profile_id`, no `origin_farm_id`.
    case unknown
}
