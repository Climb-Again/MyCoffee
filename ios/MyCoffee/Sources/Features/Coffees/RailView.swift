import SwiftUI

/// One of the detail page's "what else is good" rails (PLAN.md §6.3):
/// ordered by rating desc, not date, and omitted entirely below 2 items.
struct CoffeeRail: Identifiable {
    /// Where "More" goes once `FeatureFlags.railMoreGoesToEntityPage` is on
    /// (PLAN.md §6.3: the roaster/origin rails go to the entity page rather
    /// than a bare filtered list, which would duplicate the page and orphan
    /// its blurb/stats; the profile rail has no entity page, so it always
    /// stays a filtered list).
    enum MoreDestination {
        case roaster(id: Int)
        case country(id: Int, role: CountryPageRole)
        case filteredList
    }

    let id: String
    let title: String
    let coffees: [Coffee]
    let moreFilter: CoffeeFilter
    let moreDestination: MoreDestination
}

struct RailView: View {
    let rail: CoffeeRail
    let vocabulary: Vocabulary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rail.title)
                    .font(.headline)
                Spacer()
                // Destination-style NavigationLink rather than value-based:
                // avoids requiring `CoffeeFilter` (shell-owned, not
                // `Hashable`) to gain a manual conformance just for this.
                NavigationLink {
                    moreDestination
                } label: {
                    Text("More")
                        .font(.subheadline)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rail.coffees.prefix(10)) { coffee in
                        NavigationLink(value: coffee.id) {
                            RailCard(coffee: coffee, vocabulary: vocabulary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var moreDestination: some View {
        if FeatureFlags.railMoreGoesToEntityPage {
            switch rail.moreDestination {
            case let .roaster(id):
                RoasterPageView(roasterID: id)
            case let .country(id, role):
                CountryPageView(countryID: id, role: role)
            case .filteredList:
                RailMoreView(title: rail.title, filter: rail.moreFilter)
            }
        } else {
            RailMoreView(title: rail.title, filter: rail.moreFilter)
        }
    }
}

private struct RailCard: View {
    let coffee: Coffee
    let vocabulary: Vocabulary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumbnail(urlString: coffee.images?.thumb, size: 96, cornerRadius: 10)
            Text(coffee.displayTitle(vocabulary: vocabulary))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(width: 96, alignment: .leading)
            if let rating = coffee.rating {
                Label(String(format: "%.1f", rating), systemImage: Symbols.starFill)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 96, alignment: .leading)
        .foregroundStyle(.primary)
    }
}

/// A rail's "More" destination when there's no entity page to go to instead
/// (the profile rail, or `FeatureFlags.railMoreGoesToEntityPage` reverted —
/// PLAN.md §6.3).
struct RailMoreView: View {
    let title: String
    let filter: CoffeeFilter
    @EnvironmentObject private var store: CoffeeStore

    var body: some View {
        List {
            ForEach(coffees) { coffee in
                NavigationLink(value: coffee.id) {
                    CoffeeRowView(coffee: coffee, vocabulary: store.index.vocabulary, sort: .rating)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var coffees: [Coffee] {
        store.index.coffees(matching: filter, sortedBy: .rating)
    }
}
