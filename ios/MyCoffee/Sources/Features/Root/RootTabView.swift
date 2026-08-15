import SwiftUI

/// The app's root: three tabs — Coffees / Insights / Review (PLAN.md §6).
/// Search lives on the Coffees tab via `.searchable`, not as a tab of its
/// own. The Review tab is always present with a `.badge(pendingCount)` —
/// never conditionally inserted, which would reindex the bar.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared

    var body: some View {
        TabView(selection: $store.selectedTab) {
            CoffeesListView()
                .tabItem { Label("Coffees", systemImage: Symbols.tabCoffees) }
                .tag(RootTab.coffees)

            InsightsView()
                .tabItem { Label("Insights", systemImage: Symbols.tabInsights) }
                .tag(RootTab.insights)

            ReviewQueueView()
                .tabItem { Label("Review", systemImage: Symbols.tabReview) }
                .badge(store.reviewQueueCount)
                .tag(RootTab.review)
        }
        .environmentObject(store)
        .task {
            if store.index.coffees.isEmpty {
                await store.load()
            }
            // Badge follows the actual review queue, not the count of non-clean
            // coffees (which includes fields the app can't review).
            await store.refreshReviewCount()
        }
        .task {
            await reviewCache.ensureLoaded()
        }
    }
}
