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

- [2026-07-31 00:00 UTC] No open backlog row (#22 blocked on backend #21) — instead closed the cross-boundary gap
  the UX lane flagged in `status/ios-ux.md` after #18: `Profile` and `SortOption` are both used in `Hashable`-requiring
  contexts (`Set<Profile>` on `CoffeeFilter`, `FacetKey.profile(Profile)`, a `Picker` binding to `SortOption`) but
  neither declared it at the original type. UX had bridged the gap with manual `extension Profile: Hashable` /
  `extension SortOption: Hashable` in their own `Features/Coffees/CoffeeDisplay.swift`, explicitly asking shell to
  move it into the originals in the same commit if we'd rather. Did that: added `Hashable` to the conformance list on
  both `Models/Profile.swift` and `Query/SortOption.swift` (trivial synthesis, no associated values), and removed the
  now-redundant manual `==`/`hash(into:)`/`sortKey` from `CoffeeDisplay.swift`, keeping only its `SortOption.displayName`
  extension (UX's, unrelated to the conformance). Checked `RatingBand`/`PriceBand`/`AltitudeBand` — also used in
  `Set<_>` on `CoffeeFilter` — for the same gap; all three already declare `Hashable` at the original declaration, so
  no further fix needed there. No BACKLOG.md row for this (not new scope, just closing a flagged gap in already-owned
  files); left `main`'s stale copy of #17/#18 as `ready`/`blocked` untouched — that's the dev/ship split's job to
  reconcile when `ios-staging` merges to `main`, not something to fix by pushing to `main` directly.
  - `Sources/Models/Profile.swift`, `Sources/Query/SortOption.swift`, `Sources/Features/Coffees/CoffeeDisplay.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-01 00:00 UTC] Session check — no ready `ios-shell` row. Only other
  row is #22 (phase 2), still `blocked` on backend #21, which is itself
  `blocked` on #11 (done) + #14 (data lane, still `ready` not `done`). Checked
  `git branch -r --list 'origin/claude/*'` per the integrate-before-you-start
  rule: all stranded branches predate the #17/#18 merge (they diff as pure
  deletions against current `main`/`ios-staging`) — no un-integrated ios-shell
  work to adopt. `ios-staging` and `main` agree on `status/BACKLOG.md`. Stopping
  cleanly rather than inventing work or touching UX-owned paths.

## Abandoned

_none_
