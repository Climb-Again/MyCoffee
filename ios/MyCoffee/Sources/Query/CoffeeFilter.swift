import Foundation

/// The full filter state for the listing. Every field is additive-within,
/// AND-across: an empty set on a dimension means "no constraint from this
/// dimension", not "match nothing".
struct CoffeeFilter: Equatable, Sendable {
    var query: String = ""

    var roasterIDs: Set<Int> = []
    var roasterCountryIDs: Set<Int> = []
    var originCountryIDs: Set<Int> = []
    var farmIDs: Set<Int> = []
    var profiles: Set<Profile> = []
    var includeUnknownProfile = false
    var isDecaf: Bool?             // nil = both
    var favoritesOnly = false
    var ratingBands: Set<RatingBand> = []
    var priceBands: Set<PriceBand> = []
    var pricePer100gBands: Set<PriceBand> = []
    var altitudeBands: Set<AltitudeBand> = []
    var years: Set<Int> = []

    var isEmpty: Bool {
        query.isEmpty
            && roasterIDs.isEmpty
            && roasterCountryIDs.isEmpty
            && originCountryIDs.isEmpty
            && farmIDs.isEmpty
            && profiles.isEmpty
            && !includeUnknownProfile
            && isDecaf == nil
            && !favoritesOnly
            && ratingBands.isEmpty
            && priceBands.isEmpty
            && pricePer100gBands.isEmpty
            && altitudeBands.isEmpty
            && years.isEmpty
    }

    /// Returns a copy with exactly one dimension's constraint removed — used
    /// to compute "what would this facet's count be if I hadn't filtered on
    /// it" (PLAN.md §5).
    func clearing(_ dimension: FilterDimension) -> CoffeeFilter {
        var copy = self
        switch dimension {
        case .roaster: copy.roasterIDs = []
        case .roasterCountry: copy.roasterCountryIDs = []
        case .originCountry: copy.originCountryIDs = []
        case .farm: copy.farmIDs = []
        case .profile:
            copy.profiles = []
            copy.includeUnknownProfile = false
        case .decaf: copy.isDecaf = nil
        case .favorite: copy.favoritesOnly = false
        case .ratingBand: copy.ratingBands = []
        case .priceBand: copy.priceBands = []
        case .pricePer100gBand: copy.pricePer100gBands = []
        case .altitudeBand: copy.altitudeBands = []
        case .year: copy.years = []
        }
        return copy
    }

    /// Replaces the entire filter — top filter cards fully replace rather than
    /// layer on top (PLAN.md §6.1: "Tapping a card replaces the whole filter").
    static func replacing(with kind: TopFilterCard.Kind) -> CoffeeFilter {
        var filter = CoffeeFilter()
        switch kind {
        case .favorites:
            filter.favoritesOnly = true
        case .highlyRated:
            filter.ratingBands = [.fourFiveToFive]
        case .process(let profile):
            filter.profiles = [profile]
        case .originCountry(let id):
            filter.originCountryIDs = [id]
        }
        return filter
    }
}
