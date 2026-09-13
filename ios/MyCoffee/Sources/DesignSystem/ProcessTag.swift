import SwiftUI
import UIKit

private extension UIColor {
    /// `"RRGGBB"`, no `#`.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

/// A process's tint, as a light/dark hex pair defined in code — zero new
/// asset entries, nothing for CI to mis-generate (PLAN.md §6.6).
struct ProcessStyle {
    let symbol: String
    private let light: UIColor
    private let dark: UIColor

    fileprivate init(symbol: String, light: String, dark: String) {
        self.symbol = symbol
        self.light = UIColor(hex: light)
        self.dark = UIColor(hex: dark)
    }

    var color: Color {
        Color(uiColor: UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? self.dark : self.light }))
    }
}

/// #181: only `DecafBadge` uses this now — `ProcessTag` (which needed
/// `.style(for:)` and the five per-profile styles) was deleted as dead code,
/// so those went with it.
enum ProcessStyles {
    static let decaf = ProcessStyle(symbol: Symbols.processDecaf, light: "4A5568", dark: "A7B4C4")
}

/// A small badge for `is_decaf`, tracked orthogonally to `profile` — a decaf
/// can be washed (PLAN.md pushback #3).
struct DecafBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ProcessStyles.decaf.symbol)
            Text("Decaf")
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(ProcessStyles.decaf.color.opacity(0.18), in: Capsule())
        .foregroundStyle(ProcessStyles.decaf.color)
    }
}
