import Foundation
import Security

/// App-wide configuration: the backend base URL (in UserDefaults) and the ingest
/// token (in the Keychain — never in the repo or binary).
///
/// Mirrors MyHealthOS's Store/AppConfig.swift.
@MainActor
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    // Filled in after the first Railway deploy. Override on the Connect screen.
    static let defaultBaseURL = "https://REPLACE_WITH_BACKEND_URL"

    private let baseURLKey = "backend_base_url"

    // Keychain generic-password coordinates.
    private let keychainService = "MyCoffee.backend"
    private let keychainAccount = "ingest_token"

    @Published private(set) var baseURL: String
    @Published private(set) var hasToken: Bool

    private init() {
        let stored = UserDefaults.standard.string(forKey: baseURLKey)
        self.baseURL = stored?.isEmpty == false ? stored! : Self.defaultBaseURL
        self.hasToken = false
        self.hasToken = (Self.readToken(service: keychainService, account: keychainAccount) != nil)
    }

    var isConnected: Bool { hasToken }

    var ingestToken: String? {
        Self.readToken(service: keychainService, account: keychainAccount)
    }

    func setBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        baseURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: baseURLKey)
    }

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Self.saveToken(trimmed, service: keychainService, account: keychainAccount)
        hasToken = true
    }

    func disconnect() {
        Self.deleteToken(service: keychainService, account: keychainAccount)
        hasToken = false
    }

    // MARK: - Keychain helpers

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func saveToken(_ token: String, service: String, account: String) {
        let data = Data(token.utf8)
        var query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readToken(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteToken(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}
