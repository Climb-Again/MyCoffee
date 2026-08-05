import Foundation

/// Decodes `T` if it can, otherwise degrades to `nil` instead of throwing.
/// Used to make the snapshot's arrays lenient: a single element that fails to
/// decode (e.g. an unexpected `null` on a field the model treats as required)
/// is skipped rather than dropping the ENTIRE array. This app has now been
/// blanked three times by that exact all-or-nothing failure — one null roaster
/// id, one null `iso2` on the Blend row — so element-level tolerance is the
/// structural fix, not just patching each field as it surfaces.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Postgres `NUMERIC` columns (`price_eur`, `rating`, `min_field_confidence`, …)
    /// come back from `pg` as JSON **strings**, not bare numbers — the driver
    /// deliberately doesn't auto-parse them, to avoid float precision loss.
    /// `INT`/`SMALLINT` columns (`weight_g`, `altitude_min_m`, …) don't have
    /// this problem and decode as plain `Int` elsewhere. A malformed or
    /// unexpectedly-shaped value degrades to `nil` rather than failing the
    /// whole row's decode — one bad numeric field shouldn't drop a coffee
    /// out of the snapshot.
    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string)
        }
        return try? decodeIfPresent(Double.self, forKey: key)
    }
}
