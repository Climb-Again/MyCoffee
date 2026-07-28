import Foundation

/// Thin async HTTP client for the MyCoffee backend.
/// Every request carries `Authorization: Bearer <ingestToken>`.
/// Mirrors MyHealthOS's API/APIClient.swift.
struct APIClient {
    enum APIError: Error, LocalizedError {
        case notConfigured
        case badURL
        case http(status: Int, body: String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Backend URL or token not set."
            case .badURL: return "Invalid backend URL."
            case let .http(status, body): return "HTTP \(status): \(body)"
            case let .decoding(err): return "Decoding failed: \(err.localizedDescription)"
            }
        }
    }

    let baseURL: String
    let token: String

    @MainActor
    init(config: AppConfig) throws {
        guard let token = config.ingestToken, !token.isEmpty else {
            throw APIError.notConfigured
        }
        self.baseURL = config.baseURL
        self.token = token
    }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // GET /api/status — quick connectivity check.
    func status() async throws -> StatusResponse {
        let req = try makeRequest(path: "/api/status", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder().decode(StatusResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // POST /api/ingest — send an event to the backend.
    @discardableResult
    func ingest(type: String, payload: [String: Any]) async throws -> Bool {
        let envelope: [String: Any] = [
            "type": type,
            "payload": payload,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let body = try JSONSerialization.data(withJSONObject: envelope)
        let req = try makeRequest(path: "/api/ingest", method: "POST", body: body)
        _ = try await send(req)
        return true
    }
}

struct StatusResponse: Codable {
    let ok: Bool
    let service: String
    let db: Bool
}
