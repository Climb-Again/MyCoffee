import SwiftUI

/// The Insights tab (PLAN.md §6.4): Data quality card, the editorial "This
/// month" brief, gated correlation findings, then the four yearly charts.
/// The findings/charts run on-device against the already-synced index —
/// recomputation after any edit is instant and offline, and templated
/// sentences are deterministic where an LLM would add hallucination risk and
/// per-render cost. The brief is the one exception: server-generated copy,
/// fetched fresh each time the tab appears via `CoffeeStore.loadBrief()`.
struct InsightsView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var useZScore = false
    @State private var brief: Brief?

    private var coffees: [Coffee] { store.index.coffees }
    private var vocabulary: Vocabulary { store.index.vocabulary }

    var body: some View {
        NavigationStack {
            ScrollView {
                if coffees.isEmpty {
                    ContentUnavailableView(
                        "Insights coming soon",
                        systemImage: Symbols.insightsEmpty,
                        description: Text("Breakdowns appear once coffees are synced.")
                    )
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        DataQualityCard(fields: InsightsAggregation.dataQuality(coffees: coffees))
                        BriefCard(brief: brief)
                        findingsSection
                        chartsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Insights")
            .task { brief = await store.loadBrief() }
        }
    }

    // MARK: - Findings

    private var findings: [InsightsFinding] {
        InsightsFindings.build(coffees: coffees, vocabulary: vocabulary, useZScore: useZScore)
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What tends to score well")
                .font(.headline)
            Toggle(isOn: $useZScore) {
                Label("Adjust for yearly rating drift", systemImage: Symbols.zscoreToggle)
            }
            .toggleStyle(.button)
            .font(.caption)
            if findings.isEmpty {
                Text("Not enough rated coffees yet for a reliable comparison.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(findings) { finding in
                    Text(finding.text)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Charts

    /// A pie per listing-filter field, all sourced from the same facet counts
    /// the filter sheet uses (computed once over the full corpus), so the
    /// breakdowns always match what tapping that filter would show. The
    /// rating-by-year line stays too — a trend, which a pie can't show.
    private var chartsSection: some View {
        let facets = store.index.facets(for: CoffeeFilter())
        return VStack(alignment: .leading, spacing: 28) {
            ForEach(pieDimensions, id: \.self) { dimension in
                CategoryPieChart(title: dimension.title, slices: slices(for: dimension, facets: facets))
            }
            RatingByYearChart(points: ratingByYearPoints, allTimeMean: allTimeMeanRating)
        }
    }

    /// The filterable fields worth a breakdown, in display order. `favorite` is
    /// omitted (a toggle, not a distribution).
    private var pieDimensions: [FilterDimension] {
        [.originCountry, .profile, .roaster, .roasterCountry, .farm, .decaf,
         .ratingBand, .priceBand, .pricePer100gBand, .altitudeBand, .year]
    }

    private func slices(for dimension: FilterDimension, facets: FacetCounts) -> [PieSlice] {
        let entries = facets[dimension]
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        let maxSlices = 8
        var slices = entries.prefix(maxSlices).map {
            PieSlice(label: facetLabel($0.key, dimension: dimension, vocabulary: vocabulary), count: $0.count)
        }
        let overflow = entries.dropFirst(maxSlices).reduce(0) { $0 + $1.count }
        if overflow > 0 { slices.append(PieSlice(label: "Other", count: overflow)) }
        return slices
    }

    private var allTimeMeanRating: Double {
        let ratings = coffees.compactMap(\.rating)
        guard !ratings.isEmpty else { return 0 }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    private var ratingByYearPoints: [RatingByYearChart.Point] {
        var byYear: [Int: [Double]] = [:]
        for coffee in coffees {
            guard let rating = coffee.rating else { continue }
            byYear[coffee.purchasedYear, default: []].append(rating)
        }
        return byYear
            .map { year, ratings in RatingByYearChart.Point(year: year, averageRating: ratings.reduce(0, +) / Double(ratings.count)) }
            .sorted { $0.year < $1.year }
    }
}
