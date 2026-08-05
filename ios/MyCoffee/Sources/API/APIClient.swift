import Foundation

/// Thin async HTTP client for the MyCoffee backend.
/// Every request carries `Authorization: Bearer <ingestToken>`.
/// Mirrors MyHealthOS's API/APIClient.swift.
struct APIClient: Sendable {
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

    // GET /api/snapshot — full delta-syncable dataset (PLAN.md §4). `since`
    // filters to rows updated after that instant server-side; omit it for a
    // full resync.
    func snapshot(since: Date?) async throws -> SnapshotResponseDTO {
        var path = "/api/snapshot"
        if let since {
            let raw = ISO8601DateFormatter.coffeeAPI.string(from: since)
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            path += "?since=\(encoded)"
        }
        let req = try makeRequest(path: path, method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(SnapshotResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // GET /api/snapshot/text — folded search blobs, keyed by coffee public id.
    func snapshotText() async throws -> [String: String] {
        let req = try makeRequest(path: "/api/snapshot/text", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(SnapshotTextResponseDTO.self, from: data).texts
        } catch {
            throw APIError.decoding(error)
        }
    }

    // GET /api/coffees/:publicId — detail + notes + signed thumb/display URLs.
    func coffeeDetail(publicId: String) async throws -> CoffeeDetailDTO {
        let req = try makeRequest(path: "/api/coffees/\(publicId)", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(CoffeeDetailDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // POST /api/coffees/:publicId/favorite
    @discardableResult
    func setFavorite(publicId: String, favorite: Bool) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["favorite": favorite])
        let req = try makeRequest(path: "/api/coffees/\(publicId)/favorite", method: "POST", body: body)
        _ = try await send(req)
        return true
    }

    // GET /api/review — the open review queue (backend maps DB fields onto the
    // app's `ReviewField` and cleans candidates; PLAN.md §6.5).
    func reviewFeed(limit: Int = 200) async throws -> ReviewFeedDTO {
        let req = try makeRequest(path: "/api/review?limit=\(limit)", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(ReviewFeedDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // POST /api/review/:id — accept a value. The backend canonicalises the raw
    // string into the field's stored shape and writes a locked, human-decided
    // resolution; a value it can't resolve (e.g. an unknown roaster) comes back
    // as HTTP 422 and the item stays open (never a corrupt write).
    @discardableResult
    func resolveReview(id: String, value: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["value": value])
        let req = try makeRequest(path: "/api/review/\(id)", method: "POST", body: body)
        _ = try await send(req)
        return true
    }

    // POST /api/review/:id — dismiss ("not on the bag"), no resolution written.
    @discardableResult
    func dismissReview(id: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["dismiss": true])
        let req = try makeRequest(path: "/api/review/\(id)", method: "POST", body: body)
        _ = try await send(req)
        return true
    }
}

struct StatusResponse: Codable {
    let ok: Bool
    let service: String
    let db: Bool
}
