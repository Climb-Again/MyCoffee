import Foundation

/// The `GET /api/brief` envelope (`routes/brief.js`). `brief` decodes
/// straight onto the domain `Brief` — the wire shape and the model are
/// identical today, no NUMERIC-string or nullable-vs-required quirks to
/// bridge, unlike `CoffeeDetailDTO`/`CompactCoffeeDTO`.
struct BriefResponseDTO: Decodable {
    let brief: Brief?
}
