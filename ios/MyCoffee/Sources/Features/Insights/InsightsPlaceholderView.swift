import SwiftUI

/// Placeholder — the real Insights page (statistical gates, Swift Charts,
/// roaster/country pages) is backlog #28, blocked on the sync engine (#22)
/// and the review-adjudication backend (#24). This just reserves the tab.
struct InsightsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Insights coming soon",
                systemImage: Symbols.tabInsights,
                description: Text("Statistical breakdowns land once enough coffees are synced and reviewed.")
            )
            .navigationTitle("Insights")
        }
    }
}
