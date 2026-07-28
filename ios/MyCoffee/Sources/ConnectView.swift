import SwiftUI

/// First-run Connect screen: enter the backend URL + ingest token.
/// The token is stored in the Keychain via AppConfig; the URL in UserDefaults.
struct ConnectView: View {
    @EnvironmentObject private var config: AppConfig

    @State private var urlText: String = ""
    @State private var tokenText: String = ""
    @State private var testing = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("https://…up.railway.app", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Ingest token", text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(messageIsError ? .red : .green)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: connect) {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 4) }
                            Text("Connect")
                        }
                    }
                    .disabled(testing || urlText.isEmpty || tokenText.isEmpty)
                }
            }
            .navigationTitle("Connect MyCoffee")
            .onAppear { if urlText.isEmpty { urlText = config.baseURL } }
        }
    }

    private func connect() {
        testing = true
        message = nil
        config.setBaseURL(urlText)
        config.setToken(tokenText)

        Task {
            defer { testing = false }
            do {
                let client = try APIClient(config: config)
                let status = try await client.status()
                if status.ok {
                    message = "Connected to \(status.service)."
                    messageIsError = false
                    // isConnected flips via hasToken; RootView swaps automatically.
                }
            } catch {
                // Roll back the token so the app doesn't get stuck "connected".
                config.disconnect()
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }
}
