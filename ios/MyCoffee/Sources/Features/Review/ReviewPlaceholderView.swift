import SwiftUI

/// Placeholder — the real Review queue (batch cards, photo auto-zoom,
/// mapping rules) is backlog #27, blocked on the sync engine (#22) and the
/// adjudication backend (#24). This just reserves the tab and shows the
/// count that will drive its badge once real data exists.
struct ReviewPlaceholderView: View {
    @EnvironmentObject private var store: CoffeeStore

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Review queue coming soon",
                systemImage: Symbols.tabReview,
                description: Text("\(pendingCount) coffee(s) will need a look once the review backend lands.")
            )
            .navigationTitle("Review")
        }
    }

    private var pendingCount: Int {
        store.index.coffees.filter(\.hasOpenReview).count
    }
}
