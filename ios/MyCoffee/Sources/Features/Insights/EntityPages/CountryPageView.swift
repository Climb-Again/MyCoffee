import SwiftUI

/// Which relationship a country page is browsing (PLAN.md pushback #7): the
/// roaster flag on a coffee leads to that roaster's *country*, while the
/// origin flag leads to the *origin* country — two distinct filtered views
/// over the same `Country`, not the same page reused.
enum CountryPageRole {
    case origin
    case roaster
}

struct CountryPageView: View {
    let countryID: Int
    let role: CountryPageRole
    @EnvironmentObject private var store: CoffeeStore

    private var vocabulary: Vocabulary { store.index.vocabulary }
    private var country: Country? { vocabulary.countries[countryID] }

    private var coffees: [Coffee] {
        var filter = CoffeeFilter()
        switch role {
        case .origin: filter.originCountryIDs = [countryID]
        case .roaster: filter.roasterCountryIDs = [countryID]
        }
        return store.index.coffees(matching: filter, sortedBy: .rating)
    }

    private var averageRating: Double? {
        let ratings = coffees.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    private var navigationTitleText: String {
        let name = country?.name ?? "Unknown"
        return role == .origin ? name : "Roasters in \(name)"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    FlagView(isoCode: country?.isoCode)
                        .font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(country?.name ?? "Unknown country")
                            .font(.title3.weight(.bold))
                        Text(role == .origin ? "Origin country" : "Roaster country")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                    NavigationLink(value: coffee.id) {
                        CoffeeRowView(coffee: coffee, vocabulary: vocabulary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}
