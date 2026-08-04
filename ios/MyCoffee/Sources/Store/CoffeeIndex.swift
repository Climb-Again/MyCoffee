import Foundation

private struct OriginCountryTally {
    let id: Int
    let name: String
    let highRatedCount: Int
    let allIndices: IndexSet
}

/// The full local snapshot as an in-memory index — no SwiftData/SQLite (see
/// PLAN.md §5 for why). Pure value type, no I/O: filtering is `IndexSet`
/// intersection over prebuilt postings, cheap enough at ~900 rows to run
/// synchronously on every keystroke and every tap.
struct CoffeeIndex: Sendable {
    let coffees: [Coffee]                                    // canonical order: purchasedOn desc
    let byID: [Coffee.ID: Int]
    let searchKeys: [String]                                 // parallel array, diacritic-folded haystacks
    let postings: [FilterDimension: [FacetKey: IndexSet]]
    let vocabulary: Vocabulary

    /// Folded free-text blobs from `/api/snapshot/text`, keyed by coffee id
    /// (PLAN.md §4) — the compact snapshot row omits raw captions/descriptions
    /// to stay near its ~140 B/row budget, so search over that text needs this
    /// separately-fetched supplement merged into `searchKeys` at build time.
    /// Retained (not just consumed) so a favorite-toggle rebuild
    /// (`SyncEngine`) can reconstruct the index without re-fetching it.
    let searchTexts: [String: String]

    /// Shared bucket widths for the two money dimensions, computed once from
    /// the whole dataset (PriceBand.swift) — `nil` when no coffee has that value.
    let priceWidthCents: Int?
    let pricePer100gWidthCents: Int?

    static let empty = CoffeeIndex(coffees: [], vocabulary: .empty)

