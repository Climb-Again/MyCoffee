import Foundation

extension Int {
    /// Normalizes a quarter-turn rotation count to `0...3` clockwise — #181
    /// dedupe of `((x % 4) + 4) % 4`, which handles Swift's `%` returning a
    /// negative result for a negative dividend (a "rotate back" adjustment
    /// can go below zero before this normalizes it). Duplicated across
    /// `Thumbnail.swift`, `ZoomableImageView.swift` and, still as of #181,
    /// `Models/Coffee.swift:91,176` — that file is shell-owned, so adopting
    /// this there needs a seam edit from the `ios-shell` lane.
    var normalizedQuarterTurns: Int { ((self % 4) + 4) % 4 }
}
