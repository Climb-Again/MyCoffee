import SwiftUI

/// A dedicated full-screen pan+zoom photo viewer: double-tap to zoom in/out,
/// pinch to scale, drag to pan while zoomed, bounded so the photo can't be
/// dragged fully off-screen, tap the close button to dismiss. Presented via
/// `.fullScreenCover`, not embedded inline in a scrolling card — an in-card
/// `MagnificationGesture` loses to the enclosing scroll view's own drag
/// recognizer, and `.scaleEffect` alone has no way to pan the magnified
/// region into view once it no longer fits the card's frame (PLAN.md
/// §13/#55). Shared by the Review card's source photo and the coffee detail
/// page's hero photo, which both had this exact broken in-card pattern.
struct ZoomableImageView: View {
    let urlString: String?
    /// Starting display rotation (#57), quarter-turns clockwise. Persisted via
    /// `onRotate` when the user taps the rotate control; the control only shows
    /// when a handler is provided (so the Review card, whose photo has no coffee
    /// row yet, gets a plain zoomable viewer with no rotate button).
    var initialRotationQuarterTurns: Int = 0
    var onRotate: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var rotationTurns: Int = 0
    @GestureState private var pinchDelta: CGFloat = 1
    @GestureState private var dragDelta: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: Symbols.close)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .overlay(alignment: .bottomTrailing) {
            if onRotate != nil {
                Button {
                    let next = (rotationTurns + 1) % 4
                    withAnimation { rotationTurns = next }
                    onRotate?(next)
                } label: {
                    Image(systemName: Symbols.rotate)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding()
            }
        }
        .onAppear { rotationTurns = ((initialRotationQuarterTurns % 4) + 4) % 4 }
    }

    private var content: some View {
        Group {
            if let url = urlString.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(Double(rotationTurns) * 90))
                            .scaleEffect(displayScale)
                            .offset(displayOffset)
                            .gesture(SimultaneousGesture(pinchGesture, dragGesture))
                            .onTapGesture(count: 2, perform: toggleZoom)
                    case .failure:
                        Image(systemName: Symbols.reviewPhotoMissing)
                            .font(.system(size: 56))
                            .foregroundStyle(.white.opacity(0.5))
                    default:
                        ProgressView().tint(.white)
                    }
                }
            } else {
                Image(systemName: Symbols.reviewPhotoMissing)
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var displayScale: CGFloat {
        max(minScale, min(maxScale, scale * pinchDelta))
    }

    private var displayOffset: CGSize {
        CGSize(width: offset.width + dragDelta.width, height: offset.height + dragDelta.height)
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in state = value }
            .onEnded { value in
                let newScale = max(minScale, min(maxScale, scale * value))
                scale = newScale
                if newScale <= minScale { withAnimation { offset = .zero } }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragDelta) { value, state, _ in
                guard scale > minScale else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > minScale else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > minScale {
                scale = minScale
                offset = .zero
            } else {
                scale = 3
            }
        }
    }
}
