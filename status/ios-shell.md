# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- [2026-07-30 00:00 UTC] 17 Create `ios-staging`; models, `CoffeeIndex`, filters/facets/bands, sample repo — branch `ios-staging`
  - `Sources/Models/{Coffee,Profile,Vocab}.swift` — mirrors the planned `coffees` row (PLAN.md §1). Property names spell
    acronyms as `Id`/`Eur`, not `ID`/`EUR`, to match `JSONDecoder`'s `.convertFromSnakeCase` output exactly.
  - `Sources/Query/{FilterDimension,CoffeeFilter,RatingBand,AltitudeBand,PriceBand,FacetCounts,TopFilterCard,SortOption}.swift`
    — the 11-ish filter dimensions, half-open rating bands, multi-valued altitude bands, and data-driven price bands (PLAN.md §5).
  - `Sources/Store/CoffeeIndex.swift` — the in-memory index: postings-based `matches`/`facets`/`topFilterCards`, per the
    pseudocode in PLAN.md §5.
  - `Sources/Store/{CoffeeRepository,SampleCoffeeRepository,SampleData,CoffeeStore}.swift` — a protocol + ~22-record
    fixture dataset covering every band/edge case (nil rating, nil price, blend, decaf, unknown roaster country, thin
    facets) so the UX lane can build real screens now; the real network repository is #22, blocked on backend #21.
  - Commit: (see `git log` on `ios-staging`)

## Abandoned

_none_

## Abandoned

_none_
