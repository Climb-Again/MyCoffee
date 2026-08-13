import SwiftUI

/// The "This month" editorial section (PLAN.md §6.4): "Reuse the existing
/// `/api/brief` + `briefs` table for a clearly separated section." Vertex
/// generates the copy server-side once a month; the app only renders it —
/// no on-device generation, unlike the templated findings below. Omitted
/// entirely until the backend has actually produced one (`nil` while a
/// month's brief hasn't generated yet, or the fetch failed/is offline).
struct BriefCard: View {
    let brief: Brief?

    var body: some View {
        if let brief {
            VStack(alignment: .leading, spacing: 8) {
                Label("This month", systemImage: Symbols.brief)
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
}
