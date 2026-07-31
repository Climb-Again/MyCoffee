import SwiftUI

/// The row of up to 7 top filter cards above the listing (PLAN.md §6.1).
/// Tapping a card **replaces** the whole filter — additive cards on top of a
/// filter sheet would make "Show 862" incomprehensible.
struct TopFilterCardsRow: View {
    let cards: [TopFilterCard]
    let activeFilter: CoffeeFilter
    let onSelect: (TopFilterCard) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cards) { card in
                    Button {
                        onSelect(card)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(card.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isActive(card) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isActive(card) ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private func isActive(_ card: TopFilterCard) -> Bool {
        activeFilter == card.filter
    }
}
