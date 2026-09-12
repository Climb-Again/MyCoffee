import SwiftUI

/// One shared selectable capsule button — the primary filter/section-switcher
/// affordance, used by `CoffeesListView.filterChip`, `InsightsView.equalPill`
/// and `InsightsView.chip` (#193 dedupe of that family; #181's `Pill` is a
/// different, non-interactive shape and stays separate, as does the filter
/// sheet's `FilterPill`, which adds a count-in-parens/average-rating/disabled
/// state on top of this one).
///
/// All three call sites share 13pt-semibold text, an accent fill when
/// selected vs a bordered unselected state, and a `minHitTarget`-ish height;
/// they differ in whether the pill stretches to fill its row, whether a
/// trailing count renders, and whether the unselected fill is a flat surface
/// color or `.thinMaterial`.
struct TogglePill: View {
    enum Width {
        /// Hugs its content — the dimension/year chips and the section pill.
        case natural
        /// `maxWidth: .infinity` — the three-way section control, which
        /// wants its pills to divide the row evenly.
        case stretch
    }

    /// The unselected fill. `CoffeesListView`'s chips float over the list
    /// content and read as an overlay, so they use frosted glass; Insights'
    /// pills sit on the flat tab surface and use a solid fill instead.
    enum UnselectedFill {
        case material
        case surface
    }

    let title: String
    var count: Int? = nil
    let isSelected: Bool
    var width: Width = .natural
    var unselectedFill: UnselectedFill = .surface
    var titleFont: Font = .system(size: 13, weight: Theme.Weight.semibold)
    var minHeight: CGFloat = Theme.minHitTarget
    var verticalPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.neutral900)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: Theme.Weight.semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.neutral700)
                }
            }
            .padding(.horizontal, count == nil ? 14 : 16)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: width == .stretch ? .infinity : nil, minHeight: minHeight)
            .background {
                if isSelected {
                    Capsule().fill(Theme.Colors.accent)
                } else if unselectedFill == .material {
                    Capsule().fill(.thinMaterial)
                } else {
                    Capsule().fill(Theme.Colors.surface)
                }
            }
            .overlay(
                Capsule().strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.neutral300, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
