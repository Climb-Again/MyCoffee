import SwiftUI

/// Placeholder home screen. Confirms connectivity; grow into the real MyCoffee
/// UI once the product brief lands.
struct ContentView: View {
    @EnvironmentObject private var config: AppConfig

    @State private var statusText = "Checking…"
    @State private var isHealthy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.brown)

                Text("MyCoffee")
                    .font(.largeTitle.bold())

                HStack(spacing: 6) {
                    Circle()
                        .fill(isHealthy ? .green : .orange)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(config.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect", role: .destructive) { config.disconnect() }
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            let client = try APIClient(config: config)
            let status = try await client.status()
            isHealthy = status.db
            statusText = status.db ? "Connected · DB healthy" : "Connected · DB unavailable"
        } catch {
            isHealthy = false
            statusText = "Offline"
        }
    }
}
