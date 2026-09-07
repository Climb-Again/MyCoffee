import SwiftUI

/// The app's root (Redesign **v3 §3**,
/// `design/coffees_redesign/UPDATE_BRIEF.md`): a **native** `TabView` with the
/// system's translucent glass tab bar. v2's mistake — hiding the tab bar and
/// building a custom three-slot `.safeAreaInset` bar with a 56pt floating `+`
/// circle — is reverted here. Content now blurs under the real bar and nothing
/// floats over a row or the detail page.
///
/// The `+` is a **third tab item** in the middle (`RootTab.add`): selecting it
/// presents the Add Coffee wizard as a sheet and immediately restores the
/// previous tab, so it never stays selected. No overlay, no shadow, no offset.
///
/// `RootTab.review` (shell-owned, `Store/CoffeeStore.swift`) is left untouched —
/// nothing references it now that the Review tab is gone.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showAddCoffeeWizard = false

    var body: some View {
        TabView(selection: $store.selectedTab) {
            CoffeesListView()
                .tabItem {
                    // §11: Lucide outline glyphs, not SF fills.
                    Label("Coffees", image: Lucide.coffee)
                }
                .tag(RootTab.coffees)

            // Middle `+` tab. Its content is never shown — the `onChange`
            // below bounces the selection back and opens the wizard sheet —
            // so a light placeholder is enough.
            Color.clear
                .tabItem {
                    Label("Add", image: Lucide.circlePlus)
                }
                .tag(RootTab.add)

            InsightsView()
                .tabItem {
                    Label("Insights", image: Lucide.barChart3)
                }
                .tag(RootTab.insights)
        }
        // §3/§12: never hide the bar, never paint it — the system glass is the
        // point. `.tint` makes the selected item and the `+` render `#0078ff`.
        .tint(Theme.Colors.accent)
        .onChange(of: store.selectedTab) { oldValue, newValue in
            guard newValue == .add else { return }
            // Restore the tab the user was on, then present the wizard.
            store.selectedTab = oldValue == .add ? .coffees : oldValue
            showAddCoffeeWizard = true
        }
        .environmentObject(store)
        .task {
            if store.index.coffees.isEmpty {
                await store.load()
            }
            // Nudge follows the actual review queue, not the count of non-clean
            // coffees (which includes fields the app can't review).
            await store.refreshReviewCount()
        }
        .task {
            await reviewCache.ensureLoaded()
        }
        .sheet(isPresented: $showAddCoffeeWizard) {
            AddCoffeeWizardView()
                .environmentObject(store)
        }
    }
}
