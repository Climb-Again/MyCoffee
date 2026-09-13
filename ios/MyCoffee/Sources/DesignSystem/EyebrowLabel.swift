import SwiftUI

/// The 10pt semibold neutral-700 section/fact label — #181 dedupe of the
/// same three lines (`.font(.system(size: 10, weight: Theme.Weight.semibold))`,
/// `.tracking(_)`, `.foregroundStyle(Theme.Colors.neutral700)`) hand-rolled
/// across `CoffeeDetailView`, `RoasterPageView` and `CoffeesListView`.
/// `tracking` is required rather than defaulted: the app uses three
/// different values (0.6 for a short fact caption, 1.2 for a section
/// header, 1.4 for a month header) and a silent default would make it easy
/// to pick the wrong one without noticing. A caller relying on `.textCase`
/// to uppercase mixed-case source text can still chain it on afterward —
/// `textCase` is an environment modifier and reaches the `Text` inside.
struct EyebrowLabel: View {
    let text: String
    let tracking: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: Theme.Weight.semibold))
            .tracking(tracking)
            .foregroundStyle(Theme.Colors.neutral700)
    }
}
