import SwiftUI

/// The "This month" editorial section (PLAN.md §6.4): reuses `GET /api/brief`
/// rather than generating anything on-device, and is kept visually distinct
/// from the statistical findings below it — those are templated sentences
/// with gates and an `n`; this is Vertex-authored prose with neither. Renders
/// nothing when the backend hasn't generated a brief yet (`brief == nil`),
/// same "missing omits the row entirely" convention as `FactRowsCard`.
struct EditorialBriefCard: View {
    let brief: Brief

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This month", systemImage: Symbols.editorialBrief)
                .font(.headline)
            Text(brief.title)
                .font(.subheadline.weight(.semibold))
            Text(brief.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
