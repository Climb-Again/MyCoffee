import SwiftUI

extension View {
    /// Clamps a full-bleed scrollable container (a `List` or `ScrollView`) to
    /// a comfortable reading width and centers it — #191: on iPhone `maxWidth`
    /// is never reached (portrait tops out around 430pt), so the two spacers
    /// stay at zero width and this is a no-op; on iPad landscape or a wide
    /// multitasking split, the content stops stretching into an unreadable
    /// full-bleed column. `background` paints edge-to-edge behind the clamped
    /// column so the surface color still reaches the screen's actual edges
    /// rather than stopping at the content's own width — pass `nil` for a
    /// view (like `CoffeesListView`'s `List`) that already paints its own
    /// background and only needs the width clamp.
    @ViewBuilder
    func readableWidth(maxWidth: CGFloat = 700, background: Color? = nil) -> some View {
        if let background {
            ZStack {
                background.ignoresSafeArea()
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    self.frame(maxWidth: maxWidth)
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                self.frame(maxWidth: maxWidth)
                Spacer(minLength: 0)
            }
        }
    }
}
