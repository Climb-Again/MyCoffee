import SwiftUI

/// The Insights tab (PLAN.md §6.4), split into three sub-sections (Radu):
///
/// - **Insights** — the headline average, the editorial "This month" brief,
///   and the gated correlation findings ("what tends to score well").
/// - **Charts** — a per-dimension donut/pie breakdown, switched across
///   dimensions, under a time-window control (All / last 12m / last 18m /
///   pick specific years).
/// - **Data** — the data-quality card (what still needs editing).
///
/// The findings/charts run on-device against the already-synced index —
/// recomputation after any edit is instant and offline, and templated
/// sentences are deterministic where an LLM would add hallucination risk and
/// per-render cost. The brief is the one exception: server-generated copy,
/// fetched fresh each time the tab appears via `CoffeeStore.loadBrief()`.
///
/// `#89` redesign (`design/coffees_redesign/README.md` §Screen 3): blue
/// header field (matching the Coffees tab), three-pill section control
/// replacing the segmented Picker, a card-free headline, the restyled
/// `BriefCard`/findings.
///
/// `#99` (2026-08-28, Radu: "bring the pie charts back"): #89's
/// `CategoryPieChart`-replaced-by-`BreakdownCard` swap is reverted the other
/// way — the dimension chip switcher stays, but it now drives a
/// `CategoryPieChart` (`InsightsCharts.swift`) in a single-hue blue ramp
/// (replacing the old Tableau-10 rotation) instead of `BreakdownCard`'s
/// ranked list, which is gone.
struct InsightsView: View {
    @EnvironmentObject private var store: CoffeeStore
    @State private var useZScore = false
    @State private var brief: Brief?
    @State private var section: Section = .insights

