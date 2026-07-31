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

enum ProcessStyles {
    static func style(for profile: Profile) -> ProcessStyle {
        switch profile {
        case .washed: return washed
        case .natural: return natural
        case .anaerobic: return anaerobic
        case .coFermented: return coFermented
        case .experimental: return experimental
        }
    }

    static let unknown = ProcessStyle(symbol: Symbols.processUnknown, light: "6B7280", dark: "9CA3AF")
    static let decaf = ProcessStyle(symbol: Symbols.processDecaf, light: "4A5568", dark: "A7B4C4")

    private static let natural = ProcessStyle(symbol: Symbols.processNatural, light: "B23A1E", dark: "FF9E7D")
    private static let washed = ProcessStyle(symbol: Symbols.processWashed, light: "0B6BB5", dark: "7CC4FF")
    private static let anaerobic = ProcessStyle(symbol: Symbols.processAnaerobic, light: "6B3FA0", dark: "C6A7F0")
    private static let coFermented = ProcessStyle(symbol: Symbols.processCoFermented, light: "0E7C6B", dark: "6FD9C4")
    private static let experimental = ProcessStyle(symbol: Symbols.processExperimental, light: "A8145A", dark: "FF9BC4")
}

/// A tinted capsule for a coffee's process/profile. `nil` renders as the
/// "Unknown" facet — never defaulted to Washed (PLAN.md pushback #4).
struct ProcessTag: View {
    let profile: Profile?

    private var style: ProcessStyle { profile.map(ProcessStyles.style) ?? ProcessStyles.unknown }
    private var title: String { profile?.displayName ?? "Unknown" }

    var body: some View {
        Label(title, systemImage: style.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.color.opacity(0.18), in: Capsule())
            .foregroundStyle(style.color)
    }
}

/// A small badge for `is_decaf`, tracked orthogonally to `profile` — a decaf
/// can be washed (PLAN.md pushback #3).
struct DecafBadge: View {
    var body: some View {
        Label("Decaf", systemImage: ProcessStyles.decaf.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ProcessStyles.decaf.color.opacity(0.18), in: Capsule())
            .foregroundStyle(ProcessStyles.decaf.color)
    }
}
