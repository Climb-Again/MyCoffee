import SwiftUI
import UIKit

/// The roaster medallion (`HEADER_UPDATE.md` §2, shared verbatim by §8): an
/// 86×86pt rounded-square tile, shared by the coffee-detail header and the
/// roaster page. **No logo → no tile** — this renders nothing at all (not
/// even the background/ring) when `logoUrl` is absent, so callers must not
/// reserve layout space for it on that path.
///
/// Web-only fetch, matching the existing roaster-logo rule (Radu,
/// 2026-09-07: "do not cache logos") — no `ImageStore`, no disk
/// persistence. `RoasterMarkCache` below is an in-memory-only memo of the
/// **crop**, not the source bytes, and it is gone the moment the process
/// exits.
struct RoasterLogoTile: View {
    let logoUrl: String?
    var size: CGFloat = 86
    var cornerRadius: CGFloat = 22

    @State private var mark: UIImage?

    private var hasLogo: Bool {
        !(logoUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        if hasLogo {
            Group {
                if let mark {
                    Image(uiImage: mark)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 9 / 86)
                }
            }
            .frame(width: size, height: size)
            .background(
                Theme.Colors.logoTileBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // Clip before the ring/shadow: a square-cornered source mark
            // must not poke past the tile's own rounded silhouette.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white, lineWidth: 3)
            )
            // Fixed white ring/shadow ink: this tile always sits astride the
            // hero photo (§2), whose ground doesn't change with the theme —
            // same reasoning as `Theme.Colors.onAccent`.
            .shadow(color: .black.opacity(0.16), radius: 14, y: 3)
            .task(id: logoUrl) {
                await loadMark()
            }
        }
    }

    private func loadMark() async {
        guard let logoUrl, let url = URL(string: logoUrl) else { return }
        if let cached = await RoasterMarkCache.shared.get(logoUrl) {
            mark = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = UIImage(data: data),
              let cgImage = source.cgImage
        else { return }
        let cropped = Self.cropToMark(cgImage)
        let result = UIImage(cgImage: cropped, scale: source.scale, orientation: source.imageOrientation)
        await RoasterMarkCache.shared.set(logoUrl, result)
        mark = result
    }

    /// "Use the mark, not the lockup" (§2): a wide image (mark + wordmark,
    /// like DAK's) is cropped to its leading square, the common convention
    /// for a lockup's mark. There's no per-roaster crop metadata and no
    /// on-device vision framework in play here, so this is a deliberate,
    /// documented heuristic rather than true bounding-box detection — a
    /// square or portrait logo (ratio below 1.3) is left untouched.
    private static func cropToMark(_ image: CGImage) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard height > 0, width / height >= 1.3 else { return image }
        let rect = CGRect(x: 0, y: 0, width: height, height: height)
        return image.cropping(to: rect) ?? image
    }
}

/// Per-process memo of the leading-square crop, keyed by `logoUrl` — avoids
/// re-decoding/re-cropping the same roaster's mark on every render. Not a
/// disk cache; nothing here survives past the running process.
private actor RoasterMarkCache {
    static let shared = RoasterMarkCache()
    private var storage: [String: UIImage] = [:]

    func get(_ key: String) -> UIImage? { storage[key] }
    func set(_ key: String, _ image: UIImage) { storage[key] = image }
}
