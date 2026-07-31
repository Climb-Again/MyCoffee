import SwiftUI

/// One of the detail page's "what else is good" rails (PLAN.md §6.3):
/// ordered by rating desc, not date, and omitted entirely below 2 items.
struct CoffeeRail: Identifiable {
    let id: String
    let title: String
    let coffees: [Coffee]
    let moreFilter: CoffeeFilter
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
                    RailMoreView(title: rail.title, filter: rail.moreFilter)
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

/// A rail's "More" destination — a bare filtered list until roaster/country
/// entity pages (#28) exist (PLAN.md §6.3, `FeatureFlags.railMoreGoesToEntityPage`).
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
