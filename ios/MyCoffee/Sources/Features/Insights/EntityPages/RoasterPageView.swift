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
                    MonogramAvatar(name: roaster?.name ?? "?")
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
}
