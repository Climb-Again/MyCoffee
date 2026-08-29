import SwiftUI
import Charts

/// All iOS 17-safe: `BarMark`/`LineMark`/`PointMark`/`RuleMark`/`SectorMark` +
/// `.chartForegroundStyleScale` only — never iOS 18's `BarPlot`/`LinePlot` or
/// iOS 26's `Chart3D` (PLAN.md §6.4).
enum ChartPalette {
    /// A balanced categorical palette (the Tableau-10 hues) — kept only for
    /// `YearlyStackedChart`'s origin-country/roaster series, which need many
    /// distinguishable categories at once. The single-dimension pie
    /// (`CategoryPieChart`) uses `blueRamp` instead (`#99`) — see there for why
    /// the two charts don't share a palette. `Color.gray` is reserved for the
    /// "Other" bucket on both so it reads the same way everywhere.
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

    /// Single-hue blue ramp anchored on the brand blue, replacing the
    /// Tableau-10 rotation for the Charts pie (`#99`, Radu: "replace, use
    /// blue palette") — Insights now reads as the same system as the rest of
    /// the 2a redesign. Index 0 is the most visually prominent step, handed
    /// to the largest slice (§99 constraint 2: colour follows rank).
    ///
    /// Deliberately **not** `Theme.Colors.accent100...accent800`: those
    /// dark-mode values are tuned for *text* contrast against `surface`, and
    /// #99 flagged that reusing them here would land several steps at a
    /// luminance close to `surface`'s near-black (`#141212`) — slices (and
    /// slice-vs-background) would wash out together in dark mode. These six
    /// steps are picked for slice/background separation specifically: the
    /// light ramp runs deep → pale, but the dark ramp runs bright → medium,
    /// so "index 0" is always the strongest contrast against *that* theme's
    /// surface, not literally the darkest hex value.
    static let blueRamp: [Color] = [
        Theme.adaptive(light: "00337F", dark: "BFE0FF"),
        Theme.adaptive(light: "0058C7", dark: "8FC2FF"),
        Theme.adaptive(light: "0078FF", dark: "5CACFF"),
        Theme.adaptive(light: "4FA6FF", dark: "3A86E0"),
        Theme.adaptive(light: "8FC7FF", dark: "285F9E"),
        Theme.adaptive(light: "CFE6FF", dark: "17324F"),
    ]

    /// Assigns `blueRamp` steps by rank (the caller sorts slices by count
    /// descending, so index order *is* rank), cycling past 6 slices — the
    /// top-8-slices-+-Other cap (§99 constraint 1) means up to 8 colours are
    /// needed from a 6-step single-hue ramp, so a few of the smallest kept
    /// slices can share a step. That's an accepted tradeoff of a single-hue
    /// ramp: the legend's label + count + rating always carries identity,
    /// never colour alone (§99 constraint 3). "Other" always gets neutral
    /// grey, never a ramp step.
    static func blueRampColors(for slices: [PieSlice]) -> [Color] {
        var colors: [Color] = []
        var rank = 0
        for slice in slices {
            if slice.key == nil {
                colors.append(.gray)
            } else {
                colors.append(blueRamp[rank % blueRamp.count])
                rank += 1
            }
        }
        return colors
    }
}

/// One slice of a category pie. `key` is `nil` for the aggregate "Other"
/// bucket, which doesn't correspond to a single filterable value and so isn't
/// tappable. `averageRating` is `nil` when the slice has no rated coffees.
struct PieSlice: Identifiable {
    let label: String
    let count: Int
    let key: FacetKey?
    let averageRating: Double?
    var id: String { label }
}

/// A donut/pie breakdown of one filterable dimension (origin, roaster,
/// process, price band, year, …), restored per `#99` — Radu wants the pies
/// back after #89 replaced them with `BreakdownCard`'s ranked-list-only
/// presentation. The legend states each slice's count and average rating and
/// stays the source of identity (§99 constraint 3); tapping a legend label
/// deep-links to the Coffees listing filtered to that value (PLAN.md §13/#50,
/// #50a/#50b) — `onSelect` is nil-able so previews/tests can render a
/// non-interactive chart.
struct CategoryPieChart: View {
    let title: String
    let slices: [PieSlice]
    var onSelect: ((FacetKey) -> Void)?

    private struct ColoredSlice: Identifiable {
        let slice: PieSlice
        let color: Color
        var id: String { slice.id }
    }

    private var coloredSlices: [ColoredSlice] {
        zip(slices, ChartPalette.blueRampColors(for: slices)).map { ColoredSlice(slice: $0, color: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.text)
            if slices.isEmpty {
                Text("Not enough data yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .frame(height: 60)
            } else {
                Chart(coloredSlices) { item in
                    SectorMark(
                        angle: .value("Coffees", item.slice.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(item.color)
                }
                .frame(height: 180)

                legend
            }
        }
    }

    private var legend: some View {
        WrapLayout(horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(coloredSlices) { item in
                legendRow(item.slice, color: item.color)
            }
        }
    }

    private func legendRow(_ slice: PieSlice, color: Color) -> some View {
        let content = HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(legendText(for: slice))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.neutral700)
        }
        .padding(.trailing, 4)

        return Group {
            if let key = slice.key, let onSelect {
                Button { onSelect(key) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    /// "Label · 12 · ★4.3" — the rating clause is dropped when the slice has
    /// no rated coffees (e.g. the "Other" bucket, or an all-unrated category).
    private func legendText(for slice: PieSlice) -> String {
        var text = "\(slice.label) · \(slice.count)"
        if let averageRating = slice.averageRating {
            text += " · ★\(String(format: "%.1f", averageRating))"
        }
        return text
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

