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
    /// The "Unknown / missing" bucket — rendered in red so the fields that
    /// still need editing stand out at a glance (Radu's ask).
    var isUnknown: Bool = false
    let action: () -> Void

    private var accent: Color { isUnknown ? .red : .accentColor }

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
                Capsule().fill(
                    isSelected ? accent.opacity(0.22)
                        : (isUnknown ? Color.red.opacity(0.12) : Color.secondary.opacity(0.1))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? accent : (isUnknown ? Color.red.opacity(0.55) : .clear),
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isUnknown ? Color.red : .primary)
        .opacity((isEnabled && count > 0) || isSelected ? 1 : 0.3)
        .disabled(!isEnabled || (count == 0 && !isSelected))
    }
}
