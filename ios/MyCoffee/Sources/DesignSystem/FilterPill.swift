import SwiftUI

/// One filter-sheet pill: `Label (count)` plus a trailing `★ 4.31` when a
/// mean rating is available (PLAN.md §6.2). Zero-count values render
/// disabled at 30% opacity rather than being hidden, so the corpus shape
/// stays visible even when a value can't currently be reached.
struct FilterPill: View {
    let title: String
    let count: Int
    let averageRating: Double?
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("\(title) (\(count))")
                if let averageRating {
                    Text("★ \(String(format: "%.2f", averageRating))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.1))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .opacity((isEnabled && count > 0) || isSelected ? 1 : 0.3)
        .disabled(!isEnabled || (count == 0 && !isSelected))
    }
}
