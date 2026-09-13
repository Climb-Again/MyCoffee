import SwiftUI

extension View {
    /// The zero-inset, no-separator, transparent-background row treatment
    /// used throughout `CoffeesListView` for content that draws its own
    /// full-bleed background (§5 §12) — #181 dedupe of the same three
    /// chained modifiers repeated five times in that file.
    func plainListRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
