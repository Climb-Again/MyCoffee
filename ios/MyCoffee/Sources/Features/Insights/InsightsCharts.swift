import SwiftUI
import Charts

/// All iOS 17-safe: `BarMark`/`LineMark`/`PointMark`/`RuleMark` +
/// `.chartForegroundStyleScale` only — never iOS 18's `BarPlot`/`LinePlot` or
/// iOS 26's `Chart3D` (PLAN.md §6.4).
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

/// A donut/pie breakdown of one filterable dimension (origin, roaster, process,
/// price band, year, …) with a wrapped legend showing each slice's count and
/// average rating. Colors are pinned by label so the same category keeps its
/// hue. Tapping a legend label deep-links to the Coffees listing filtered to
/// that value (PLAN.md §13/#50) — `onSelect` is nil-able so previews/tests can
/// render a non-interactive chart.
struct CategoryPieChart: View {
    let title: String
    let slices: [PieSlice]
    var onSelect: ((FacetKey) -> Void)?

    private var scale: (domain: [String], range: [Color]) {
        ChartPalette.scale(for: slices.map(\.label))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if slices.isEmpty {
                Text("Not enough data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Coffees", slice.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value(title, slice.label))
                }
                .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
                .chartLegend(.hidden)
                .frame(height: 180)

                legend
            }
        }
    }

    private var legend: some View {
        let colors = Dictionary(uniqueKeysWithValues: zip(scale.domain, scale.range))
        return WrapLayout() {
            ForEach(slices) { slice in
                legendRow(slice, color: colors[slice.label] ?? .gray)
            }
        }
    }

    private func legendRow(_ slice: PieSlice, color: Color) -> some View {
        let content = HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(legendText(for: slice))
                .font(.caption)
                .foregroundStyle(.secondary)
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
