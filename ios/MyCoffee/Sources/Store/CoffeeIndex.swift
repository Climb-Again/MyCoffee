import Foundation

private struct OriginCountryTally {
    let id: Int
    let name: String
    let highRatedCount: Int
    let allIndices: IndexSet
}

/// A coffee's **quality-for-money** standing against the rest of the library
/// (`UPDATE_BRIEF.md` §B) — a display-only derived value, no schema change.
///
/// This deliberately is **not** a price percentile. The first version scored
/// price alone, so a cheap bag rated 3.2 read `FAIR VALUE`, which is exactly
/// backwards. The question it answers now is "for what this cost, did you like
/// it more or less than your other bags in the same price range."
///
/// `pillCount` is the number of filled pills (1–5) in the listing/detail value
/// meter: the coffee's **rating** rank within its own price band, so more pills
/// always means better-liked-for-the-money.
///
/// `band` is `nil` when the coffee's price band holds too few rated bags for its
/// mean to mean anything (`CoffeeIndex.minRatedPerPriceBand`) — the meter still
/// shows, the verdict is suppressed rather than guessed.
struct ValueRating: Sendable, Hashable {
    /// Five steps, one per pill (#105). The meter and its label are the SAME
    /// scale — `pillCount == band.rawValue` whenever a band exists — so they
    /// can never contradict each other. Before this, the meter had five steps
    /// and the label three, and 4 pills and 2 pills both printed
    /// `FAIR VALUE`; Radu caught it on the shipped build.
    enum Band: Int, Sendable {
        case overpaid = 1
        case poor = 2
        case fair = 3
        case good = 4
        case great = 5

        /// Whether to tint the meter and label with the accent — the positive
        /// half of the scale.
        var isPositive: Bool { self == .good || self == .great }
    }

    let band: Band?
    let pillCount: Int   // 1...5, and == band.rawValue when band != nil
}

/// A vocab entry (roaster or origin country) with its average rating across
/// the coffees that carry it, restricted to entries with at least
/// `minCount` rated coffees (design handoff §State) — used to mark the
/// user's own top roasters/origins in the row/detail views. Sorted
/// descending by average, so `.first` is "your best".
struct TopVocabAverage: Sendable, Hashable {
    let id: Int
    let average: Double
    let count: Int
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

    /// Every coffee's `pricePer100gEur` in the library, ascending — the input
    /// to `valueBand(for:)`'s price-band lookup. Empty when no coffee has a price.
    let pricePer100gSorted: [Double]

    /// Per price band (index 0–4 = quintile 1–5), the ascending ratings of the
    /// rated bags in that band, and their mean. Precomputed here so
    /// `valueBand(for:)` stays O(log n) per row rather than rescanning the
    /// library for every visible cell.
    let ratingsByPriceBand: [[Double]]
    let meanRatingByPriceBand: [Double?]

    /// Below this many rated bags in a price band, the band mean is noise —
    /// show the pills, suppress the verdict (`UPDATE_BRIEF.md` §B).
    static let minRatedPerPriceBand = 5

    /// The two cutoffs that split `delta` into the five steps above. Measured
    /// against the real library, not guessed: ±0.10/±0.30 spreads the 94
    /// rated-and-priced coffees 14% / 26% / 25% / 14% / 18% across
    /// overpaid → great, the most even of the shapes tried (±0.08/±0.25 and
    /// ±0.10/±0.25 both thin out `good` to 11%; ±0.12/±0.35 pushes `overpaid`
    /// down to 10%).
    ///
    /// Absolute cutoffs rather than a forced rank: in a price band where every
    /// bag really is equally good, nobody should be branded `OVERPAID` for
    /// sitting 0.05 below the mean. The cost is that a band with unusually tight
    /// spread will cluster on `fair` — correct, if less colourful.
    ///
    /// Per-band spread varies (SD 0.15 in the cheapest band vs 0.40 in the
    /// priciest), so if this reads wrong at the extremes, scale by the band's
    /// own SD rather than moving these numbers.
    static let valueDeltaNear = 0.10
    static let valueDeltaFar = 0.30

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
        let ppgSorted = sorted.compactMap { $0.pricePer100gEur }.sorted()
        self.pricePer100gSorted = ppgSorted

        var banded = [[Double]](repeating: [], count: 5)
        if !ppgSorted.isEmpty {
            for coffee in sorted {
                guard let price = coffee.pricePer100gEur, let rating = coffee.rating else { continue }
                banded[Self.quintileRank(price, in: ppgSorted) - 1].append(rating)
            }
        }
        self.ratingsByPriceBand = banded.map { $0.sorted() }
        self.meanRatingByPriceBand = banded.map { ratings in
            ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
        }
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

