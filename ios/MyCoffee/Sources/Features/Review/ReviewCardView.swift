import SwiftUI

/// One field, one decision (PLAN.md §6.5): source photo up top, the raw
/// snippet with the flagged value highlighted, the top candidate as one big
/// chip, alternates below, an "Other…" field revealed on demand, then the full
/// source text. Tap a chip to accept (long-press to accept **and** remember the
/// correction for every remaining task with the same raw value); explicit
/// "Skip" / "Not on the bag" buttons handle the other two outcomes. There is
/// deliberately **no** swipe gesture — the card scrolls to show the full text,
/// and a swipe-to-dismiss would fire every time you dragged to read it.
struct ReviewCardView: View {
    let task: ReviewTask
    let onAccept: (String) -> Void
    let onAcceptWithRule: (String) -> Void
    let onSkip: () -> Void
    let onNotPresent: () -> Void

    @State private var otherText = ""
    @State private var showOtherField = false
    @State private var fullTextExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReviewPhoto(urlString: task.thumbUrl)
            snippetBlock
            candidateChips
            if showOtherField {
                otherField
            }
            fullTextSection
            actionRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                onSkip()
            } label: {
                Label("Skip", systemImage: Symbols.chevronRight)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onNotPresent()
            } label: {
                Label("Not on the bag", systemImage: Symbols.reviewPhotoMissing)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private var snippetBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(task.field.label, systemImage: task.field.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let reason = task.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let snippet = task.rawSnippet {
                highlighted(snippet, matching: task.rawValue)
                    .font(.subheadline)
            }
        }
    }

    private func highlighted(_ snippet: String, matching rawValue: String) -> Text {
        guard let range = snippet.range(of: rawValue, options: .caseInsensitive) else {
            return Text(snippet)
        }
        let before = Text(snippet[snippet.startIndex..<range.lowerBound])
        let match = Text(snippet[range]).fontWeight(.bold).foregroundColor(.orange)
        let after = Text(snippet[range.upperBound...])
        return before + match + after
    }

    private var candidateChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let top = task.candidates.first {
                ReviewChip(candidate: top, isPrimary: true,
                           onTap: { onAccept(top.value) },
                           onLongPress: { onAcceptWithRule(top.value) })
            }
            WrapLayout() {
                ForEach(task.candidates.dropFirst()) { candidate in
                    ReviewChip(candidate: candidate, isPrimary: false,
                               onTap: { onAccept(candidate.value) },
                               onLongPress: { onAcceptWithRule(candidate.value) })
                }
                otherChip
            }
        }
    }

    private var otherChip: some View {
        Button {
            showOtherField = true
        } label: {
            Label("Other…", systemImage: Symbols.reviewOther)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var otherField: some View {
        HStack {
            TextField("Type the correct value", text: $otherText)
                .textFieldStyle(.roundedBorder)
            Button("Use") {
                let trimmed = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onAccept(trimmed)
            }
            .disabled(otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// The whole scraped caption/description behind this task. Expanded by
    /// default — it's the context the reviewer decides from — but collapsible
    /// when the short snippet is enough.
    @ViewBuilder
    private var fullTextSection: some View {
        if let fullText = task.fullText, fullText != task.rawSnippet {
            DisclosureGroup(isExpanded: $fullTextExpanded) {
                Text(fullText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Text("Full text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReviewChip: View {
    let candidate: ReviewCandidate
    let isPrimary: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.value)
                .font(isPrimary ? .title3.weight(.semibold) : .subheadline.weight(.medium))
            if let hint = candidate.hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, isPrimary ? 18 : 12)
        .padding(.vertical, isPrimary ? 12 : 7)
        .frame(maxWidth: isPrimary ? .infinity : nil, alignment: .leading)
        .background(
            isPrimary ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: isPrimary ? 16 : 14, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress)
    }
}

/// Pinch-zoomable source photo (PLAN.md §6.5's "killer feature": the source
/// photo the extracted values came from). Loads the signed `thumbUrl` the
/// review feed now carries; falls back to a placeholder when a row has no
/// photo URL (or while it's loading), staying zoomable in both states.
private struct ReviewPhoto: View {
    let urlString: String?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.85))
            if let url = urlString.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholderContent
                    default:
                        ProgressView().tint(.white)
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .scaleEffect(scale)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(
            MagnificationGesture()
                .onChanged { value in scale = max(1, min(4, lastScale * value)) }
                .onEnded { _ in lastScale = scale }
        )
        .onTapGesture(count: 2) {
            withAnimation { scale = 1; lastScale = 1 }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: Symbols.reviewZoom)
                .font(.caption)
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .padding(10)
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: Symbols.reviewPhotoMissing)
                .font(.system(size: 40))
            Text("Source photo unavailable")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .foregroundStyle(.white.opacity(0.7))
    }
}
