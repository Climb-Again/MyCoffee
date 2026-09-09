import Foundation

private struct OriginCountryTally {
    let id: Int
    let name: String
    let highRatedCount: Int
    let allIndices: IndexSet
}

/// A coffee's **cheap-for-quality** standing against the rest of the library
/// (#109) — a display-only derived value, no schema change.
///
/// This deliberately rewards a cheap bag you rated highly, not just a bag
/// that beats its price tier's average: the first version (#95) compared a
/// coffee's rating to the mean of its own price band, so price stopped
/// mattering once two bags shared a band. The question it answers now is
/// "how good is this, and how little did it cost, across the whole library."
///
/// `pillCount` is the number of filled pills (1–5) in the listing/detail value
/// meter: the library-wide quintile of the coffee's cheap-for-quality `score`
/// (see `CoffeeIndex.valueBand(for:)`), so more pills always means
/// better-liked-for-the-money.
///
/// `band` is never `nil` once a coffee has both a rating and a price — the
/// score is a library-wide percentile comparison, not a per-bucket mean, so
/// there is no "too few peers" case to suppress.
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
    /// to `valueBand(for:)`'s cheap-percentile lookup. Empty when no coffee
    /// has a price.
    let pricePer100gSorted: [Double]

    /// Every coffee's `rating` in the library, ascending — the input to
    /// `valueBand(for:)`'s rating-percentile lookup. Empty when no coffee is rated.
    let ratingsSorted: [Double]

    /// The cheap-for-quality `score` (see `valueBand(for:)`) of every coffee
    /// that has both a rating and a price, ascending — precomputed here so a
    /// score can be mapped to a band by `quintileRank` in O(log n) per row
    /// instead of rescanning the library for every visible cell.
    let valueScoresSorted: [Double]

    /// Rating sum/count per roaster id and per origin-country id, tallied
    /// **once** here (#112) rather than inside `topRoasterIDs`/
    /// `topOriginCountryIDs` — those are called from every visible row's
    /// `body` (`CoffeeRowView.isTopRoaster`/`.originAverage`), so rescanning
    /// all ~900 coffees on every call made scrolling the full library
    /// effectively O(rows²). `topAverages` now only filters+sorts these much
    /// smaller per-id maps, independent of `minCount` or library size.
    private let roasterRatingTally: (sums: [Int: Double], counts: [Int: Int])
    private let originCountryRatingTally: (sums: [Int: Double], counts: [Int: Int])

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
        let ratedSorted = sorted.compactMap { $0.rating }.sorted()
        self.ratingsSorted = ratedSorted

        var scores: [Double] = []
        if !ppgSorted.isEmpty && !ratedSorted.isEmpty {
            for coffee in sorted {
                guard let price = coffee.pricePer100gEur, let rating = coffee.rating else { continue }
                let ratingPct = Self.percentileRank(rating, in: ratedSorted)
                let cheapPct = 1 - Self.percentileRank(price, in: ppgSorted)
                scores.append(Self.cheapForQualityScore(ratingPct: ratingPct, cheapPct: cheapPct))
            }
        }
        self.valueScoresSorted = scores.sorted()

        self.roasterRatingTally = Self.ratingTally(coffees: sorted) { $0.roasterId.map { [$0] } ?? [] }
        self.originCountryRatingTally = Self.ratingTally(coffees: sorted) { $0.originCountryIds }
    }

    // MARK: - Lookup

    func coffee(id: Coffee.ID) -> Coffee? {
        byID[id].map { coffees[$0] }
    }

    /// A full rebuild with one row swapped in (or added, if `updated.id` isn't
    /// in the index yet — #130's quick-create placeholder is the one caller
    /// that inserts rather than replaces) — used after a detail fetch enriches
    /// a single coffee (PLAN.md §4). Cheap enough to do on every such fetch at
    /// ~900 rows (PLAN.md §5), same as every other mutation here; no partial-
    /// postings-update path exists on purpose.
    func replacingCoffee(_ updated: Coffee) -> CoffeeIndex {
        var replaced = coffees.map { $0.id == updated.id ? updated : $0 }
        if byID[updated.id] == nil {
            replaced.append(updated)
        }
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

        // Selecting "Unknown" on a dimension adds the missing-field bucket to
        // the OR set — so picking only Unknown matches exactly the coffees
        // lacking that field (what still needs editing). Every dimension
        // supports this the same way now (#117): the four band dimensions
        // used to be handled by `intersectPostings` directly below with no
        // `.unknown` arm at all, so `unknownDimensions.contains(.priceBand)`
        // (as `toggleFacet`'s wildcard already lets the UI set) silently
        // imposed no constraint — `buildPostings` never emitted an `.unknown`
        // key for them, so this appended it to an empty set and intersected
        // away nothing. See `buildPostings`'s matching fix.
        func withUnknown(_ dimension: FilterDimension, _ keys: [FacetKey]) -> [FacetKey] {
            filter.unknownDimensions.contains(dimension) ? keys + [.unknown] : keys
        }
        func keysWithUnknown(_ dimension: FilterDimension, _ ids: Set<Int>) -> [FacetKey] {
            withUnknown(dimension, ids.map { .vocabID($0) })
        }
        intersectPostings(.roaster, keysWithUnknown(.roaster, filter.roasterIDs))
        intersectPostings(.roasterCountry, keysWithUnknown(.roasterCountry, filter.roasterCountryIDs))
        intersectPostings(.originCountry, keysWithUnknown(.originCountry, filter.originCountryIDs))
        intersectPostings(.farm, keysWithUnknown(.farm, filter.farmIDs))
        intersectPostings(.profile, withUnknown(.profile, filter.profiles.map { .profile($0) }))

        if let isDecaf = filter.isDecaf {
            intersectPostings(.decaf, [.bool(isDecaf)])
        }
        if filter.favoritesOnly {
            intersectPostings(.favorite, [.bool(true)])
        }
        intersectPostings(.ratingBand, withUnknown(.ratingBand, filter.ratingBands.map { .ratingBand($0) }))
        intersectPostings(.priceBand, withUnknown(.priceBand, filter.priceBands.map { .priceBand($0) }))
        intersectPostings(.pricePer100gBand, withUnknown(.pricePer100gBand, filter.pricePer100gBands.map { .priceBand($0) }))
        intersectPostings(.altitudeBand, withUnknown(.altitudeBand, filter.altitudeBands.map { .altitudeBand($0) }))
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

    /// The coffee's **cheap-for-quality** standing (#109, replacing the
    /// per-price-band mean-comparison version from #95; reweighted 65/35 by
    /// #139).
    ///
    /// `ratingPct` is the coffee's rating's percentile rank among all rated
    /// coffees, `cheapPct` is 1 minus its price's percentile rank among all
    /// priced coffees (so cheaper scores higher) — see `cheapForQualityScore`
    /// for how the two combine. Percentiles, not z-scores or a band mean — a
    /// handful of 100+€/100g outliers would otherwise wreck a mean/SD
    /// comparison.
    ///
    /// The score is mapped to the same five pill bands by its own quintile
    /// among all rated-and-priced coffees (`valueScoresSorted`), so `band` is
    /// never `nil` once a coffee has both a rating and a price — there is no
    /// "too few peers" case, since the comparison is library-wide.
    ///
    /// `nil` — no meter at all — when the coffee is **unrated** or has no price.
    func valueBand(for coffee: Coffee) -> ValueRating? {
        guard let price = coffee.pricePer100gEur,
              let rating = coffee.rating,
              !pricePer100gSorted.isEmpty,
              !ratingsSorted.isEmpty,
              !valueScoresSorted.isEmpty
        else { return nil }

        let ratingPct = Self.percentileRank(rating, in: ratingsSorted)
        let cheapPct = 1 - Self.percentileRank(price, in: pricePer100gSorted)
        let score = Self.cheapForQualityScore(ratingPct: ratingPct, cheapPct: cheapPct)
        // One scale: the band IS the pill count (#105).
        let band = ValueRating.Band(rawValue: Self.quintileRank(score, in: valueScoresSorted))!
        return ValueRating(band: band, pillCount: band.rawValue)
    }

    /// Combines a coffee's rating percentile and cheapness percentile into
    /// one cheap-for-quality score (#139, Radu 2026-09-07: "give more weight
    /// to rating than price, something like 65/35" — up from #109's even
    /// 50/50 product). A **weighted geometric mean** rather than a weighted
    /// arithmetic mean, deliberately: it keeps the original product's
    /// "both must be decent" behaviour (either percentile at 0 still zeroes
    /// the whole score, so a cheap-but-mediocre bag can't buy its way up),
    /// while letting rating dominate the trade-off between two otherwise
    /// close bags — the opposite of #109's even split, where a slightly
    /// cheaper but clearly worse-rated bag could out-rank a pricier,
    /// better-rated one.
    private static func cheapForQualityScore(ratingPct: Double, cheapPct: Double) -> Double {
        let ratingWeight = 0.65
        let cheapWeight = 0.35
        return pow(ratingPct, ratingWeight) * pow(cheapPct, cheapWeight)
    }

    /// Roasters with at least `minCount` rated coffees, sorted descending by
    /// average rating — `.first` is "your best roaster" (design handoff
    /// §Row/§Screen 2). Unrated coffees and coffees with no roaster don't count.
    func topRoasterIDs(minCount: Int = 5) -> [TopVocabAverage] {
        Self.topAverages(minCount: minCount, tally: roasterRatingTally)
    }

    /// Same as `topRoasterIDs` but over origin countries — a coffee with
    /// multiple origins (a blend) contributes to each of its countries.
    func topOriginCountryIDs(minCount: Int = 5) -> [TopVocabAverage] {
        Self.topAverages(minCount: minCount, tally: originCountryRatingTally)
    }

    /// One O(n) pass over `coffees` building rating sum/count per id — the
    /// part of the old `topAverages` that must not repeat per call (#112).
    private static func ratingTally(
        coffees: [Coffee],
        idsFor: (Coffee) -> [Int]
    ) -> (sums: [Int: Double], counts: [Int: Int]) {
        var ratingSums: [Int: Double] = [:]
        var ratingCounts: [Int: Int] = [:]
        for coffee in coffees {
            guard let rating = coffee.rating else { continue }
            for id in idsFor(coffee) {
                ratingSums[id, default: 0] += rating
                ratingCounts[id, default: 0] += 1
            }
        }
        return (ratingSums, ratingCounts)
    }

    /// Filters + sorts an already-tallied rating map — cheap regardless of
    /// `minCount` or library size, since it never revisits `coffees`.
    private static func topAverages(
        minCount: Int,
        tally: (sums: [Int: Double], counts: [Int: Int])
    ) -> [TopVocabAverage] {
        tally.counts
            .filter { $0.value >= minCount }
            .map { id, count in TopVocabAverage(id: id, average: tally.sums[id]! / Double(count), count: count) }
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
        let fraction = percentileRank(value, in: sortedValues)
        let rank = Int((fraction * 5).rounded(.up))
        return min(max(rank, 1), 5)
    }

    /// Fraction (0...1) of `sortedValues` (ascending) that is `<= value` —
    /// the percentile rank used by `valueBand(for:)`'s cheap/rating scores,
    /// and the shared building block for `quintileRank`'s five buckets.
    private static func percentileRank(_ value: Double, in sortedValues: [Double]) -> Double {
        var lo = 0
        var hi = sortedValues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedValues[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return Double(lo) / Double(sortedValues.count)
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

            // The four band dimensions (#117): each already has its own
            // "no value" band case for a labelled facet chip (`.unrated`,
            // `AltitudeBand.unknown`, or simply no posting at all for the two
            // price bands before this fix) — but the Insights data-quality
            // rows and the chart "Unknown" slices route through
            // `FilterDimension`'s generic `.unknown` bucket instead
            // (`toggleFacet`'s wildcard), which was never populated for these
            // four. Add `.unknown` alongside the normal band key whenever a
            // coffee lands in that dimension's "no value" bucket, so both
            // paths resolve to the same row set.
            let ratingBand = RatingBand.band(for: coffee.rating)
            add(.ratingBand, .ratingBand(ratingBand), index)
            if ratingBand == .unrated {
                add(.ratingBand, .unknown, index)
            }

            if let priceEur = coffee.priceEur, let width = priceWidthCents {
                add(.priceBand, .priceBand(PriceBand.band(forEUR: priceEur, widthCents: width)), index)
            } else {
                add(.priceBand, .unknown, index)
            }
            if let perHundredGrams = coffee.pricePer100gEur, let width = pricePer100gWidthCents {
                add(.pricePer100gBand, .priceBand(PriceBand.band(forEUR: perHundredGrams, widthCents: width)), index)
            } else {
                add(.pricePer100gBand, .unknown, index)
            }

            // `AltitudeBand.bands(forMin:max:)` already returns exactly
            // `[.unknown]` (its own case, not `FacetKey.unknown`) for missing
            // altitude data — never an empty array — so the generic bucket
            // needs its own explicit check rather than `isEmpty`.
            let altitudeBands = AltitudeBand.bands(forMin: coffee.altitudeMinM, max: coffee.altitudeMaxM)
            for band in altitudeBands {
                add(.altitudeBand, .altitudeBand(band), index)
            }
            if altitudeBands == [.unknown] {
                add(.altitudeBand, .unknown, index)
            }

            add(.year, .year(coffee.purchasedYear), index)
        }

        return postings
    }
}
