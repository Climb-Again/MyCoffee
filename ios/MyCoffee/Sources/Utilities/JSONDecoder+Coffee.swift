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

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
