import Foundation

/// A data-driven money bucket (half-open, in cents to avoid float-hashing
/// surprises), used for both the price and €/100 g dimensions. Unlike
/// `RatingBand`/`AltitudeBand` there's no fixed brief-given boundary — the
/// bucket width is chosen from the observed data range so "€15 – €20" stays
/// meaningful whether the library's prices span €5–€30 or €3–€8.
struct PriceBand: Hashable, Sendable, Comparable {
    let lowerCents: Int   // inclusive
    let upperCents: Int   // exclusive

    static func < (lhs: PriceBand, rhs: PriceBand) -> Bool { lhs.lowerCents < rhs.lowerCents }

    /// e.g. "€15 – €20". Whole-euro rounding matches the brief's own examples;
    /// this app only ever displays EUR (every price is converted at ingest).
    var label: String {
        let lower = lowerCents / 100
        let upper = upperCents / 100
        return "€\(lower) – €\(upper)"
    }

    /// Candidate bucket widths, in cents, tried smallest-first until the
    /// observed range fits in `maxBuckets` or fewer buckets.
    private static let candidateWidthsCents = [
        100, 200, 250, 500, 1_000, 2_000, 2_500, 5_000, 10_000, 20_000, 25_000, 50_000,
    ]

    /// The shared bucket width (in cents) for a set of (non-nil) EUR amounts —
    /// compute this once per dataset, then bucket each value with `band(for:widthCents:)`.
    /// `nil` for an empty input.
    static func widthCents(forEUR amounts: [Double], maxBuckets: Int = 8) -> Int? {
        guard !amounts.isEmpty else { return nil }
        let cents = amounts.map { Int(($0 * 100).rounded()) }
        let span = max((cents.max() ?? 0) - (cents.min() ?? 0), 1)
        return candidateWidthsCents.first { (span / $0) + 1 <= maxBuckets } ?? candidateWidthsCents.last!
    }

    static func band(forEUR amount: Double, widthCents: Int) -> PriceBand {
        let cents = Int((amount * 100).rounded())
        let lower = (cents / widthCents) * widthCents
        return PriceBand(lowerCents: lower, upperCents: lower + widthCents)
    }
}
