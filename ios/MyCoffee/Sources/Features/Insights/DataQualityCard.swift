import SwiftUI

/// One of the "two additions the brief doesn't ask for but should have"
/// (PLAN.md §6.4): per-field completeness, pinned at the top of Insights.
/// Each row is meant to tap through to the review queue filtered to that
/// field — deferred here since the real Review queue (#27) isn't built yet
/// (still blocked on #24); rows render as plain stats until then. Omitted
/// entirely when every field is 100% complete.
struct DataQualityCard: View {
    let fields: [InsightsAggregation.DataQualityField]

    var body: some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Data quality", systemImage: Symbols.dataQuality)
                    .font(.headline)
                ForEach(fields) { field in
                    HStack {
                        Text(field.label)
                        Spacer()
                        Text("\(field.missing) of \(field.total) missing")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
