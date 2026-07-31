import SwiftUI

/// A rounded coffee-bag thumbnail. Every sample coffee has `images == nil`
/// (no photo pipeline until #22), so the empty state below is what the UX
/// lane actually builds and sees today, not a rare edge case.
struct Thumbnail: View {
    let urlString: String?
    var size: CGFloat = 84
    var cornerRadius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFill()
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: Symbols.emptyCup)
            .font(.system(size: size * 0.36))
            .foregroundStyle(.secondary)
    }
}
