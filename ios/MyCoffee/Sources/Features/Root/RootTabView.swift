import SwiftUI

/// The app's root: three tabs — Coffees / Insights / Review (PLAN.md §6).
/// Search lives on the Coffees tab via `.searchable`, not as a tab of its
/// own. The Review tab is always present with a `.badge(pendingCount)` —
/// never conditionally inserted, which would reindex the bar.
///
/// **#58**: on iOS 26, the value-based `Tab(_:systemImage:value:)` builder
/// (iOS 18+) is what lets the system dock a tab's `.searchable` field near
/// the bottom tab bar instead of the top nav bar — the legacy
/// `.tabItem`/`.tag()` pair never gets that treatment. Deployment target is
/// iOS 17, so the modern builder is gated behind `#available` with the
/// original `.tabItem` form kept as the iOS 17 fallback; `CoffeesListView`'s
/// own `.searchable` call is untouched either way (PLAN.md §13/#58 — "keep
/// the same binding + prompt, placement only").
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $store.selectedTab) {
                    Tab("Coffees", systemImage: Symbols.tabCoffees, value: RootTab.coffees) {
                        CoffeesListView()
                    }
                    Tab("Insights", systemImage: Symbols.tabInsights, value: RootTab.insights) {
                        InsightsView()
                    }
                    Tab("Review", systemImage: Symbols.tabReview, value: RootTab.review) {
                        ReviewQueueView()
                    }
                    .badge(store.reviewQueueCount)
                }
            } else {
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
            }
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
