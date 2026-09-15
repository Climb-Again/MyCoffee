import SwiftUI

/// A roaster's entity page (PLAN.md §6.3, pushback #7: the roaster **name**
/// row leads here). Logo + blurb treatment reworked per `HEADER_UPDATE.md`
/// §8: the same rounded-square logo tile as the coffee-detail header
/// (`#142`/`#148`, never a circle, never a monogram fallback — no logo
/// means no tile), markdown stripped out of the blurb, and the rating in
/// accent blue rather than orange.
struct RoasterPageView: View {
    let roasterID: Int
    @EnvironmentObject private var store: CoffeeStore
    @State private var introExpanded = false

    private var vocabulary: Vocabulary { store.index.vocabulary }
    private var roaster: Roaster? { vocabulary.roasters[roasterID] }
    private var country: Country? { roaster?.countryId.flatMap { vocabulary.countries[$0] } }

    private var coffees: [Coffee] {
        var filter = CoffeeFilter()
        filter.roasterIDs = [roasterID]
        return store.index.coffees(matching: filter, sortedBy: .rating)
    }

    private var averageRating: Double? { coffees.averageRating }

    private var parsedBlurb: RoasterBlurbParser.Parsed? {
        guard let blurb = roaster?.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty else {
            return nil
        }
        return RoasterBlurbParser.parse(blurb)
    }

    /// #153(a) — detection half of "notify me in the app to upload text +
    /// logo for any roaster that has none." The editor half (submitting an
    /// edit) needs a shell-owned API surface that doesn't exist yet, so this
    /// session ships the passive nudge only — the row's own recommended
    /// first cut.
    private var missingContentDescription: String? {
        let noBlurb = parsedBlurb == nil
        let noLogo = roaster?.logoUrl == nil
        switch (noBlurb, noLogo) {
        case (true, true): return "a logo and a blurb"
        case (true, false): return "a blurb"
        case (false, true): return "a logo"
        case (false, false): return nil
        }
    }

    var body: some View {
        List {
            Section {
                EntityHeader(
                    icon: { RoasterLogoTile(logoUrl: roaster?.logoUrl, size: 86, cornerRadius: 22) },
                    title: roaster?.name ?? "Unknown roaster",
                    subtitle: {
                        if let country {
                            HStack(spacing: 4) {
                                FlagView(isoCode: country.isoCode)
                                Text(country.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    },
                    coffeeCount: coffees.count,
                    averageRating: averageRating
                )
            }
            .listRowSeparator(.hidden)

            if let missingContentDescription {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: Symbols.roasterMissingContent)
                            .foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This page is missing \(missingContentDescription)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Flagged for Radu — an in-app editor is on the way.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .listRowSeparator(.hidden)
            }

            // #134/#148: the roaster blurb, markdown stripped, shown only
            // when there is one (an empty box is worse than nothing).
            if let parsedBlurb {
                Section {
                    if !parsedBlurb.intro.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(parsedBlurb.intro)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(introExpanded ? nil : 3)
                                .fixedSize(horizontal: false, vertical: true)
                            if !introExpanded {
                                Button("Read more") { introExpanded = true }
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    ForEach(parsedBlurb.bullets) { bullet in
                        blurbBulletRow(bullet)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            Section {
                ForEach(coffees) { coffee in
                    CoffeeLink(coffee: coffee) {
                        CoffeeRowView(coffee: coffee, vocabulary: vocabulary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle(roaster?.name ?? "Roaster")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// §5's label/value pattern, one row per bullet — a labelled bullet
    /// (`- **Label** — text`) becomes a caption+value pair; a plain bullet
    /// stays a plain line.
    @ViewBuilder
    private func blurbBulletRow(_ bullet: RoasterBlurbBullet) -> some View {
        if let label = bullet.label {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel(text: label.uppercased(), tracking: 0.6)
                Text(bullet.text)
                    .font(.system(size: 13, weight: Theme.Weight.semibold))
                    .foregroundStyle(Theme.Colors.text)
            }
        } else {
            Text(bullet.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