        // Relative-to-today window — computed against `now`, so (like `query`)
        // it can't live in the prebuilt postings and is applied directly here.
        if let window = filter.relativeWindow {
            let cutoff = window.cutoff()
            let matchingIndices = coffees.indices.filter { coffees[$0].purchasedOn.utcMidnight >= cutoff }
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

        // For the vocab dimensions, selecting "Unknown" adds the missing-field
        // bucket to the OR set — so picking only Unknown matches exactly the
        // coffees lacking that field (what still needs editing).
        func keysWithUnknown(_ dimension: FilterDimension, _ ids: Set<Int>) -> [FacetKey] {
            var keys: [FacetKey] = ids.map { .vocabID($0) }
            if filter.unknownDimensions.contains(dimension) { keys.append(.unknown) }
            return keys
        }
        intersectPostings(.roaster, keysWithUnknown(.roaster, filter.roasterIDs))
        intersectPostings(.roasterCountry, keysWithUnknown(.roasterCountry, filter.roasterCountryIDs))
        intersectPostings(.originCountry, keysWithUnknown(.originCountry, filter.originCountryIDs))
        intersectPostings(.farm, keysWithUnknown(.farm, filter.farmIDs))

        var profileKeys: [FacetKey] = filter.profiles.map { .profile($0) }
        if filter.unknownDimensions.contains(.profile) { profileKeys.append(.unknown) }
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

    // MARK: - Redesign derived values (#84)

    /// The coffee's **quality-for-money** standing (`UPDATE_BRIEF.md` §B).
    ///
    /// Bucket the library into five price bands by `pricePer100gEur`; inside the
    /// coffee's own band, compare its rating to the mean rating of the user's
    /// bags there. Pills are its rating rank within that band; the verdict comes
    /// from `delta = rating − bandMean`.
    ///
    /// `nil` — no meter at all — when the coffee is **unrated** or has no price.
    /// An unrated bag has no value judgement yet, and the old price-only version
    /// wrongly gave it one.
    func valueBand(for coffee: Coffee) -> ValueRating? {
        guard let price = coffee.pricePer100gEur,
              let rating = coffee.rating,
              !pricePer100gSorted.isEmpty
        else { return nil }

        let bandIndex = Self.quintileRank(price, in: pricePer100gSorted) - 1
        let peers = ratingsByPriceBand[bandIndex]
        guard !peers.isEmpty else { return nil }

        guard peers.count >= Self.minRatedPerPriceBand,
              let mean = meanRatingByPriceBand[bandIndex]
        else {
            // Too few rated bags in this band to judge: show the meter from the
            // coffee's rating rank, but no label. This is the one case where
            // pills without a verdict is correct rather than contradictory.
            return ValueRating(band: nil, pillCount: Self.quintileRank(rating, in: peers))
        }

        // One scale: the band IS the pill count (#105).
        let delta = rating - mean
        let band: ValueRating.Band
        if delta > Self.valueDeltaFar { band = .great }
        else if delta > Self.valueDeltaNear { band = .good }
        else if delta >= -Self.valueDeltaNear { band = .fair }
        else if delta >= -Self.valueDeltaFar { band = .poor }
        else { band = .overpaid }
        return ValueRating(band: band, pillCount: band.rawValue)
    }

    /// Roasters with at least `minCount` rated coffees, sorted descending by
    /// average rating — `.first` is "your best roaster" (design handoff
    /// §Row/§Screen 2). Unrated coffees and coffees with no roaster don't count.
    func topRoasterIDs(minCount: Int = 5) -> [TopVocabAverage] {
        Self.topAverages(minCount: minCount, coffees: coffees) { $0.roasterId.map { [$0] } ?? [] }
    }

    /// Same as `topRoasterIDs` but over origin countries — a coffee with
    /// multiple origins (a blend) contributes to each of its countries.
    func topOriginCountryIDs(minCount: Int = 5) -> [TopVocabAverage] {
        Self.topAverages(minCount: minCount, coffees: coffees) { $0.originCountryIds }
    }

    private static func topAverages(
        minCount: Int,
        coffees: [Coffee],
        idsFor: (Coffee) -> [Int]
    ) -> [TopVocabAverage] {
        var ratingSums: [Int: Double] = [:]
        var ratingCounts: [Int: Int] = [:]
        for coffee in coffees {
            guard let rating = coffee.rating else { continue }
            for id in idsFor(coffee) {
                ratingSums[id, default: 0] += rating
                ratingCounts[id, default: 0] += 1
            }
        }
        return ratingCounts
            .filter { $0.value >= minCount }
            .map { id, count in TopVocabAverage(id: id, average: ratingSums[id]! / Double(count), count: count) }
            .sorted { lhs, rhs in
                if lhs.average != rhs.average { return lhs.average > rhs.average }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }

    /// 1-indexed quintile rank (1 = cheapest/lowest, 5 = priciest) of `value`
    /// within `sortedValues` (ascending) — nearest-rank method: rank =
    /// `ceil(countLessOrEqual / total * 5)`, so the single most expensive
    /// value always lands in rank 5 and the cheapest in rank 1, with no
    /// off-by-one at either end regardless of `sortedValues.count % 5`.
    private static func quintileRank(_ value: Double, in sortedValues: [Double]) -> Int {
        var lo = 0
        var hi = sortedValues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedValues[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        let countLessOrEqual = lo
        let rank = Int((Double(countLessOrEqual) / Double(sortedValues.count) * 5).rounded(.up))
        return min(max(rank, 1), 5)
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
            if let roasterID = coffee.roasterId {
                add(.roaster, .vocabID(roasterID), index)
            } else {
                add(.roaster, .unknown, index)  // filterable "no roaster yet" bucket
            }

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
