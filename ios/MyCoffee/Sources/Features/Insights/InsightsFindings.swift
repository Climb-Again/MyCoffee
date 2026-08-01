import Foundation

/// One gated, plain-language correlation sentence (PLAN.md §6.4). Always
/// states its `n`; never a p-value; ordered by `effectSize` (never shown).
struct InsightsFinding: Identifiable {
    let id = UUID()
    let text: String
    let effectSize: Double
}

/// Builds the capped, effect-size-ordered finding list. Every comparison
/// goes through `InsightsStats`'s gates, so a thin corpus (or a thin slice of
/// it, like `Papua New Guinea (1)`) simply produces no sentence rather than
/// a misleading one.
enum InsightsFindings {
    static func build(coffees: [Coffee], vocabulary: Vocabulary, useZScore: Bool, limit: Int = 12) -> [InsightsFinding] {
        let scored = scoredCoffees(coffees, useZScore: useZScore)
        guard !scored.isEmpty else { return [] }
        let unit = useZScore ? " z" : "★"

        var findings: [InsightsFinding] = []

        func addCategorical(subject: String, isIn: (Coffee) -> Bool) {
            let group = scored.filter { isIn($0.coffee) }.map(\.value)
            let outGroup = scored.filter { !isIn($0.coffee) }.map(\.value)
            guard let (delta, groupN, outN) = InsightsStats.categoricalDelta(group: group, outGroup: outGroup) else { return }
            let direction = delta > 0 ? "higher" : "lower"
            let magnitude = String(format: "%.2f", abs(delta))
            findings.append(InsightsFinding(
                text: "\(subject) tend to rate \(direction) than the rest — by \(magnitude)\(unit) (n=\(groupN) vs \(outN)).",
                effectSize: abs(delta)
            ))
        }

        for profile in Profile.allCases {
            addCategorical(subject: "\(profile.displayName) coffees") { $0.profile == profile }
        }
        addCategorical(subject: "Decaf coffees") { $0.isDecaf }

        for countryID in Set(scored.compactMap(\.coffee.originCountryId)) {
            guard let country = vocabulary.countries[countryID] else { continue }
            addCategorical(subject: "\(country.name) origin coffees") { $0.originCountryId == countryID }
        }

        for countryID in Set(scored.compactMap(\.coffee.roasterCountryId)) {
            guard let country = vocabulary.countries[countryID] else { continue }
            addCategorical(subject: "Roasters from \(country.name)") { $0.roasterCountryId == countryID }
        }

        // Capped to the 15 best-represented roasters — with n ≥ 5 already
        // gating every comparison, testing all ~100 roasters would mostly
        // waste cycles on groups too thin to ever pass.
        let roasterCounts = Dictionary(grouping: scored, by: { $0.coffee.roasterId }).mapValues(\.count)
        let topRoasterIDs = roasterCounts.sorted { $0.value > $1.value }.prefix(15).map(\.key)
        for roasterID in topRoasterIDs {
            guard let roaster = vocabulary.roasters[roasterID] else { continue }
            addCategorical(subject: roaster.name) { $0.roasterId == roasterID }
        }

        func addOrdinal(subject: String, x: (Coffee) -> Double?) {
            let pairs = scored.compactMap { entry -> (Double, Double)? in
                x(entry.coffee).map { ($0, entry.value) }
            }
            guard let (rho, n) = InsightsStats.spearman(pairs.map { $0.0 }, pairs.map { $0.1 }) else { return }
            let direction = rho > 0 ? "higher" : "lower"
            findings.append(InsightsFinding(
                text: "\(subject) tends toward \(direction) ratings (ρ = \(String(format: "%.2f", rho)), n=\(n)).",
                effectSize: abs(rho)
            ))
        }

        addOrdinal(subject: "Higher altitude") { $0.altitudeMidM.map { Double($0) } }
        addOrdinal(subject: "Higher price") { $0.priceEur }
        addOrdinal(subject: "Higher price per 100 g") { $0.pricePer100gEur }
        // Year-vs-rating is exactly the calibration-drift trend the z-score
        // mode exists to remove — within-year-normalized ratings average to
        // ~0 every year by construction, so the comparison is meaningless
        // once that mode is on.
        if !useZScore {
            addOrdinal(subject: "More recent purchases") { Double($0.purchasedYear) }
        }

        return Array(findings.sorted { $0.effectSize > $1.effectSize }.prefix(limit))
    }

    private struct ScoredCoffee {
        let coffee: Coffee
        let value: Double
    }

    private static func scoredCoffees(_ coffees: [Coffee], useZScore: Bool) -> [ScoredCoffee] {
        guard useZScore else {
            return coffees.compactMap { coffee in coffee.rating.map { ScoredCoffee(coffee: coffee, value: $0) } }
        }
        let rated = coffees.filter { $0.rating != nil }
        let points = rated.map { (year: $0.purchasedYear, rating: $0.rating!) }
        let zScores = InsightsStats.withinYearZScores(points)
        return zip(rated, zScores).compactMap { coffee, z in z.map { ScoredCoffee(coffee: coffee, value: $0) } }
    }
}
