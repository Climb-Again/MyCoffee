import SwiftUI

/// A deterministic colored-circle avatar for entities with no real artwork
/// (roasters — PLAN.md pushback #11: "a roaster page needs a logo that
/// doesn't exist in the data"). Same name always yields the same color, so a
/// roaster's avatar stays stable across launches without persisting anything.
struct MonogramAvatar: View {
    let name: String
    var size: CGFloat = 56

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private var color: Color {
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }

    // Reuses the process-tag hue family so an entity avatar never looks like
    // a stray new color introduced just for this screen.
    private static let palette: [Color] = [
        Color(hex: "B23A1E"), Color(hex: "0B6BB5"), Color(hex: "6B3FA0"),
        Color(hex: "0E7C6B"), Color(hex: "A8145A"), Color(hex: "6B7280"),
    ]

    var body: some View {
        Circle()
            .fill(color.opacity(0.85))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
