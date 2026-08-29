import SwiftUI

/// The app's root: two real tabs, Coffees and Insights (`#87`,
/// `design/coffees_redesign/README.md` §Tab bar). The Review tab is gone —
/// its count reaches the user through the listing's review nudge (`#86`,
/// `CoffeesListView.reviewNudge`) instead of a badge.
///
/// **Redesign v2 §A3** (`#94`, `design/coffees_redesign/UPDATE_BRIEF.md`):
/// round 1 floated the `+` as an `.overlay(alignment: .bottom)` on top of the
/// native tab bar, so it painted over list rows and the coffee-detail body
/// text alike. The system tab bar is now hidden outright
/// (`.toolbar(.hidden, for: .tabBar)`) and replaced with a real three-slot
/// `.safeAreaInset(edge: .bottom)` bar — Coffees · (+) · Insights — so both
/// `CoffeesListView` and `CoffeeDetailView` inset *above* it instead of
/// something floating on top of them. `.searchable`'s iOS-18 bottom-docking
/// (the old #58 rationale for the value-based `Tab(value:)` builder) no
/// longer applies now that `CoffeesListView` dropped `.searchable` for its
/// own plain search field (`#93`), so the plain `.tag()` form is enough here.
///
/// `RootTab.review` (shell-owned, `Store/CoffeeStore.swift`) is left
/// untouched — dropping the case would be a shared-surface change, and
/// nothing here still references it now that the Review tab is gone.
struct RootTabView: View {
    @StateObject private var store = CoffeeStore()
    @ObservedObject private var reviewCache = ReviewFeedCache.shared
    @State private var showAddCoffeeWizard = false

    var body: some View {
        TabView(selection: $store.selectedTab) {
            CoffeesListView()
                .tag(RootTab.coffees)

            InsightsView()
                .tag(RootTab.insights)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
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

    /// Coffees · (+) · Insights, per the handoff's three-slot bar. Not shown
    /// on the coffee-detail page — `CoffeeDetailView` pushes onto
    /// `CoffeesListView`'s own `NavigationStack`, which sits inside this
    /// `TabView`'s tab content, so the inset (and this bar) stays with the
    /// tab, not the pushed detail screen. Acceptance per `#94`: never
    /// overlaps a row or the detail page.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Coffees", systemImage: Symbols.tabCoffees, tab: .coffees)
            addCoffeeButton
                .padding(.horizontal, 24)
            tabButton(title: "Insights", systemImage: Symbols.tabInsights, tab: .insights)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.Colors.surface)
    }

    private func tabButton(title: String, systemImage: String, tab: RootTab) -> some View {
        let isSelected = store.selectedTab == tab
        return Button {
            store.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 10, weight: Theme.Weight.semibold))
            }
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.neutral700)
            .frame(maxWidth: .infinity, minHeight: Theme.minHitTarget)
        }
        .buttonStyle(.plain)
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
