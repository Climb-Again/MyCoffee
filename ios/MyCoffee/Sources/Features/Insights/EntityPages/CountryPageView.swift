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

    private var averageRating: Double? { coffees.averageRating }

    private var navigationTitleText: String {
        let name = country?.name ?? "Unknown"
        return role == .origin ? name : "Roasters in \(name)"
    }

    var body: some View {
        List {
            Section {
                EntityHeader(
                    icon: { FlagView(isoCode: country?.isoCode).font(.system(size: 40)) },
                    title: country?.name ?? "Unknown country",
                    subtitle: {
                        Text(role == .origin ? "Origin country" : "Roaster country")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    },
                    coffeeCount: coffees.count,
                    averageRating: averageRating
                )
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
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}
