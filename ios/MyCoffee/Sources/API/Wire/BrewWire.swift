import Foundation

/// Wire shapes for the Brew lab API (PLAN.md §14, backlog #155/#156):
/// `GET /api/brew-options`, `POST /api/brew-options`, `PATCH
/// /api/brew-options/:id`, `POST /api/coffees/:publicId/brew`. All keys are
/// already camelCase server-side (`routes/brew.js`'s `toBrewOption`), and
/// every NUMERIC column the route touches (`value_num`, `dose_g`) is
/// `Number()`-converted before sending, so — unlike `price_eur`/`rating`
/// elsewhere — these decode as plain JSON numbers, no `decodeFlexibleDouble`
/// needed.
struct BrewOptionDTO: Decodable {
    let id: Int
    let kind: String
    let label: String
    let detail: String?
    let valueNum: Double?
    let recipe: BrewRecipeSpecDTO?
    let sortOrder: Int
    let archived: Bool
}

struct BrewRecipeSpecDTO: Decodable {
    let doseG: Double
    let pours: Int
    let mlPerPour: Int?
    let totalWaterMl: Int
    let grindClicks: Int
    let waterTempC: Int
}

/// `GET /api/brew-options` response envelope.
struct BrewOptionListResponseDTO: Decodable {
    let options: [BrewOptionDTO]
}

/// `POST /api/coffees/:publicId/brew` response — the coffee's WHOLE brew
/// state, since the recipe auto-tick (server-side) can change more than the
/// one (coffee, option) pair the request named. The client replaces the
/// coffee's brew arrays from this atomically rather than reconciling
/// per-option.
struct BrewStateResponseDTO: Decodable, Sendable {
    let id: String
    let brewTried: [Int]
    let brewBest: [Int]
}
