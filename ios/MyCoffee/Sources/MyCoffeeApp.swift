import SwiftUI

@main
struct MyCoffeeApp: App {
    @StateObject private var config = AppConfig.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        if config.isConnected {
            ContentView()
        } else {
            ConnectView()
        }
    }
}
