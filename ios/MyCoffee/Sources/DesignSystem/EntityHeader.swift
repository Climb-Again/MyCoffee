import SwiftUI

/// The identity + stats block at the top of an entity page (roaster or
/// country) — two `List` rows (icon/title/subtitle, then coffee count +
/// average rating), duplicated between `RoasterPageView` and
/// `CountryPageView` until #181, **and inconsistent**: the star was
/// `Theme.Colors.accent` on the roaster page but `.orange` on the country
/// page. Accent wins (#148). `Group` rather than a `VStack` so this still
/// expands into two independent `List` rows when placed inside a `Section`,
/// matching what both pages had before.
struct EntityHeader<Icon: View, Subtitle: View>: View {
    @ViewBuilder let icon: () -> Icon
    let title: String
    @ViewBuilder let subtitle: () -> Subtitle
    let coffeeCount: Int
    let averageRating: Double?

    var body: some View {
        Group {
            HStack(spacing: 16) {
                icon()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    subtitle()
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("\(coffeeCount) coffee\(coffeeCount == 1 ? "" : "s")")
                if let averageRating {
                    Spacer()
                    Label(String(format: "%.2f", averageRating), systemImage: Symbols.starFill)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .font(.subheadline)
        }
    }
}
