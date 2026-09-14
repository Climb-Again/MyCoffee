import SwiftUI

/// The app's root (Redesign **v3 §3**,
/// `design/coffees_redesign/UPDATE_BRIEF.md`): a **native** `TabView` with the
/// system's translucent glass tab bar. v2's mistake — hiding the tab bar and
/// building a custom three-slot `.safeAreaInset` bar with a 56pt floating `+`
/// circle — is reverted here. Content now blurs under the real bar and nothing
/// floats over a row or the detail page.
///
/// The `+` is a **third tab item** in the middle (`RootTab.add`): selecting it
/// immediately restores the previous tab (never stays selected — no overlay,
/// no shadow, no offset) and offers a `confirmationDialog` between the two
/// things it can start: the Add Coffee wizard (a bag going into the library)
/// or "Evaluate this coffee" (#125, a bag that isn't — nothing it produces is
/// saved). One entry point for both keeps the tab count at three (#87) rather
/// than giving the evaluate flow a fourth tab or a home buried in Settings.
///
/// `RootTab.review` (shell-owned, `Store/CoffeeStore.swift`) is left untouched —
/// nothing references it now that the Review tab is gone.
///
/// **#195 (Radu, 2026-09-12, verbatim):** *"add 2 new sections: Shop
/// (presenting the shortlist from the extension) and Recipes (the new speced
/// section with recipes, devices, grind size and asasociations with coffees).
/// order: Coffees, Recipes, +, Shop, Insights"*. Five items, `+` still the
/// centre bounce — comfortably under the 5-item limit at which iOS folds the
/// last tab into a "More" list, so the bar still shows all five.
///
/// Both new tabs surface things that already existed but had no home: Recipes
/// wraps `BrewCatalogueView` (#157), which until now was reachable only from
/// Settings; Shop reads the extension's shortlist, which the phone could not
/// see at all until #194 moved it server-side.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showAddChooser = false
    @State private var showAddCoffeeWizard = false
    /// #125: "Evaluate this coffee" needed a home and the tab structure is
    /// decided (#87) — no fourth tab. The `+` now offers a choice rather than
    /// jumping straight to the wizard, so the evaluate flow doesn't need its
    /// own entry point elsewhere (Settings, a toolbar item, …) for one row.
    @State private var showEvaluateCoffee = false

    var body: some View {
        TabView(selection: $store.selectedTab) {
            CoffeesListView()
                .tabItem {
                    // §11: Lucide outline glyphs, not SF fills.
                    Label("Coffees", image: Lucide.coffee)
                }
                .tag(RootTab.coffees)

            // #195(a): the Brew lab's catalogue as a first-class surface —
            // recipes, devices, grind clicks and temperatures with their
            // per-option win rates — rather than a row inside Settings. It
            // stays reachable from Settings too; discovering it there was the
            // problem, not the path.
            NavigationStack {
                BrewCatalogueView()
                    .navigationTitle("Recipes")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                // ⚠ SF Symbol, not Lucide (§11): there is no flask/storefront
                // imageset in Assets.xcassets and adding one means art, which
                // is Radu's call. Swap when the glyphs land — Symbols.swift
                // names these `tabRecipesFallback`/`tabShopFallback` so the
                // placeholder is impossible to mistake for a decision.
                Label("Recipes", systemImage: Symbols.tabRecipesFallback)
            }
            .tag(RootTab.recipes)

            // Middle `+` tab. Its content is never shown — the `onChange`
            // below bounces the selection back and opens the wizard sheet —
            // so a light placeholder is enough.
            Color.clear
                .tabItem {
                    Label("Add", image: Lucide.circlePlus)
                }
                .tag(RootTab.add)

            // #195(b): the extension's shortlist (#187 → #194).
            ShopTabView()
                .tabItem {
                    Label("Shop", systemImage: Symbols.tabShopFallback)
                }
                .tag(RootTab.shop)

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
            // Restore the tab the user was on, then offer the choice.
            store.selectedTab = oldValue == .add ? .coffees : oldValue
            showAddChooser = true
        }
        .confirmationDialog("Add", isPresented: $showAddChooser, titleVisibility: .hidden) {
            Button("Add a coffee I own") { showAddCoffeeWizard = true }
            Button("Evaluate a coffee") { showEvaluateCoffee = true }
            Button("Cancel", role: .cancel) {}
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
        .sheet(isPresented: $showEvaluateCoffee) {
            EvaluateCoffeeView()
                .environmentObject(store)
        }
    }
}
