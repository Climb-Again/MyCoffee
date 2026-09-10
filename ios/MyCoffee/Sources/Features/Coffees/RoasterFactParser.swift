import Foundation

/// One cell of the "FROM THE ROASTER" grid (`HEADER_UPDATE.md` §5).
struct RoasterFact: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

/// Best-effort extraction of the four facts out of the roaster's own raw
/// scraped copy — there is no structured `variety`/`fermentation`/`drying`/
/// `washingStation` field anywhere in the data, so this reads the same
/// title/caption/description text the "full text" section already shows.
///
/// Two passes, in order, first match wins per fact: the roaster's own
/// `Label: value` line, then a named-keyword sniff for the fact's
/// surrounding clause. Deliberately conservative — a miss here just falls
/// through to the plain excerpt (`fewer than two facts → skip the grid`,
/// §5), so this never needs to be exhaustive to be safe.
enum RoasterFactParser {
    private struct Field {
        let key: String
        let labels: [String]
        let keywords: [String]
    }

    /// Order fixed by §5: VARIETY · FERMENTATION · DRYING · WASHING STATION.
    private static let fields: [Field] = [
        Field(key: "VARIETY", labels: ["variety", "varieties", "varietate", "soi", "cultivar"], keywords: []),
        Field(
            key: "FERMENTATION",
            labels: ["fermentation", "fermentare", "ferment"],
            keywords: ["anaerobic", "72 h", "72h", "fermentation"]
        ),
        Field(
            key: "DRYING",
            labels: ["drying", "dried", "uscare", "uscat"],
            keywords: ["raised beds", "sun-dried", "sun dried", "patio dried", "drying"]
        ),
        Field(
            key: "WASHING STATION",
            labels: ["washing station", "wet mill", "washing", "statie de spalare", "stație de spălare"],
            keywords: ["washing station", "wet mill", "washed"]
        ),
    ]

    static func extract(from texts: [String]) -> [RoasterFact] {
        let combined = texts.joined(separator: "\n")
        let lines = combined
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.components(separatedBy: ".") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var facts: [RoasterFact] = []
        for field in fields {
            if let value = labeledValue(for: field.labels, in: lines) {
                facts.append(RoasterFact(key: field.key, value: value))
                continue
            }
            if let value = keywordClause(for: field.keywords, in: lines) {
                facts.append(RoasterFact(key: field.key, value: value))
            }
        }
        return facts
    }

    /// A line of the shape `Label: value` or `Label - value`, label matched
    /// case-insensitively against any of `labels`.
    private static func labeledValue(for labels: [String], in lines: [String]) -> String? {
        for line in lines {
            guard let separatorRange = line.range(of: ":") ?? line.range(of: " - ") ?? line.range(of: "\u{2013}") else {
                continue
            }
            let label = line[line.startIndex..<separatorRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard labels.contains(where: { label == $0 || label.hasSuffix($0) }) else { continue }
            let value = line[separatorRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            return String(value.prefix(80))
        }
        return nil
    }

    /// The first clause containing one of `keywords`, trimmed and capped —
    /// a lower-confidence fallback for roaster copy with no explicit label.
    private static func keywordClause(for keywords: [String], in lines: [String]) -> String? {
        guard !keywords.isEmpty else { return nil }
        for line in lines {
            let lowered = line.lowercased()
            guard keywords.contains(where: { lowered.contains($0) }) else { continue }
            return String(line.prefix(80))
        }
        return nil
    }
}
