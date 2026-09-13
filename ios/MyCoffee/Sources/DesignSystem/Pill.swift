import SwiftUI

/// A plain, non-interactive label capsule — text (+ optional leading icon)
/// on a flat fill, no border, no selection state. #181 dedupe of
/// `CoffeeDetailView`'s `DetailPill`/`InfoPill` and its flavour-note chip,
/// which were three near-identical capsules differing only in font/color.
/// (The filter sheet's `FilterPill` and the toggle-style pills in
/// `InsightsView`/`CoffeesListView` are a different shape — count badges and
/// selection state — and stay separate.)
struct Pill: View {
    let text: String
    var icon: String?
    var font: Font = .system(size: 11, weight: .medium)
    var foreground: Color = Theme.Colors.text
    var background: Color = Theme.Colors.neutral100
    /// `DetailPill`'s original behaviour: single-line, never truncated by a
    /// squeezed `WrapLayout` row. `false` for pills that already sit in a
    /// layout with room to breathe (the flavour chips, the blend marker).
    var fixedWidth: Bool = true

    var body: some View {
        let content = HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(font)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: Capsule())

        if fixedWidth {
            content.fixedSize(horizontal: true, vertical: false)
        } else {
            content
        }
    }
}
