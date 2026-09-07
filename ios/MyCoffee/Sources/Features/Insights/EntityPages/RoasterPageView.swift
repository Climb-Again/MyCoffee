import SwiftUI

/// A roaster's entity page (PLAN.md §6.3, pushback #7: the roaster **name**
/// row leads here). Pushback #11 flags that a roaster page wants a logo and
/// a blurb that don't exist in the data yet — `Roaster` (shell-owned,
/// `Models/Vocab.swift`) has no `blurb` field today, so that section is
/// simply omitted rather than shipping an empty box; a monogram avatar
/// stands in for the missing logo.
struct RoasterPageView: View {
    let roasterID: Int
    @EnvironmentObject private var store: CoffeeStore

    private var vocabulary: Vocabulary { store.index.vocabulary }
    private var roaster: Roaster? { vocabulary.roasters[roasterID] }
    private var country: Country? { roaster?.countryId.flatMap { vocabulary.countries[$0] } }

    private var coffees: [Coffee] {
        var filter = CoffeeFilter()
        filter.roasterIDs = [roasterID]
        return store.index.coffees(matching: filter, sortedBy: .rating)
    }

    private var averageRating: Double? {
        let ratings = coffees.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    roasterLogo
                    VStack(alignment: .leading, spacing: 4) {
                        Text(roaster?.name ?? "Unknown roaster")
                            .font(.title3.weight(.bold))
                        if let country {
                            HStack(spacing: 4) {
                                FlagView(isoCode: country.isoCode)
                                Text(country.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("\(coffees.count) coffee\(coffees.count == 1 ? "" : "s")")
                    if let averageRating {
                        Spacer()
                        Label(String(format: "%.2f", averageRating), systemImage: Symbols.starFill)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
            }
            .listRowSeparator(.hidden)

            // #134: the roaster blurb, shown only when there is one (an empty
            // box is worse than nothing — the original omitted this section).
            if let blurb = roaster?.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty {
                Section {
                    Text(blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowSeparator(.hidden)
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

    /// #134: the roaster's logo, fetched **web-only** (`AsyncImage`, not the
    /// 30 MB `ImageStore` cache — Radu, 2026-09-07 "do not cache logos"). Falls
    /// back to the `MonogramAvatar` while loading, on failure, or when the
    /// roaster has no `logoUrl`.
    @ViewBuilder private var roasterLogo: some View {
        let fallback = MonogramAvatar(name: roaster?.name ?? "?")
        if let urlString = roaster?.logoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    fallback
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            fallback
        }
    }
}
