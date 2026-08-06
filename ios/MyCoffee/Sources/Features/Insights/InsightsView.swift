import SwiftUI

/// The Insights tab (PLAN.md §6.4): the editorial "This month" brief, a data
/// quality card, gated correlation findings, then the four yearly charts.
/// The charts/findings run on-device against the already-synced index —
/// recomputation after any edit is instant and offline, and templated
/// sentences are deterministic where an LLM would add hallucination risk and
/// per-render cost. The brief itself is the one exception: it's fetched from
/// `GET /api/brief` (Vertex-authored, reused rather than duplicated) via
/// `CoffeeStore.loadBrief()`, now that the shell lane has added it.
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
                        if let brief {
                            EditorialBriefCard(brief: brief)
                        }
                        DataQualityCard(fields: InsightsAggregation.dataQuality(coffees: coffees))
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

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            YearlyStackedChart(
                title: "Coffees by origin country",
                data: InsightsAggregation.yearlyTopCategories(coffees: coffees, topN: 6) { coffee in
                    coffee.isBlend ? "Blend" : (coffee.primaryOriginCountry(vocabulary: vocabulary)?.name ?? "Unknown")
                }
            )

            YearlyStackedChart(
                title: "Coffees by process",
                // topN covers every profile *plus* "Unknown" — process has a
                // small, fixed domain, so there's never a real "Other" bucket
                // to fall into (unlike roaster/origin country, which do).
                data: InsightsAggregation.yearlyTopCategories(coffees: coffees, topN: Profile.allCases.count + 1) { coffee in
                    coffee.profile?.displayName ?? "Unknown"
                },
                overrideColors: processColors
            )

            YearlyStackedChart(
                title: "Coffees by roaster",
                data: InsightsAggregation.yearlyTopCategories(coffees: coffees, topN: 6) { coffee in
                    coffee.roaster(vocabulary: vocabulary)?.name ?? "Unknown"
                }
            )

            RatingByYearChart(points: ratingByYearPoints, allTimeMean: allTimeMeanRating)
        }
    }

    private var processColors: [String: Color] {
        var colors = Dictionary(uniqueKeysWithValues: Profile.allCases.map { ($0.displayName, ProcessStyles.style(for: $0).color) })
        colors["Unknown"] = ProcessStyles.unknown.color
        return colors
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
