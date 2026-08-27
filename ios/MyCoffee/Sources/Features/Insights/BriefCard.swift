import SwiftUI

/// The "This month" editorial section (PLAN.md §6.4): "Reuse the existing
/// `/api/brief` + `briefs` table for a clearly separated section." Vertex
/// generates the copy server-side once a month; the app only renders it —
/// no on-device generation, unlike the templated findings below. Omitted
/// entirely until the backend has actually produced one (`nil` while a
/// month's brief hasn't generated yet, or the fetch failed/is offline).
///
/// `#89` restyle (`design/coffees_redesign/README.md` §"Brief card"):
/// `accent100` fill, radius 14, label `THIS MONTH` in `accent700`, body in
/// `accent800` — server copy unchanged, only the treatment moved.
struct BriefCard: View {
    let brief: Brief?

    var body: some View {
        if let brief {
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS MONTH")
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.accent700)
                Text(brief.title)
                    .font(.system(size: 14, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.accent800)
                Text(brief.body)
                    .font(.system(size: 14))
                    .lineSpacing(6.3)  // ~1.45 line-height at 14pt
                    .foregroundStyle(Theme.Colors.accent800)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.accent100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
