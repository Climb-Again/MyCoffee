import SwiftUI

extension String {
    /// Regional-indicator flag emoji for a two-letter ISO-3166 alpha-2 code.
    /// `nil` for anything that isn't exactly two Latin letters (the data
    /// contains pseudo-countries like `Blend` and multi-values like
    /// `Colombia / Brazilia` that never reach this as a code, but a defensive
    /// `nil` keeps this safe for any stray value too).
    ///
    /// The trap (PLAN.md §6.6): the two regional indicators combine into
    /// **one** grapheme cluster, so checking `result.count == 2` afterwards
    /// is always false. Validate on the *input's* scalar count instead.
    var flagEmoji: String? {
        let scalars = uppercased().unicodeScalars.filter { ("A"..."Z").contains(Character($0)) }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    }
}

/// Renders a country's flag emoji, falling back to a white flag + code for
/// pseudo-countries (`Blend`) or anything without a resolvable ISO code.
struct FlagView: View {
    let isoCode: String?

    var body: some View {
        if let isoCode, let emoji = isoCode.flagEmoji {
            Text(emoji)
        } else {
            Text("🏳️" + (isoCode.map { " \($0)" } ?? ""))
        }
    }
}
