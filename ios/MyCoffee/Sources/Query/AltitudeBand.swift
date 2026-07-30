import Foundation

/// Fixed 500 m altitude buckets. **Multi-valued**: a coffee stored as
/// 1300–1600 m belongs to both `.r1000to1500` and `.r1500to2000`, so altitude
/// facet counts intentionally sum to more than the total (PLAN.md §5) — the
/// section footnote that explains this is a UI concern, not enforced here.
enum AltitudeBand: CaseIterable, Hashable, Sendable {
    case under1000
    case r1000to1500
    case r1500to2000
    case r2000to2500
    case over2500
    case unknown

    /// `nil` only for `.unknown`.
    var range: ClosedRange<Int>? {
        switch self {
        case .under1000: return 0...999
        case .r1000to1500: return 1000...1499
        case .r1500to2000: return 1500...1999
        case .r2000to2500: return 2000...2499
        case .over2500: return 2500...Int.max
        case .unknown: return nil
        }
    }

    var label: String {
        switch self {
        case .under1000: return "Under 1000 m"
        case .r1000to1500: return "1000 – 1500 m"
        case .r1500to2000: return "1500 – 2000 m"
        case .r2000to2500: return "2000 – 2500 m"
        case .over2500: return "2500 m+"
        case .unknown: return "Unknown"
        }
    }

    /// Every band whose range overlaps `[min, max]`. Empty altitude data
    /// yields exactly `[.unknown]`.
    static func bands(forMin min: Int?, max: Int?) -> [AltitudeBand] {
        guard let min, let max else { return [.unknown] }
        let lo = Swift.min(min, max)
        let hi = Swift.max(min, max)
        let span = lo...hi
        return Self.allCases.filter { band in
            guard let r = band.range else { return false }
            return r.overlaps(span)
        }
    }
}
