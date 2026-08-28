import SwiftUI

/// The app's root: two real tabs, Coffees and Insights (`#87`,
/// `design/coffees_redesign/README.md` §Tab bar). The Review tab is gone —
/// its count reaches the user through the listing's review nudge (`#86`,
/// `CoffeesListView.reviewNudge`) instead of a badge. A floating centre
/// button sits on the boundary between the two tabs, visually completing the
/// handoff's "Coffees · + · Insights" three-slot bar without the flicker a
/// real third `Tab` that intercepts selection would cause: with exactly two
/// tabs the native bar already splits evenly in half, so a button centred at
/// the bottom edge lands exactly on the seam between them.
///
/// **#58**: on iOS 26, the value-based `Tab(_:systemImage:value:)` builder
/// (iOS 18+) is what lets the system dock a tab's `.searchable` field near
/// the bottom tab bar instead of the top nav bar — the legacy
/// `.tabItem`/`.tag()` pair never gets that treatment. Deployment target is
/// iOS 17, so the modern builder is gated behind `#available` with the
/// original `.tabItem` form kept as the iOS 17 fallback; `CoffeesListView`'s
/// own `.searchable` call is untouched either way (PLAN.md §13/#58 — "keep
/// the same binding + prompt, placement only").
///
/// `RootTab.review` (shell-owned, `Store/CoffeeStore.swift`) is left
/// untouched — dropping the case would be a shared-surface change, and
/// nothing here still references it now that the Review tab is gone.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showAddCoffeeWizard = false

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
                }
                .tint(Theme.Colors.accent)
            } else {
                TabView(selection: $store.selectedTab) {
                    CoffeesListView()
                        .tabItem { Label("Coffees", systemImage: Symbols.tabCoffees) }
                        .tag(RootTab.coffees)

                    InsightsView()
                        .tabItem { Label("Insights", systemImage: Symbols.tabInsights) }
                        .tag(RootTab.insights)
                }
                .tint(Theme.Colors.accent)
            }
        }
        .overlay(alignment: .bottom) {
            addCoffeeButton
                .padding(.bottom, 76)
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

    /// Design handoff §Tab bar: 56pt `#0078ff` circle, white 24pt plus, `md` shadow.
    private var addCoffeeButton: some View {
        Button {
            showAddCoffeeWizard = true
        } label: {
            Image(systemName: Symbols.wizardAdd)
                .font(.system(size: 24, weight: Theme.Weight.semibold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.accent, in: Circle())
                .themeShadow(Theme.Shadow.md)
        }
        .accessibilityLabel("Add coffee")
    }
}
