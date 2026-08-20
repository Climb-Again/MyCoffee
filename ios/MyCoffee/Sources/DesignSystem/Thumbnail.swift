import SwiftUI
import UIKit

/// A rounded coffee-bag thumbnail, backed by `Store/ImageStore.swift`'s
/// disk-cached, downsample-on-write actor rather than a plain `AsyncImage` —
/// see that file's doc comment for why (a 12 MP JPEG decoded full-size in a
/// scrolling list would be a ~48 MB bitmap per row).
struct Thumbnail: View {
    let urlString: String?
    var size: CGFloat = 84
    var cornerRadius: CGFloat = 10
    /// Persisted display rotation (#57), quarter-turns clockwise. Applied inside
    /// the square, clipped frame so a corrected-orientation thumb crops cleanly.
    var rotationQuarterTurns: Int = 0

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .rotationEffect(.degrees(Double(((rotationQuarterTurns % 4) + 4) % 4) * 90))
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: urlString) {
                image = nil
                guard let urlString else { return }
                let maxPixelSize = size * displayScale
                guard let cgImage = try? await ImageStore.shared.thumbnail(
                    for: urlString,
                    maxPixelSize: maxPixelSize
                ) else { return }
                image = UIImage(cgImage: cgImage)
            }
    }

    private var placeholder: some View {
        Image(systemName: Symbols.emptyCup)
            .font(.system(size: size * 0.36))
            .foregroundStyle(.secondary)
    }
}
