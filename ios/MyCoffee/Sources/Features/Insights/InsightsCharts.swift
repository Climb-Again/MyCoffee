import SwiftUI
import Charts

/// All iOS 17-safe: `BarMark`/`LineMark`/`PointMark`/`RuleMark` +
/// `.chartForegroundStyleScale` only — never iOS 18's `BarPlot`/`LinePlot` or
/// iOS 26's `Chart3D` (PLAN.md §6.4). Only `YearlyStackedChart` still uses
/// this — the Charts tab's per-dimension breakdown became `BreakdownCard`
/// (`#89`, no chart, no categorical palette needed).
enum ChartPalette {
    /// A balanced categorical palette (the Tableau-10 hues) — evenly spaced,
    /// consistent saturation/lightness, and legible in both light and dark.
    /// `Color.gray` is reserved for the "Other" bucket so it reads the same way
    /// on every chart on the page.
    static let rotation: [Color] = [
        Color(red: 0.31, green: 0.48, blue: 0.65),  // blue
        Color(red: 0.95, green: 0.56, blue: 0.17),  // orange
        Color(red: 0.35, green: 0.63, blue: 0.31),  // green
        Color(red: 0.88, green: 0.34, blue: 0.35),  // red
        Color(red: 0.69, green: 0.48, blue: 0.63),  // purple
        Color(red: 0.46, green: 0.72, blue: 0.70),  // teal
        Color(red: 0.93, green: 0.79, blue: 0.28),  // yellow
        Color(red: 1.00, green: 0.62, blue: 0.65),  // pink
        Color(red: 0.61, green: 0.46, blue: 0.37),  // brown
    ]

    static func scale(for categories: [String]) -> (domain: [String], range: [Color]) {
        var range: [Color] = []
        var next = 0
        for category in categories {
            if category == "Other" {
                range.append(.gray)
            } else {
                range.append(rotation[next % rotation.count])
                next += 1
            }
        }
        return (categories, range)
    }
}

/// One yearly-stacked-count chart. Colors are pinned via
/// `.chartForegroundStyleScale(domain:range:)` (PLAN.md §6.4) so a series
/// never shifts hue between charts; `overrideColors` lets the process chart
/// reuse `ProcessTag`'s exact hues instead of the generic rotation, so a
/// color in the chart means the same profile it means in the listing.
struct YearlyStackedChart: View {
    let title: String
    let data: InsightsAggregation.CategoryYearChartData
    var overrideColors: [String: Color]?

    private var scale: (domain: [String], range: [Color]) {
        if let overrideColors {
            return (data.categories, data.categories.map { overrideColors[$0] ?? .gray })
        }
        return ChartPalette.scale(for: data.categories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if data.points.isEmpty {
                Text("Not enough data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
            } else {
                Chart(data.points) { point in
                    BarMark(
                        x: .value("Year", String(point.year)),
                        y: .value("Coffees", point.count)
                    )
                    .foregroundStyle(by: .value("Category", point.category))
                }
                .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
                .frame(height: 200)
            }
        }
    }
}

/// The Charts tab's "what you rate highest" card (`#89`,
/// `design/coffees_redesign/README.md` §Screen 3) — replaces the old
/// donut-pie-per-dimension entirely. One bordered card, one dimension at a
/// time (picked via the caller's chip switcher), rows ordered by **average
/// rating** rather than count since the card answers "what do I rate
/// highest" — every row states its own sample size so a thin slice can still
/// be judged. `onSelect` is nil-able so previews can render non-interactively.
struct BreakdownCard: View {
    let title: String
    let entries: [FacetCounts.Entry]
    let dimension: FilterDimension
    let vocabulary: Vocabulary
    var onSelect: ((FacetKey) -> Void)?

    /// Rated entries (an average to sort and show) first, highest average
    /// first; unrated entries after, by count — never invented, never hidden.
    private var rankedEntries: [FacetCounts.Entry] {
        entries.filter { $0.count > 0 }.sorted { lhs, rhs in
            switch (lhs.averageRating, rhs.averageRating) {
            case let (l?, r?): return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            case (nil, nil): return lhs.count > rhs.count
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: Theme.Weight.heavy))
                .padding(.bottom, 12)
            if rankedEntries.isEmpty {
                Text("Not enough data yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(rankedEntries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                    if index < rankedEntries.count - 1 {
                        Rectangle()
                            .fill(Theme.Colors.hairline)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.Colors.neutral300, lineWidth: 1)
        )
    }

    private func row(_ entry: FacetCounts.Entry) -> some View {
        let label = facetLabel(entry.key, dimension: dimension, vocabulary: vocabulary)
        let content = HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                HStack(spacing: 4) {
                    if let average = entry.averageRating {
                        Image(systemName: Symbols.starFill)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(String(format: "%.2f", average))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.text)
                    }
                    Text("Based on \(entry.count) bag\(entry.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.neutral700)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: Symbols.chevronRight)
                .font(.system(size: 18))
                .foregroundStyle(Theme.Colors.neutral700)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        return Group {
            if let onSelect {
                Button { onSelect(entry.key) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}
