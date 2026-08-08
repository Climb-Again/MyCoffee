import SwiftUI

/// The app's root: three tabs — Coffees / Insights / Review (PLAN.md §6).
/// Search lives on the Coffees tab via `.searchable`, not as a tab of its
/// own. The Review tab is always present with a `.badge(pendingCount)` —
/// never conditionally inserted, which would reindex the bar.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared

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
        .task {
            await reviewCache.ensureLoaded()
        }
    }

    /// Counts only coffees with a client-reviewable open item (PLAN.md §11
    /// #37) — same real-feed gate as the coffee-page Review button, so the
    /// badge never promises more than the tab actually shows.
    private var pendingReviewCount: Int {
        store.index.coffees.filter { $0.hasOpenReview && reviewCache.hasReviewableTasks(for: $0.id) }.count
    }
}
