import SwiftUI

/// One of the "two additions the brief doesn't ask for but should have"
/// (PLAN.md §6.4): per-field completeness, pinned at the top of Insights.
/// Omitted entirely when every field is 100% complete. A row whose field has
/// a real `FilterDimension` (`field.dimension != nil`) deep-links to the
/// Coffees tab filtered to that field's Unknown bucket on tap (PLAN.md
/// §13/#54); a row with no dimension (e.g. weight isn't a listing facet)
/// renders as plain, non-interactive text.
///
/// `#89` restyle (§Data section — "not redesigned, shared treatment only"):
/// no card background, 17pt/800 title, 11–12pt `neutral700` supporting text,
/// 44pt-tall rows.
struct DataQualityCard: View {
    let fields: [InsightsAggregation.DataQualityField]
    var onSelect: ((FilterDimension) -> Void)?

    var body: some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Data quality")
                    .font(.system(size: 17, weight: Theme.Weight.heavy))
                ForEach(fields) { field in
                    row(field)
                }
            }
        }
    }

    private func row(_ field: InsightsAggregation.DataQualityField) -> some View {
        let content = HStack {
            Text(field.label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            Text("\(field.missing) of \(field.total) missing")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.neutral700)
        }
        .frame(minHeight: Theme.minHitTarget)

        return Group {
            if let dimension = field.dimension, let onSelect {
                Button { onSelect(dimension) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}
