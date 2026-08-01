import Foundation

extension JSONDecoder {
    /// The one shared decoder for every backend response. Postgres `timestamptz`
    /// serializes with fractional seconds and `.iso8601` rejects them outright —
    /// this strategy tolerates both. `PlainDate` fields (`purchased_on`,
    /// `roasted_on`) are unaffected: they decode as plain strings, not `Date`,
    /// so this strategy never applies to them.
    static let coffeeAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) {
                return date
            }
            if let date = ISO8601DateFormatter.withoutFractionalSeconds.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 timestamp, got \(raw)"
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    /// The encoding half of `.coffeeAPI` — used to persist the local snapshot
    /// file (`PersistedSnapshot`) and to encode a `since` query param, so a
    /// round-trip through disk or through the wire always uses the same
    /// fractional-seconds ISO-8601 shape.
    static let coffeeAPI: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.withFractionalSeconds.string(from: date))
        }
        return encoder
    }()
}

extension ISO8601DateFormatter {
    /// Shared, non-private formatter for call sites that need to *build* a
    /// timestamp string directly (e.g. `APIClient`'s `since` query param)
    /// rather than go through a full `Encoder`.
    static let coffeeAPI = withFractionalSeconds

    fileprivate static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    fileprivate static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
