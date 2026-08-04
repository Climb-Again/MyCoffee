import SwiftUI

/// A collapsed batch card (PLAN.md §6.5): *"23 coffees say Etiopia →
/// Ethiopia?"* — batch cards alone are meant to clear the large majority of
/// the queue in under 30 decisions.
struct ReviewBatchCardView: View {
    let group: ReviewBatchGroup
    let onAcceptAll: () -> Void
    let onReviewIndividually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(group.tasks.count) coffees", systemImage: group.field.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(group.tasks.count) coffees say **\(group.rawValue)** → \(group.topCandidate.value)?")
                .font(.title3.weight(.semibold))

            Text("Grouped by \(group.field.label.lowercased()) — the same correction applies to all of them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: onAcceptAll) {
                    Label("Accept all \(group.tasks.count)", systemImage: Symbols.reviewAccept)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onReviewIndividually) {
                    Text("Review individually")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}
