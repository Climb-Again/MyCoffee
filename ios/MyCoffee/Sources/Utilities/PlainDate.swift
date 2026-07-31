import Foundation

/// A calendar date with no time component ("YYYY-MM-DD"), as Postgres emits a
/// `DATE` column. Deliberately decoded independently of any decoder-level
/// date strategy — `purchased_on`/`roasted_on` are dates, not instants, and
/// mixing them with the fractional-seconds `timestamptz` strategy used
/// elsewhere would either reject them or silently apply a timezone shift.
struct PlainDate: Hashable, Sendable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    private var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Midnight UTC on this calendar day — safe for interval math, never for display.
    var utcMidnight: Date {
        Calendar.utc.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(string: String) {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return nil
        }
        self.init(year: y, month: m, day: d)
    }

    static func < (lhs: PlainDate, rhs: PlainDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension PlainDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = PlainDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

extension Calendar {
    /// The Gregorian calendar pinned to UTC — every `PlainDate` and month/year
    /// bucketing computation in the app goes through this one instance so
    /// "July 2026" section headers never drift with the device time zone.
    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}
