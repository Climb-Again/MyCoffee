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

/// Renders **one flag per origin country**, for a coffee that legitimately has
/// several (a blend: `origin_country_ids`). The listing row used to pass `nil`
/// for any blend, so every multi-origin coffee showed a single white flag even
/// though its text already read "Colombia · Brazil".
///
/// Falls back to the same white flag as `FlagView` when nothing resolves — a
/// blend whose origins are unknown still gets a marker rather than an empty gap.
/// The flags concatenate into one `Text`: each is a single grapheme cluster, so
/// this lays out as compactly as one glyph run and can't wrap mid-flag. Pinned
/// with `lineLimit(1)` + `fixedSize` for the same reason the rating and process
/// tag are — under horizontal pressure SwiftUI would otherwise break the run.
struct FlagsView: View {
    let isoCodes: [String?]

    private var emoji: String {
        let flags = isoCodes.compactMap { $0?.flagEmoji }
        return flags.isEmpty ? "🏳️" : flags.joined()
    }

    var body: some View {
        Text(emoji)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
