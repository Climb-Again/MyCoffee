import Foundation

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
