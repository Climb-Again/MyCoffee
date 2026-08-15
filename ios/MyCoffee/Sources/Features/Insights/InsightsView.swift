import SwiftUI

/// The Insights tab (PLAN.md §6.4), split into three sub-sections (Radu):
///
/// - **Insights** — the headline average, the editorial "This month" brief,
///   and the gated correlation findings ("what tends to score well").
/// - **Charts** — the per-dimension pie breakdowns, each legend now carrying
///   the slice's average rating, under a time-window control (All / last 12m /
///   last 18m / pick specific years).
/// - **Data** — the data-quality card (what still needs editing).
///
/// The findings/charts run on-device against the already-synced index —
/// recomputation after any edit is instant and offline, and templated
/// sentences are deterministic where an LLM would add hallucination risk and
/// per-render cost. The brief is the one exception: server-generated copy,
/// fetched fresh each time the tab appears via `CoffeeStore.loadBrief()`.
struct InsightsView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var useZScore = false
    @State private var brief: Brief?
    @State private var section: Section = .insights

    // Charts time-window (Charts section only).
    @State private var window: ChartWindow = .all
    @State private var selectedYears: Set<Int> = []

    private var coffees: [Coffee] { store.index.coffees }
    private var vocabulary: Vocabulary { store.index.vocabulary }

    enum Section: String, CaseIterable, Identifiable {
        case insights = "Insights"
        case charts = "Charts"
        case data = "Data"
        var id: String { rawValue }
    }

    /// The Charts time-window. `.years` filters to the explicitly-picked set
    /// (empty ⇒ all years, so switching to "By year" before picking doesn't
    /// blank the charts); the month windows are relative to today.
    enum ChartWindow: Hashable {
        case all
        case last12m
        case last18m
        case years
    }

    var body: some View {
        NavigationStack {
            Group {
                if coffees.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "Insights coming soon",
                            systemImage: Symbols.insightsEmpty,
                            description: Text("Breakdowns appear once coffees are synced.")
                        )
                        .padding(.top, 60)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch section {
                            case .insights: insightsSection
                            case .charts: chartsSection
                            case .data: dataSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if !coffees.isEmpty {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .navigationTitle("Insights")
            .task { brief = await store.loadBrief() }
        }
    }

    // MARK: - Insights section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            headlineCard
            BriefCard(brief: brief)
            findingsSection
        }
    }

    /// The one-line corpus summary: how many coffees, and the overall average
    /// rating across the rated ones — the "average rating in insights" ask.
    private var headlineCard: some View {
        HStack(spacing: 20) {
            stat(value: "\(coffees.count)", label: coffees.count == 1 ? "coffee" : "coffees")
            if let mean = overallAverageRating {
                Divider().frame(height: 34)
                stat(value: "★ " + String(format: "%.2f", mean), label: "average rating")
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

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

    // MARK: - Data section

    private var dataSection: some View {
        DataQualityCard(fields: InsightsAggregation.dataQuality(coffees: coffees))
    }

    // MARK: - Charts section

    /// A pie per listing-filter field, all sourced from the same facet counts
    /// the filter sheet uses — but computed over the *windowed* subset so the
    /// breakdowns (and their per-slice average ratings) reflect the chosen
    /// time range. Building a throwaway `CoffeeIndex` from the subset reuses
    /// the exact facet/averaging code the listing relies on, so the numbers
    /// always agree with what filtering to that window would show.
    private var chartsSection: some View {
        let windowed = windowedCoffees
        let facets = CoffeeIndex(coffees: windowed, vocabulary: vocabulary).facets(for: CoffeeFilter())
        return VStack(alignment: .leading, spacing: 24) {
            windowControls
            windowSummary(for: windowed)
            if windowed.isEmpty {
                Text("No coffees in this window.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(pieDimensions, id: \.self) { dimension in
                    CategoryPieChart(title: dimension.title, slices: slices(for: dimension, facets: facets))
                }
            }
        }
    }

    private var windowControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Time window", selection: $window) {
                Text("All").tag(ChartWindow.all)
                Text("12m").tag(ChartWindow.last12m)
                Text("18m").tag(ChartWindow.last18m)
                Text("By year").tag(ChartWindow.years)
            }
            .pickerStyle(.segmented)

            if window == .years {
                yearPicker
            }
        }
    }

    /// Multi-select year chips, newest first — a bare `Menu` closes on every
    /// tap, which makes picking several years painful, so the years drop down
    /// as toggleable pills instead (reusing the listing's `FilterPill`).
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            WrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(availableYears, id: \.self) { year in
                    FilterPill(
                        title: "\(year)",
                        count: yearCounts[year] ?? 0,
                        averageRating: nil,
                        isSelected: selectedYears.contains(year)
                    ) {
                        if selectedYears.contains(year) { selectedYears.remove(year) }
                        else { selectedYears.insert(year) }
                    }
                }
            }
            if selectedYears.isEmpty {
                Text("Showing every year — tap years to narrow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func windowSummary(for windowed: [Coffee]) -> some View {
        let ratings = windowed.compactMap(\.rating)
        let mean = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
        return HStack(spacing: 6) {
            Text("\(windowed.count) " + (windowed.count == 1 ? "coffee" : "coffees"))
            if let mean {
                Text("· ★ " + String(format: "%.2f", mean) + " average")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
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
            PieSlice(
                label: facetLabel($0.key, dimension: dimension, vocabulary: vocabulary),
                count: $0.count,
                averageRating: $0.averageRating
            )
        }
        let overflow = entries.dropFirst(maxSlices).reduce(0) { $0 + $1.count }
        // "Other" carries no average — the per-entry means can't be re-averaged
        // without their rated counts, and a wrong number is worse than none.
        if overflow > 0 { slices.append(PieSlice(label: "Other", count: overflow, averageRating: nil)) }
        return slices
    }

    // MARK: - Windowing

    private var windowedCoffees: [Coffee] {
        switch window {
        case .all:
            return coffees
        case .last12m:
            return coffeesSince(months: 12)
        case .last18m:
            return coffeesSince(months: 18)
        case .years:
            guard !selectedYears.isEmpty else { return coffees }
            return coffees.filter { selectedYears.contains($0.purchasedYear) }
        }
    }

    private func coffeesSince(months: Int) -> [Coffee] {
        let cutoff = Calendar.utc.date(byAdding: .month, value: -months, to: Date()) ?? .distantPast
        return coffees.filter { $0.purchasedOn.utcMidnight >= cutoff }
    }

    private var availableYears: [Int] {
        Array(Set(coffees.map(\.purchasedYear))).sorted(by: >)
    }

    private var yearCounts: [Int: Int] {
        Dictionary(coffees.map { ($0.purchasedYear, 1) }, uniquingKeysWith: +)
    }

    private var overallAverageRating: Double? {
        let ratings = coffees.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }
}