    init(coffees rawCoffees: [Coffee], vocabulary: Vocabulary, searchTexts: [String: String] = [:]) {
        let sorted = rawCoffees.sorted { $0.purchasedOn > $1.purchasedOn }
        self.coffees = sorted
        self.byID = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0) })
        self.vocabulary = vocabulary
        self.searchTexts = searchTexts
        self.searchKeys = sorted.map { Self.searchKey(for: $0, vocabulary: vocabulary, searchTexts: searchTexts) }

        let priceWidth = PriceBand.widthCents(forEUR: sorted.compactMap { $0.priceEur })
        let ppgWidth = PriceBand.widthCents(forEUR: sorted.compactMap { $0.pricePer100gEur })
        self.priceWidthCents = priceWidth
        self.pricePer100gWidthCents = ppgWidth
        self.postings = Self.buildPostings(coffees: sorted, priceWidthCents: priceWidth, pricePer100gWidthCents: ppgWidth)
    }

    // MARK: - Lookup

    func coffee(id: Coffee.ID) -> Coffee? {
        byID[id].map { coffees[$0] }
    }

    /// A full rebuild with one row swapped in — used after a detail fetch
    /// enriches a single coffee (PLAN.md §4). Cheap enough to do on every
    /// such fetch at ~900 rows (PLAN.md §5), same as every other mutation
    /// here; no partial-postings-update path exists on purpose.
    func replacingCoffee(_ updated: Coffee) -> CoffeeIndex {
        guard byID[updated.id] != nil else { return self }
        let replaced = coffees.map { $0.id == updated.id ? updated : $0 }
        return CoffeeIndex(coffees: replaced, vocabulary: vocabulary, searchTexts: searchTexts)
    }

    func roaster(_ id: Int) -> Roaster? { vocabulary.roasters[id] }
    func country(_ id: Int) -> Country? { vocabulary.countries[id] }
    func farm(_ id: Int) -> Farm? { vocabulary.farms[id] }

    // MARK: - Filtering

    /// Every coffee whose fields satisfy every constrained dimension in `filter`.
    /// Empty per-dimension sets impose no constraint; multiple values within
    /// one dimension are OR'd, dimensions are AND'd.
    func matches(_ filter: CoffeeFilter) -> IndexSet {
        var result = IndexSet(coffees.indices)

        if !filter.query.isEmpty {
            let folded = filter.query.foldedForSearch
            let matchingIndices = searchKeys.indices.filter { searchKeys[$0].contains(folded) }
            result.formIntersection(IndexSet(matchingIndices))
        }

        func intersectPostings(_ dimension: FilterDimension, _ keys: [FacetKey]) {
            guard !keys.isEmpty else { return }
            var dimensionSet = IndexSet()
            for key in keys {
                if let set = postings[dimension]?[key] {
                    dimensionSet.formUnion(set)
                }
            }
            result.formIntersection(dimensionSet)
        }

        intersectPostings(.roaster, filter.roasterIDs.map { .vocabID($0) })
        intersectPostings(.roasterCountry, filter.roasterCountryIDs.map { .vocabID($0) })
        intersectPostings(.originCountry, filter.originCountryIDs.map { .vocabID($0) })
        intersectPostings(.farm, filter.farmIDs.map { .vocabID($0) })

        var profileKeys: [FacetKey] = filter.profiles.map { .profile($0) }
        if filter.includeUnknownProfile { profileKeys.append(.unknown) }
        intersectPostings(.profile, profileKeys)

        if let isDecaf = filter.isDecaf {
            intersectPostings(.decaf, [.bool(isDecaf)])
        }
        if filter.favoritesOnly {
            intersectPostings(.favorite, [.bool(true)])
        }
        intersectPostings(.ratingBand, filter.ratingBands.map { .ratingBand($0) })
        intersectPostings(.priceBand, filter.priceBands.map { .priceBand($0) })
        intersectPostings(.pricePer100gBand, filter.pricePer100gBands.map { .priceBand($0) })
        intersectPostings(.altitudeBand, filter.altitudeBands.map { .altitudeBand($0) })
        intersectPostings(.year, filter.years.map { .year($0) })

        return result
    }

    /// Convenience for the listing: matching coffees in the requested sort order.
    func coffees(matching filter: CoffeeFilter, sortedBy sort: SortOption) -> [Coffee] {
        matches(filter).map { coffees[$0] }.sorted { sort.isOrderedBefore($0, $1) }
    }

    // MARK: - Facets

    /// Per-dimension value counts, each computed with *that* dimension cleared
    /// from `filter` so a dimension never constrains its own counts (PLAN.md §5).
    func facets(for filter: CoffeeFilter) -> FacetCounts {
        var result: [FilterDimension: [FacetCounts.Entry]] = [:]
        for dimension in FilterDimension.allCases {
            guard let dimensionPostings = postings[dimension] else { continue }
            let base = matches(filter.clearing(dimension))
            var entries: [FacetCounts.Entry] = []
            for (key, indices) in dimensionPostings {
                let matched = base.intersection(indices)
                guard !matched.isEmpty else {
                    entries.append(FacetCounts.Entry(key: key, count: 0, averageRating: nil))
                    continue
                }
                let ratings = matched.compactMap { coffees[$0].rating }
                let average = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
                entries.append(FacetCounts.Entry(key: key, count: matched.count, averageRating: average))
            }
            result[dimension] = entries.sorted { $0.count > $1.count }
        }
        return FacetCounts(entries: result)
    }

    // MARK: - Top filter cards

    /// Resolves the brief's 8-into-7 overbooking (PLAN.md §6.1). Computed
    /// against the full, unfiltered corpus — tapping a card replaces whatever
    /// filter is active, so cards represent stable corpus segments, not the
    /// current selection.
    func topFilterCards(limit: Int = 7) -> [TopFilterCard] {
        let total = coffees.count
        guard total > 0 else { return [] }

        func makeCard(kind: TopFilterCard.Kind, title: String, indexSet: IndexSet) -> TopFilterCard? {
            let count = indexSet.count
            guard count >= 5, count < total else { return nil }
            return TopFilterCard(kind: kind, title: title, count: count)
        }

        var candidates: [TopFilterCard] = []

        if let favoriteIndices = postings[.favorite]?[.bool(true)],
           let card = makeCard(kind: .favorites, title: "Favourites", indexSet: favoriteIndices) {
            candidates.append(card)
        }

        if let highRatedIndices = postings[.ratingBand]?[.ratingBand(.fourFiveToFive)],
           let card = makeCard(kind: .highlyRated, title: "4.5+ ★", indexSet: highRatedIndices) {
            candidates.append(card)
        }

        let interestingProfiles: [(Profile, IndexSet)] = Profile.allCases
            .filter { $0.isInterestingForTopFilters }
            .compactMap { profile in
                postings[.profile]?[.profile(profile)].map { (profile, $0) }
            }
        if let (topProfile, indices) = interestingProfiles.max(by: { $0.1.count < $1.1.count }),
           let card = makeCard(kind: .process(topProfile), title: topProfile.displayName, indexSet: indices) {
            candidates.append(card)
        }

        let highRatedRowIndices = Set(coffees.indices.filter { (coffees[$0].rating ?? 0) >= 4.0 })
        var originCandidates: [OriginCountryTally] = []
        for (key, indices) in postings[.originCountry] ?? [:] {
            guard case let .vocabID(countryID) = key else { continue }
            var highRatedCount = 0
            for index in indices where highRatedRowIndices.contains(index) {
                highRatedCount += 1
            }
            let name = vocabulary.countries[countryID]?.name ?? "Unknown"
            originCandidates.append(OriginCountryTally(id: countryID, name: name, highRatedCount: highRatedCount, allIndices: indices))
        }
        originCandidates.sort { lhs, rhs in
            if lhs.highRatedCount != rhs.highRatedCount { return lhs.highRatedCount > rhs.highRatedCount }
            return lhs.name < rhs.name
        }

        for country in originCandidates.prefix(4) {
            if let card = makeCard(kind: .originCountry(id: country.id), title: country.name, indexSet: country.allIndices) {
                candidates.append(card)
            }
        }

        // Dedup by resulting row set — linear scan over at most a handful of
        // candidates, and avoids relying on `IndexSet` being `Hashable`
        // (`SetAlgebra` only guarantees `Equatable`).
        var seenRowSets: [IndexSet] = []
        var deduped: [TopFilterCard] = []
        for card in candidates {
            let rowSet = matches(card.filter)
            guard !seenRowSets.contains(rowSet) else { continue }
            seenRowSets.append(rowSet)
            deduped.append(card)
        }

        return Array(deduped.prefix(limit))
    }

    // MARK: - Building

    private static func searchKey(for coffee: Coffee, vocabulary: Vocabulary, searchTexts: [String: String]) -> String {
        var parts: [String] = []
        if let roasterID = coffee.roasterId, let roaster = vocabulary.roasters[roasterID] { parts.append(roaster.name) }
        for countryID in coffee.originCountryIds {
            if let country = vocabulary.countries[countryID] { parts.append(country.name) }
        }
        if let farmID = coffee.originFarmId, let farm = vocabulary.farms[farmID] { parts.append(farm.name) }
        if let profile = coffee.profile { parts.append(profile.displayName) }
        for note in [coffee.profileDetail, coffee.farmLotNote, coffee.rawTitle, coffee.rawCaption, coffee.rawDescription] {
            if let note { parts.append(note) }
        }
        if let text = searchTexts[coffee.id] { parts.append(text) }
        return parts.joined(separator: " ").foldedForSearch
    }

    private static func buildPostings(
        coffees: [Coffee],
        priceWidthCents: Int?,
        pricePer100gWidthCents: Int?
    ) -> [FilterDimension: [FacetKey: IndexSet]] {
        var postings: [FilterDimension: [FacetKey: IndexSet]] = [:]

        func add(_ dimension: FilterDimension, _ key: FacetKey, _ index: Int) {
            postings[dimension, default: [:]][key, default: IndexSet()].insert(index)
        }

        for (index, coffee) in coffees.enumerated() {
            if let roasterID = coffee.roasterId { add(.roaster, .vocabID(roasterID), index) }

            if let roasterCountryID = coffee.roasterCountryId {
                add(.roasterCountry, .vocabID(roasterCountryID), index)
            } else {
                add(.roasterCountry, .unknown, index)
            }

            if coffee.originCountryIds.isEmpty {
                add(.originCountry, .unknown, index)
            } else {
                for countryID in coffee.originCountryIds {
                    add(.originCountry, .vocabID(countryID), index)
                }
            }

            if let farmID = coffee.originFarmId {
                add(.farm, .vocabID(farmID), index)
            } else {
                add(.farm, .unknown, index)
            }

            if let profile = coffee.profile {
                add(.profile, .profile(profile), index)
            } else {
                add(.profile, .unknown, index)
            }

            add(.decaf, .bool(coffee.isDecaf), index)
            add(.favorite, .bool(coffee.isFavorite), index)
            add(.ratingBand, .ratingBand(RatingBand.band(for: coffee.rating)), index)

            if let priceEur = coffee.priceEur, let width = priceWidthCents {
                add(.priceBand, .priceBand(PriceBand.band(forEUR: priceEur, widthCents: width)), index)
            }
            if let perHundredGrams = coffee.pricePer100gEur, let width = pricePer100gWidthCents {
                add(.pricePer100gBand, .priceBand(PriceBand.band(forEUR: perHundredGrams, widthCents: width)), index)
            }

            for band in AltitudeBand.bands(forMin: coffee.altitudeMinM, max: coffee.altitudeMaxM) {
                add(.altitudeBand, .altitudeBand(band), index)
            }

            add(.year, .year(coffee.purchasedYear), index)
        }

        return postings
    }
}
