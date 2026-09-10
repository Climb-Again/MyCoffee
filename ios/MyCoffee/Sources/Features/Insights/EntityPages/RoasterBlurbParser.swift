import Foundation

/// One bullet from a roaster's blurb — `- **Label** — text` becomes a
/// labelled fact, a plain `- text` bullet keeps `label == nil`.
struct RoasterBlurbBullet: Identifiable {
    let label: String?
    let text: String
    var id: String { (label ?? "") + text }
}

/// Strips the raw markdown a roaster's `blurb` arrives with — asterisked
/// bold and `- ` bullets — since the page used to show both literally
/// (`**Convection roasting precision**` visible on screen, `HEADER_UPDATE.md`
/// §8). Deliberately simple: this data only ever uses bold spans and a flat
/// bullet list, never headers, links or nested lists.
enum RoasterBlurbParser {
    struct Parsed {
        let intro: String
        let bullets: [RoasterBlurbBullet]
    }

    static func parse(_ blurb: String) -> Parsed {
        var introParts: [String] = []
        var bullets: [RoasterBlurbBullet] = []

        for rawLine in blurb.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let (label, text) = labelAndText(from: body) {
                    bullets.append(RoasterBlurbBullet(label: label, text: text))
                } else {
                    bullets.append(RoasterBlurbBullet(label: nil, text: stripBold(body)))
                }
            } else {
                introParts.append(stripBold(line))
            }
        }
        return Parsed(intro: introParts.joined(separator: " "), bullets: bullets)
    }

    /// `**Label** — text` / `**Label**: text` / `**Label** - text`.
    private static func labelAndText(from body: String) -> (label: String, text: String)? {
        guard body.hasPrefix("**") else { return nil }
        let afterOpen = body.index(body.startIndex, offsetBy: 2)
        guard let closeRange = body.range(of: "**", range: afterOpen..<body.endIndex) else { return nil }
        let label = String(body[afterOpen..<closeRange.lowerBound])
        var rest = String(body[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        for separator in ["—", "–", "-", ":"] where rest.hasPrefix(separator) {
            rest = String(rest.dropFirst(separator.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return (label, stripBold(rest))
    }

    private static func stripBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
}
