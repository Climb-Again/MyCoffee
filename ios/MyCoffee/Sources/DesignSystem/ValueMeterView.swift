import SwiftUI

/// The five-pill "cheap-for-quality" value meter + its verdict label
/// (#105/#113, #186's band-tone colors) — verbatim-duplicated in
/// `CoffeeRowView` and `CoffeeDetailView` until #181 folded them into one
/// view. `spacing` defaults to `CoffeeDetailView`'s original nested-`VStack`
/// gap (4pt); `CoffeeRowView` passes 2pt to match its old outer-`VStack`
/// spacing exactly.
struct ValueMeterView: View {
    let rating: ValueRating
    var spacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            pips
            if let band = rating.band {
                Text(band.label)
                    .font(.system(size: 10, weight: band == .great ? Theme.Weight.bold : Theme.Weight.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Self.bandColor(band))
            }
        }
    }

    private var pips: some View {
        let tone = Self.bandColor(rating.band)
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: Theme.Radius.pill)
                    .fill(pip < rating.pillCount ? tone : tone.opacity(0.15))
                    .frame(width: 8, height: 4)
            }
        }
    }

    /// One shared depth tone per band — the lit pills, the unlit track (this
    /// colour at 15%) and the verdict text all read off this.
    static func bandColor(_ band: ValueRating.Band?) -> Color {
        switch band {
        case .overpaid: return Theme.Colors.valueOverpaid
        case .poor: return Theme.Colors.valuePoor
        case .fair: return Theme.Colors.valueFair
        case .good: return Theme.Colors.valueGood
        case .great: return Theme.Colors.valueGreat
        case nil: return Theme.Colors.neutral700
        }
    }
}
