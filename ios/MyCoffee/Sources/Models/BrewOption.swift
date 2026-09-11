import Foundation

/// The four brew catalogues (PLAN.md §14, backlog #155/#156): one discriminator
/// enum rather than four separate types, mirroring the backend's single
/// `brew_options` table with a `kind` column.
enum BrewKind: String, Codable, CaseIterable, Sendable {
    case recipe
    case device
    case grind
    case temp

    var displayName: String {
        switch self {
        case .recipe: return "Recipe"
        case .device: return "Device"
        case .grind: return "Grind size"
        case .temp: return "Temperature"
        }
    }
}

/// A recipe's structured body (Radu, 2026-09-09: coffee grams, number of
/// pours, ml per pour, total water, grind clicks, water temp — not a free-text
/// `detail`). `mlPerPour` is the only optional field — nil for uneven pours,
/// where only the total is meaningful.
struct BrewRecipeSpec: Codable, Hashable, Sendable {
    let doseG: Double
    let pours: Int
    let mlPerPour: Int?
    let totalWaterMl: Int
    let grindClicks: Int
    let waterTempC: Int

    var ratio: Double { Double(totalWaterMl) / doseG }

    /// "20 g · 5 × 60 ml · 300 ml · 1:15 · 28 clicks · 92 °C" — drops the
    /// ml/pour term when uneven pours leave it nil ("15 g · 3 pours · 250 ml ·
    /// 1:16.7 · 24 clicks · 95 °C").
    var summary: String {
        let doseText = Self.trimmedNumber(doseG)
        let pourText: String
        if let mlPerPour {
            pourText = "\(pours) × \(mlPerPour) ml"
        } else {
            pourText = pours == 1 ? "1 pour" : "\(pours) pours"
        }
        let ratioText = "1:" + Self.trimmedNumber(ratio, maxFractionDigits: 1)
        return "\(doseText) g · \(pourText) · \(totalWaterMl) ml · \(ratioText) · \(grindClicks) clicks · \(waterTempC) °C"
    }

    private static func trimmedNumber(_ value: Double, maxFractionDigits: Int = 1) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.\(maxFractionDigits)f", value)
    }

    /// The wire body `POST`/`PATCH /api/brew-options` expect for a recipe
    /// (`routes/brew.js`'s `validateRecipe`) — `mlPerPour` omitted, not `nil`,
    /// when the pours are uneven.
    var wireDictionary: [String: Any] {
        var dict: [String: Any] = [
            "doseG": doseG, "pours": pours, "totalWaterMl": totalWaterMl,
            "grindClicks": grindClicks, "waterTempC": waterTempC,
        ]
        if let mlPerPour { dict["mlPerPour"] = mlPerPour }
        return dict
    }
}

/// One row in a brew catalogue (PLAN.md §14). `recipe` is non-nil only when
/// `kind == .recipe`; `valueNum` carries the grind-clicks/temperature-°C
/// number for `.grind`/`.temp` rows (nil otherwise).
struct BrewOption: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let kind: BrewKind
    let label: String
    let detail: String?
    let valueNum: Double?
    let recipe: BrewRecipeSpec?
    let sortOrder: Int
    let archived: Bool
}

/// A (coffee, option) pair's tri-state (PLAN.md §14) — deliberately no 1–5
/// score per pair, just untried / tried / best, with at most one best per
/// (coffee, kind).
enum BrewTrialState: String, Codable, Sendable {
    case untried
    case tried
    case best
}
