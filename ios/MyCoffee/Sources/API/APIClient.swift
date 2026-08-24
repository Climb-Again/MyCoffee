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

    // POST /api/coffees/:id/rotation — persisted display rotation (#57/#73).
    // `quarterTurns` is the absolute clockwise correction (0–3); the backend
    // rejects anything else with 400, which `send` surfaces as an APIError.
    @discardableResult
    func setRotation(publicId: String, quarterTurns: Int) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["quarterTurns": quarterTurns])
        let req = try makeRequest(path: "/api/coffees/\(publicId)/rotation", method: "POST", body: body)
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

    // POST /api/review/rules — remember a raw->canonical mapping (an
    // "accept and remember" long-press, PLAN.md §6.5) for one of the alias
    // tables `routes/review.js`'s `ALIAS_TABLES` knows (`kind`, e.g.
    // "roaster"). `alias` is the raw string being aliased.
    @discardableResult
    func createReviewRule(kind: String, canonicalId: Int, alias: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: [
            "kind": kind, "canonicalId": canonicalId, "alias": alias,
        ])
        let req = try makeRequest(path: "/api/review/rules", method: "POST", body: body)
        _ = try await send(req)
        return true
    }

    // POST /api/coffees/:publicId/edit — apply a per-field edit outside the
    // review flow (PLAN.md §12 #40). Same raw-string-in, canonicalize-on-the-
    // backend shape as `resolveReview`; a value the backend can't
    // canonicalize (e.g. an unknown country) comes back as HTTP 422.
    @discardableResult
    func editCoffeeField(publicId: String, field: String, value: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["field": field, "value": value])
        let req = try makeRequest(path: "/api/coffees/\(publicId)/edit", method: "POST", body: body)
        _ = try await send(req)
        return true
    }

    // POST /api/coffees/:publicId/edit with a body's `edits` array — applies
    // multiple field edits in one request instead of one call per field
    // (`routes/coffees.js` resolves each in order, then writes the coffees
    // row once; any single edit's 422 aborts the whole batch before anything
    // is applied). Closes the gap #42's edit sheet flagged: two single-field
    // `editCoffeeField` calls for e.g. `roaster` + `roasterCountry` have no
    // ordering guarantee against each other, so a derived value could race
    // an explicit one.
    @discardableResult
    func editCoffeeFields(publicId: String, edits: [CoffeeFieldEdit]) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: [
            "edits": edits.map { ["field": $0.field, "value": $0.value] },
        ])
        let req = try makeRequest(path: "/api/coffees/\(publicId)/edit", method: "POST", body: body)
        _ = try await send(req)
        return true
    }

    // GET /api/brief — the editorial "This month" section (PLAN.md §6.4);
    // `nil` until the backend has generated one.
    func brief() async throws -> Brief? {
        let req = try makeRequest(path: "/api/brief", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(BriefResponseDTO.self, from: data).brief
        } catch {
            throw APIError.decoding(error)
        }
    }

    // GET /api/whatsnew — curated "what's live / what's planned" content for
    // the What's New screen (PLAN.md §13, #45/#46). No `since`/pagination —
    // the whole payload is a handful of short cards; the caller decides
    // whether to cache it for the session (no local persistence here).
    func whatsNew() async throws -> WhatsNewResponseDTO {
        let req = try makeRequest(path: "/api/whatsnew", method: "GET", body: nil)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(WhatsNewResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // POST /api/photos/manifest — registers one or more photos for the Add
    // Coffee wizard (PLAN.md §6.8, #75/#76) ahead of uploading their bytes.
    // `description` is only ever set on the primary/front photo's entry: it
    // carries the wizard's pasted whole-bag text, since #75 has no separate
    // text parameter anywhere in its wire contract.
    func uploadPhotoManifest(entries: [PhotoManifestEntry]) async throws -> [PhotoManifestResultDTO] {
        let body = try JSONSerialization.data(withJSONObject: [
            "entries": entries.map { entry -> [String: Any] in
                var dict: [String: Any] = [
                    "sourceId": entry.sourceId,
                    "contentSha256": entry.contentSha256,
                    "capturedAt": ISO8601DateFormatter.coffeeAPI.string(from: entry.capturedAt),
                ]
                if let description = entry.description { dict["description"] = description }
                return dict
            },
        ])
        let req = try makeRequest(path: "/api/photos/manifest", method: "POST", body: body)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(PhotoManifestResponseDTO.self, from: data).results
        } catch {
            throw APIError.decoding(error)
        }
    }

    // PUT /api/photos/:sourceId/image — uploads one photo's raw JPEG bytes,
    // content-addressed by its own sha256 (must match the manifest entry's
    // `contentSha256` for that `sourceId`). Binary body, so this bypasses
    // `makeRequest`'s JSON `Content-Type`.
    @discardableResult
    func uploadPhotoImage(sourceId: String, sha256: String, jpegData: Data) async throws -> Bool {
        var components = URLComponents(string: baseURL + "/api/photos/\(sourceId)/image")
        components?.queryItems = [URLQueryItem(name: "sha256", value: sha256)]
        guard let url = components?.url else { throw APIError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpegData
        _ = try await send(req)
        return true
    }

    // POST /api/coffees/extract — the wizard's light extraction ensemble over
    // already-uploaded photos (PLAN.md §6.8, #75/#76); `photoIds[0]` is the
    // primary/front photo whose manifest `description` carried the pasted
    // full text.
    func extractDraft(photoIds: [String]) async throws -> ExtractedDraftDTO {
        let body = try JSONSerialization.data(withJSONObject: ["photoIds": photoIds])
        let req = try makeRequest(path: "/api/coffees/extract", method: "POST", body: body)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(ExtractedDraftDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // POST /api/coffees — persists the wizard's confirmed fields as a
    // brand-new coffee (#75/#76); every field lands `locked=true`/
    // `decided_by='human'` server-side so the monthly re-extraction backfill
    // never overwrites it. `fields` reuses the same `{field, value}` shape
    // `editCoffeeFields` already sends.
    func createCoffee(photoIds: [String], fields: [CoffeeFieldEdit]) async throws -> CreateCoffeeResponseDTO {
        let body = try JSONSerialization.data(withJSONObject: [
            "photoIds": photoIds,
            "fields": fields.map { ["field": $0.field, "value": $0.value] },
        ])
        let req = try makeRequest(path: "/api/coffees", method: "POST", body: body)
        let data = try await send(req)
        do {
            return try JSONDecoder.coffeeAPI.decode(CreateCoffeeResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

/// One request entry for `uploadPhotoManifest` (PLAN.md §6.8, #75/#76).
struct PhotoManifestEntry: Sendable {
    let sourceId: String
    let contentSha256: String
    let capturedAt: Date
    let description: String?
}

struct StatusResponse: Codable {
    let ok: Bool
    let service: String
    let db: Bool
}

/// One field/value pair in a batch edit request (`editCoffeeFields`,
/// PLAN.md §12). `value` is always the same raw string the single-field
/// `editCoffeeField` takes — the backend's `resolveField` does the
/// canonicalizing either way.
struct CoffeeFieldEdit: Codable, Sendable, Equatable {
    let field: String
    let value: String
}
