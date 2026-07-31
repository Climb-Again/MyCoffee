import Foundation

extension String {
    /// Diacritic- and case-folded form used for on-device search haystacks and
    /// vocabulary matching — "Etiopia" and "café" both fold to plain ASCII-ish
    /// lowercase so search matches regardless of accent or case.
    var foldedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
