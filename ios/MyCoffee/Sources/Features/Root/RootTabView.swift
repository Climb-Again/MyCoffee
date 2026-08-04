import SwiftUI

/// The app's root: three tabs — Coffees / Insights / Review (PLAN.md §6).
/// Search lives on the Coffees tab via `.searchable`, not as a tab of its
/// own. The Review tab is always present with a `.badge(pendingCount)` —
/// never conditionally inserted, which would reindex the bar.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()

    var body: some View {
        TabView {
            CoffeesListView()
                .tabItem { Label("Coffees", systemImage: Symbols.tabCoffees) }

            InsightsView()
                .tabItem { Label("Insights", systemImage: Symbols.tabInsights) }

            ReviewQueueView()
                .tabItem { Label("Review", systemImage: Symbols.tabReview) }
                .badge(pendingReviewCount)
        }
        .environmentObject(store)
        .task {
            if store.index.coffees.isEmpty {
                await store.load()
            }
        }
    }

    private var pendingReviewCount: Int {
        store.index.coffees.filter(\.hasOpenReview).count
    }
}
