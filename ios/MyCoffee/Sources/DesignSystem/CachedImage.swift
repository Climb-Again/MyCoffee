import SwiftUI

/// A phase-based replacement for `AsyncImage`, backed by
/// `Store/ImageStore.swift`'s disk-cached, downsample-on-write actor instead
/// of `URLSession` + `URLCache` — see that file's doc comment for why (the
/// signed `display` URL's `exp`/`sig` query rotates every sync, so
/// `URLCache` never hits). Used for the hero/zoom/review photos (#180);
/// `Thumbnail.swift` remains the fixed-square, row-thumbnail-shaped sibling.
struct CachedImage<Content: View>: View {
    enum Phase {
        case empty
        case success(Image)
        case failure
    }

    let urlString: String?
    var maxPixelSize: CGFloat = ImageStore.displayMaxPixelSize
    @ViewBuilder var content: (Phase) -> Content

    @State private var phase: Phase = .empty

    var body: some View {
        content(phase)
            .task(id: urlString) {
                guard let urlString, !urlString.isEmpty else {
                    phase = .failure
                    return
                }
                phase = .empty
                guard let cgImage = try? await ImageStore.shared.thumbnail(
                    for: urlString,
                    maxPixelSize: maxPixelSize
                ) else {
                    phase = .failure
                    return
                }
                phase = .success(Image(uiImage: UIImage(cgImage: cgImage)))
            }
    }
}