    // Charts time-window + dimension switcher (Charts section only).
    @State private var window: ChartWindow = .all
    @State private var selectedYears: Set<Int> = []
    @State private var chartsDimension: FilterDimension = .originCountry

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
                        VStack(alignment: .leading, spacing: 0) {
                            headerSection
                            sectionControl
                                .padding(.horizontal, 22)
                                .padding(.top, 16)
                                .padding(.bottom, 20)
                            Group {
                                switch section {
                                case .insights: insightsSection
                                case .charts: chartsSection
                                case .data: dataSection
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .background(Theme.Colors.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.accent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { brief = await store.loadBrief() }
        }
    }

    // MARK: - Header

    /// "604 OF 862 RATED" — how many of the synced coffees have a rating.
    private var headerStats: String {
        let rated = coffees.filter { $0.rating != nil }.count
        return "\(rated) OF \(coffees.count) RATED"
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerStats)
                .font(.system(size: 10, weight: Theme.Weight.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.accent200)
            Text("Insights")
                .font(.system(size: 36, weight: Theme.Weight.heavy))
                .tracking(-1.08)
                .foregroundStyle(Theme.Colors.onAccent)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accent)
    }

    // MARK: - Section control (replaces the segmented Picker)

    private var sectionControl: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases) { candidate in
                equalPill(candidate.rawValue, isSelected: section == candidate) {
                    section = candidate
                }
            }
        }
    }

    /// One of the three equal-width pills shared by the section control and
    /// the time-window control (§Screen 3: same `min-height 44`, radius 999
    /// treatment, selected = accent fill).
    private func equalPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: Theme.Weight.semibold))
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.neutral900)
                .frame(maxWidth: .infinity, minHeight: Theme.minHitTarget)
                .background(Capsule().fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface))
                .overlay(Capsule().strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// A natural-width chip — the dimension switcher and the year picker
    /// (horizontally scrolling, so pills shouldn't stretch to fill the row).
    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: Theme.Weight.semibold))
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.neutral900)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minHitTarget)
                .background(Capsule().fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface))
                .overlay(Capsule().strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Insights section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            headlineStats
            BriefCard(brief: brief)
            findingsSection
        }
    }

    /// Two stats side by side, no card (§Screen 3 "Headline"): coffee count,
    /// and the overall average rating across the rated ones.
    private var headlineStats: some View {
        HStack(spacing: 28) {
            headlineStat(value: "\(coffees.count)", label: coffees.count == 1 ? "coffee" : "coffees")
            if let mean = overallAverageRating {
                headlineStat(
                    value: String(format: "%.2f", mean),
                    label: "average rating",
                    accent: true,
                    star: true
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func headlineStat(value: String, label: String, accent: Bool = false, star: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: Theme.Weight.heavy))
                    .foregroundStyle(accent ? Theme.Colors.accent : Theme.Colors.text)
                if star {
                    Image(systemName: Symbols.starFill)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.neutral700)
        }
    }

    private var findings: [InsightsFinding] {
        InsightsFindings.build(coffees: coffees, vocabulary: vocabulary, useZScore: useZScore)
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What tends to score well")
                .font(.system(size: 17, weight: Theme.Weight.heavy))
            driftTogglePill
            if findings.isEmpty {
                Text("Not enough rated coffees yet for a reliable comparison.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(findings) { finding in
                        Text(findingAttributedText(finding))
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.findingLinkScheme,
                  let uuid = UUID(uuidString: url.host ?? ""),
                  let finding = findings.first(where: { $0.id == uuid }),
                  let subject = finding.subject
            else { return .discarded }
            selectInCoffees(dimension: subject.dimension, key: subject.key)
            return .handled
        })
    }

    /// The z-score toggle as a pill button (§Screen 3: "becomes a pill
    /// button, same selected/unselected treatment as the section control"),
    /// natural width rather than one of the equal-width set.
    private var driftTogglePill: some View {
        chip("Adjust for yearly rating drift", isSelected: useZScore) {
            useZScore.toggle()
        }
    }

    private static let findingLinkScheme = "mycoffee-finding"

    /// Renders `finding.text` as: the subject phrase (when present) in
    /// `accent` semibold and tappable — the only link, unchanged from before
    /// — the effect clause in ink, and the trailing `(n=… )`/`(ρ = …)`
    /// parenthetical in `neutral700` (§Screen 3 "Findings"). The link target
    /// is a synthetic URL carrying just the finding's `id`; tapping it is
    /// intercepted by the `openURL` environment above and routed to the same
    /// `selectInCoffees` deep-link the breakdown card's rows use.
    private func findingAttributedText(_ finding: InsightsFinding) -> AttributedString {
        var attributed = AttributedString(finding.text)
        attributed.font = .system(size: 14)
        attributed.foregroundColor = Theme.Colors.text

        if let subjectText = finding.subjectText,
           let range = attributed.range(of: subjectText) {
            attributed[range].foregroundColor = Theme.Colors.accent
            attributed[range].font = .system(size: 14, weight: Theme.Weight.semibold)
            attributed[range].link = URL(string: "\(Self.findingLinkScheme)://\(finding.id.uuidString)")
        }
        if let parenStart = finding.text.lastIndex(of: "("),
           let range = attributed.range(of: String(finding.text[parenStart...])) {
            attributed[range].foregroundColor = Theme.Colors.neutral700
        }
        return attributed
    }

    // MARK: - Data section

    private var dataSection: some View {
        DataQualityCard(
            fields: InsightsAggregation.dataQuality(coffees: coffees),
            onSelect: { dimension in selectUnknownInCoffees(dimension: dimension) }
        )
    }

    /// Tapping a Data-quality row deep-links to the Coffees tab filtered to
    /// that field's Unknown/missing bucket (PLAN.md §13/#54) — a fresh
    /// filter, same "replaces, doesn't layer onto whatever was active"
    /// semantics as `selectInCoffees`.
    private func selectUnknownInCoffees(dimension: FilterDimension) {
        var filter = CoffeeFilter()
        filter.unknownDimensions.insert(dimension)
        store.filter = filter
        store.selectedTab = .coffees
    }

    // MARK: - Charts section

    /// One `CategoryPieChart` for the switcher's currently-picked dimension,
    /// sourced from facet counts computed over the *windowed* subset (a
    /// throwaway `CoffeeIndex` over the date-filtered coffees) so the
    /// breakdown always agrees with what filtering to that window would show.
    private var chartsSection: some View {
        let windowed = windowedCoffees
        let facets = CoffeeIndex(coffees: windowed, vocabulary: vocabulary).facets(for: CoffeeFilter())
        return VStack(alignment: .leading, spacing: 20) {
            windowControls
            windowSummary(for: windowed)
            if windowed.isEmpty {
                Text("No coffees in this window.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                dimensionSwitcher
                // #99: the pies are the Charts presentation now — they
                // replace #89's `BreakdownCard`, not sit alongside it.
                CategoryPieChart(
                    title: chartsDimension.title,
                    slices: pieSlices(for: chartsDimension, facets: facets),
                    onSelect: { key in selectInCoffees(dimension: chartsDimension, key: key) }
                )
            }
        }
    }

    /// Top-8 slices by count + a neutral "Other" for the remainder (§99
    /// constraint 1) — "Other" carries no average since per-entry means can't
    /// be re-averaged without their rated counts, and a wrong number is worse
    /// than none.
    private func pieSlices(for dimension: FilterDimension, facets: FacetCounts) -> [PieSlice] {
        let entries = facets[dimension]
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        let maxSlices = 8
        var slices = entries.prefix(maxSlices).map {
            PieSlice(
                label: facetLabel($0.key, dimension: dimension, vocabulary: vocabulary),
                count: $0.count,
                key: $0.key,
                averageRating: $0.averageRating
            )
        }
        let overflow = entries.dropFirst(maxSlices).reduce(0) { $0 + $1.count }
        if overflow > 0 { slices.append(PieSlice(label: "Other", count: overflow, key: nil, averageRating: nil)) }
        return slices
    }

    /// Four equal pills — All / 12m / 18m / By year (§Screen 3 "Time window").
    private var windowControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                equalPill("All", isSelected: window == .all) { window = .all }
                equalPill("12m", isSelected: window == .last12m) { window = .last12m }
                equalPill("18m", isSelected: window == .last18m) { window = .last18m }
                equalPill("By year", isSelected: window == .years) { window = .years }
            }
            if window == .years {
                yearPicker
            }
        }
    }

    /// Multi-select year chips, newest first, in the listing's chip style
    /// (§Screen 3: "reuse the listing chip style"). A bare `Menu` closes on
    /// every tap, which makes picking several years painful, so the years
    /// drop down as toggleable pills instead.
    private var yearPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            WrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(availableYears, id: \.self) { year in
                    chip("\(year) (\(yearCounts[year] ?? 0))", isSelected: selectedYears.contains(year)) {
                        if selectedYears.contains(year) { selectedYears.remove(year) }
                        else { selectedYears.insert(year) }
                    }
                }
            }
            if selectedYears.isEmpty {
                Text("Showing every year — tap years to narrow.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.neutral700)
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
        .font(.system(size: 12))
        .foregroundStyle(Theme.Colors.neutral700)
    }

    /// The dimension chip switcher over the breakdown card — the full facet
    /// set (roaster country, farm, decaf, rating/price/altitude bands, year
    /// included), one dimension at a time, rather than eleven stacked charts
    /// (§Screen 3). `favorite` is omitted (a toggle, not a distribution).
    /// Reuses `FilterDimension.title` — the same names the filter sheet
    /// already uses — rather than a second, parallel chip-copy scheme.
    private var chartsDimensions: [FilterDimension] {
        [.originCountry, .roaster, .profile, .roasterCountry, .farm, .decaf,
         .ratingBand, .priceBand, .pricePer100gBand, .altitudeBand, .year]
    }

    private var dimensionSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chartsDimensions, id: \.self) { dimension in
                    chip(dimension.title, isSelected: chartsDimension == dimension) {
                        chartsDimension = dimension
                    }
                }
            }
        }
    }

    /// Tapping a breakdown row replaces the Coffees listing's filter with
    /// exactly this value and switches to that tab (PLAN.md §13/#50) — a
    /// deep-link, not an additive toggle, so it always shows exactly what was
    /// tapped regardless of whatever filter was already active.
    private func selectInCoffees(dimension: FilterDimension, key: FacetKey) {
        var filter = CoffeeFilter()
        toggleFacet(key, dimension: dimension, in: &filter)
        filter.relativeWindow = currentRelativeWindow
        if window == .years { filter.years = selectedYears }
        store.filter = filter
        store.selectedTab = .coffees
    }

    /// Maps the Charts tab's own month-window control onto the listing
    /// filter's `RelativeWindow` (#71(b)) — the `.years` case carries its
    /// picked years across separately (`CoffeeFilter.years`, the existing
    /// specific-calendar-years field), not through `RelativeWindow`.
    private var currentRelativeWindow: RelativeWindow? {
        switch window {
        case .all, .years: return nil
        case .last12m: return .last12m
        case .last18m: return .last18m
        }
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
