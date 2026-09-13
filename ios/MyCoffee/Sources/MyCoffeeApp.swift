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
        Group {
            if config.isConnected {
                ContentView()
            } else {
                ConnectView()
            }
        }
        // Keep the on-device image cache under its 30 MB ceiling (CLAUDE.md's
        // 50 MB app+data rule) — a cheap directory scan on each launch. No
        // BGTask is registered (#175(e): removed rather than built), so this
        // launch-time sweep is the only place eviction runs.
        .task {
            await ImageStore.shared.evictStaleEntries()
        }
    }
}
