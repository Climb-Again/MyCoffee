import SwiftUI

/// Design tokens for the 2026-08-25 Coffees/Coffee-page/Insights redesign
/// (`design/coffees_redesign/README.md`, treatment "2a"). Foundation for
/// BACKLOG #84–#89 — every redesigned view references these rather than
/// re-deriving hex values. Palette is derived from the app icon
/// (`design/coffees_redesign/AppIcon-1024.png`).
enum Theme {
    enum Colors {
        static let accent = Color(hex: "0078FF")
        static let accent600 = Color(hex: "005EFF")
        static let accent100 = Color(hex: "EEF6FF")
        static let accent200 = Color(hex: "CAF0F8")
        static let accent700 = Color(hex: "0047C4")
        static let accent800 = Color(hex: "00337F")
        static let neutral100 = Color(hex: "F8F4F4")
        static let neutral300 = Color(hex: "D7D3D3")
        /// All small grey type. ≥4.5:1 contrast on white — do not use a lighter grey.
        static let neutral700 = Color(hex: "605D5D")
        static let neutral900 = Color(hex: "2D2B2B")
        static let text = Color(hex: "201E1D")
        /// 2a is white, not the system theme's default grouped background.
        static let surface = Color(hex: "FFFFFF")
    }

    enum Radius {
        static let photo: CGFloat = 10
        /// Chips, search, buttons, favourite — effectively "fully round" at
        /// any reasonable frame size, matching the design tokens 1:1.
        static let pill: CGFloat = 999
        static let card: CGFloat = 20
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        static let sm = ShadowStyle(color: Colors.neutral900.opacity(0.14), radius: 2, x: 0, y: 1)
        static let md = ShadowStyle(color: Colors.neutral900.opacity(0.16), radius: 10, x: 0, y: 3)
    }

    /// CSS-scale weights from the handoff (400/600/800) mapped onto SwiftUI's
    /// matching `Font.Weight` raw values.
    enum Weight {
        static let regular: Font.Weight = .regular
        static let semibold: Font.Weight = .semibold
        static let heavy: Font.Weight = .heavy
    }

    /// The handoff's minimum tap target everywhere (chips, breakdown rows,
    /// hero circles, favourite, toggles) — the visual glyph may be smaller
    /// inside it (`#88`).
    static let minHitTarget: CGFloat = 44
}

extension View {
    func themeShadow(_ style: Theme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

private extension Color {
    /// `"RRGGBB"`, no `#`.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
