import SwiftUI
import Charts

/// All iOS 17-safe: `BarMark`/`LineMark`/`PointMark`/`RuleMark` +
/// `.chartForegroundStyleScale` only — never iOS 18's `BarPlot`/`LinePlot` or
/// iOS 26's `Chart3D` (PLAN.md §6.4).
enum ChartPalette {
    /// A fixed hue rotation for dimensions with no existing tag color to
    /// match (origin country, roaster). `Color.gray` is reserved for the
    /// "Other" bucket so it reads the same way on every chart on the page.
    static let rotation: [Color] = [
        Color(red: 0.70, green: 0.23, blue: 0.12),
        Color(red: 0.04, green: 0.42, blue: 0.71),
        Color(red: 0.42, green: 0.25, blue: 0.63),
        Color(red: 0.05, green: 0.49, blue: 0.42),
        Color(red: 0.66, green: 0.08, blue: 0.35),
        Color(red: 0.85, green: 0.55, blue: 0.10),
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

/// Average rating by year with a dashed `RuleMark` at the all-time mean, so
/// a given year reads as above/below the corpus baseline at a glance.
struct RatingByYearChart: View {
    struct Point: Identifiable {
        let year: Int
        let averageRating: Double
        var id: Int { year }
    }

    let points: [Point]
    let allTimeMean: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Average rating by year").font(.headline)
            if points.isEmpty {
                Text("Not enough rated coffees yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Year", point.year), y: .value("Rating", point.averageRating))
                        PointMark(x: .value("Year", point.year), y: .value("Rating", point.averageRating))
                    }
                    RuleMark(y: .value("All-time mean", allTimeMean))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 200)
            }
        }
    }
}
