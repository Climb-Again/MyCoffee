import SwiftUI
import UIKit

/// Design tokens for the 2026-08-25 Coffees/Coffee-page/Insights redesign
/// (`design/coffees_redesign/README.md`, treatment "2a"). Foundation for
/// BACKLOG #84–#89 — every redesigned view references these rather than
/// re-deriving hex values. Palette is derived from the app icon
/// (`design/coffees_redesign/AppIcon-1024.png`).
///
/// # Dark mode (#100)
///
/// Every ink/surface token below is **adaptive** — it resolves against the
/// current `UITraitCollection`, so one token name works in both themes. The
/// light values are the handoff's, unchanged; the dark values are new.
///
/// The bug this fixes: the tokens used to be fixed light-only literals
/// (`text` = `#201E1D`, `surface` = `#FFFFFF`), and nothing set
/// `preferredColorScheme`. `surface` was painted in only two places, so in dark
/// mode SwiftUI supplied a black system background while every ink token stayed
/// near-black — the entire listing rendered black-on-black.
///
/// **The rule for any new view:** never paint a background with a literal
/// (`Color.white`, `.black`) and never pair a token with a literal ground.
/// Take *both* the ink and the surface under it from this enum, or the view
/// will be correct in one theme and invisible in the other. Where a view sits
/// on the always-blue header band, use `onAccent` / `accent200`, which are
/// deliberately **fixed** because their ground is fixed.
enum Theme {
    enum Colors {
        /// Brand blue: the header band, the `+`, selected chips, filled stars,
        /// and blue-on-surface text. Lifted slightly in dark so it still passes
        /// as body text against the dark surface (~5.9:1) without changing how
        /// white reads on top of it.
        static let accent = adaptive(light: "0078FF", dark: "2E90FF")
        static let accent600 = adaptive(light: "005EFF", dark: "1A7DFF")
        /// Pale blue fill behind `accent700`/`accent800` text (pills, BriefCard).
        static let accent100 = adaptive(light: "EEF6FF", dark: "15263A")
        /// **Fixed on purpose** — the stats overline sits on the always-blue
        /// header band, whose ground does not change between themes.
        static let accent200 = Color(hex: "CAF0F8")
        /// Blue text on `surface` or on `accent100`. Inverts to a light blue in
        /// dark, where a `#0047C4` would be unreadable.
        static let accent700 = adaptive(light: "0047C4", dark: "8FC2FF")
        static let accent800 = adaptive(light: "00337F", dark: "B9D8FF")
        /// Neutral pill fill (process/altitude/weight chips).
        static let neutral100 = adaptive(light: "F8F4F4", dark: "201E1E")
        /// Chip and frame borders, and the *unfilled* star — must stay visible
        /// against `surface` in both themes.
        static let neutral300 = adaptive(light: "D7D3D3", dark: "3F3B3B")
        /// All small grey type. ≥4.5:1 on `surface` in both themes — do not use
        /// a lighter grey in light or a darker one in dark.
        static let neutral700 = adaptive(light: "605D5D", dark: "A6A1A1")
        /// Label colour for an *unselected* chip, whose ground is `surface`.
        static let neutral900 = adaptive(light: "2D2B2B", dark: "EDEAEA")
        /// Hairline row dividers (Insights breakdown card, `#89`) — distinct
        /// from `neutral300`'s heavier chip/frame border.
        static let hairline = adaptive(light: "EAE7E7", dark: "2C2929")
        /// Primary ink.
        static let text = adaptive(light: "201E1D", dark: "F2EFEF")
        /// The page ground. 2a is white in light, and a warm near-black in dark
        /// that matches the warm neutral family (not a pure `#000`).
        static let surface = adaptive(light: "FFFFFF", dark: "141212")
        /// **Fixed on purpose** — ink for anything drawn on the blue header
        /// band or on a filled `accent` chip, both of which stay blue in dark.
        static let onAccent = Color.white
        /// Shadow ink. Kept dark in *both* themes — it must never follow
        /// `neutral900`, or shadows become white glows in dark mode.
        static let shadow = Color(hex: "000000")
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
        static let sm = ShadowStyle(color: Colors.shadow.opacity(0.14), radius: 2, x: 0, y: 1)
        static let md = ShadowStyle(color: Colors.shadow.opacity(0.16), radius: 10, x: 0, y: 3)
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

extension Theme {
    /// Resolves per-trait, so a single token name is correct in both themes.
    /// `UIColor`'s dynamic provider is the only mechanism that re-resolves on a
    /// live theme change; a `@Environment(\.colorScheme)` check would have to be
    /// threaded through every call site instead. Not `fileprivate`: `#99`'s
    /// blue chart ramp (`InsightsCharts.swift`) needs its own light/dark hex
    /// pairs distinct from the named `Colors` tokens, built with this same helper.
    static func adaptive(light: String, dark: String) -> Color {
        let lightColor = UIColor(Color(hex: light))
        let darkColor = UIColor(Color(hex: dark))
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
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
