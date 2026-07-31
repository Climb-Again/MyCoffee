import SwiftUI

/// The connected app's root. Hosts the real three-tab UI (`Features/Root`);
/// this file itself stays a thin pass-through so it's a one-line change for
/// whichever lane needs to touch it next (see `status/ios-ux.md`).
struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}
