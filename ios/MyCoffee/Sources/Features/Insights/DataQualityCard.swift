import SwiftUI

/// One of the "two additions the brief doesn't ask for but should have"
/// (PLAN.md §6.4): per-field completeness, pinned at the top of Insights.
/// Omitted entirely when every field is 100% complete. A row whose field has
/// a real `FilterDimension` (`field.dimension != nil`) deep-links to the
/// Coffees tab filtered to that field's Unknown bucket on tap (PLAN.md
/// §13/#54); a row with no dimension (e.g. weight isn't a listing facet)
/// renders as plain, non-interactive text.
struct DataQualityCard: View {
    let fields: [InsightsAggregation.DataQualityField]
    var onSelect: ((FilterDimension) -> Void)?

    var body: some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Data quality", systemImage: Symbols.dataQuality)
                    .font(.headline)
                ForEach(fields) { field in
                    row(field)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(_ field: InsightsAggregation.DataQualityField) -> some View {
        let content = HStack {
            Text(field.label)
            Spacer()
            Text("\(field.missing) of \(field.total) missing")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)

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
