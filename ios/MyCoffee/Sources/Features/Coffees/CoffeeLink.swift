import SwiftUI

/// A tap target that opens a coffee's detail page, and **works from any
/// navigation stack** (`#102`).
///
/// # Why this exists
///
/// Every coffee row used to be a value-based `NavigationLink(value: coffee.id)`
/// resolved by a single `navigationDestination(for: String.self)` declared once,
/// on `CoffeesListView`. That worked on the main listing and nowhere else:
///
/// - `CountryPageView`, `RoasterPageView` and `RailMoreView` are pushed with
///   **closure-based** links, and mixing the two styles in one `NavigationStack`
///   leaves the value-based links inside the pushed view unable to resolve the
///   stack's destination — the tap did nothing at all.
/// - `InsightsView` has its **own** `NavigationStack` and never registered a
///   `String` destination, so a coffee opened from that tab was inert for a
///   second, unrelated reason.
///
/// Making the link carry its own destination removes both failure modes and the
/// need for the registration. It also drops `String` as a navigation key, which
/// was fragile on its own: any other `String` value pushed anywhere in the app
/// would have collided with the coffee destination.
///
/// # Styling
///
/// Deliberately applies **no** `buttonStyle`, because the right one differs by
/// context: inside a `List` the default style draws the row disclosure chevron
/// the listing relies on, while the horizontal rail cards want `.plain`. Call
/// sites add `.buttonStyle(.plain)` when they need it.
///
/// Constructing the destination eagerly is safe here: `CoffeeDetailView.init`
/// only stores the passed `Coffee`, and SwiftUI does not evaluate its `body`
/// until the link is actually followed.
struct CoffeeLink<Label: View>: View {
    private let coffee: Coffee
    private let label: Label

    init(coffee: Coffee, @ViewBuilder label: () -> Label) {
        self.coffee = coffee
        self.label = label()
    }

    var body: some View {
        NavigationLink {
            CoffeeDetailView(coffee: coffee)
        } label: {
            label
        }
    }
}
