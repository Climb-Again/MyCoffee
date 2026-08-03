# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- [2026-08-01 12:00 UTC] 22 Remote repository + SyncEngine + ImageStore + MutationOutbox — branch `ios-staging`
  - `Sources/Store/{SyncEngine,RemoteCoffeeRepository,MutationOutbox,ImageStore,PersistedSnapshot}.swift`,
    `Sources/API/Wire/{SnapshotWire,CoffeeDetailWire,CoffeeMapping,FlexibleDecoding}.swift`, plus edits to
    `Sources/{Models/Coffee,Models/Vocab,Store/CoffeeIndex,Store/CoffeeRepository,Store/SampleCoffeeRepository,
    Store/CoffeeStore,API/APIClient,Utilities/CoffeeCoding}.swift` (renamed from `JSONDecoder+Coffee.swift`).
  - `RemoteCoffeeRepository` is `CoffeeStore`'s default now (`SampleCoffeeRepository` stays for previews).
    `SyncEngine` actor holds the single `[id: Coffee]` map every operation (sync merge, favorite toggle, detail
    enrichment) mutates through, so "server row wins unless a pending mutation is un-acked" (PLAN.md §5) has one
    place to hold true; delta-syncs `/api/snapshot` with `since = lastSyncAt − 60s`, merges upserts + `deleted`,
    drops the cache and forces one full refetch on a `schemaVersion` mismatch, persists to
    `Application Support/MyCoffee/snapshot.json` via `PersistedSnapshot` (atomic write). `MutationOutbox` persists
    pending favorite writes to `outbox.json` and flushes them against `APIClient` at the end of every sync.
    `ImageStore` is the disk-backed, downsample-on-write cache PLAN.md §5 specifies instead of `URLCache`
    (in-flight coalescing, 250 MB/30-day eviction) — built but **not yet wired into any view** (see below).
  - **Two real wire-format bugs found and fixed while building this, both in code this lane owns, discovered
    because #21's actual backend responses don't match what #17 assumed before those endpoints existed:**
    1. `Country`'s wire shape (`loadCountryVocab` in the backend's `vocab.js`) is `{id, name, iso2, is_origin,
       is_roaster, kind}` — no `isPseudo` boolean at all (`kind` is a string, `"pseudo"` one of its values) and
       the ISO column is `iso2`, not `iso_code`. Decoding the real `/api/snapshot` into the existing `Country`
       struct as-is would have thrown on every sync. Fixed with a custom `Codable` on `Country` (`Models/Vocab.swift`)
       that bridges `iso2`/`kind` to `isoCode`/`isPseudo` — every other call site (`isoCode` is used all over
       `DesignSystem`/`Features`) keeps working unchanged. `Roaster`/`Farm` didn't need this; their columns already
       line up under `.convertFromSnakeCase`.
    2. Postgres `NUMERIC` columns (`price_eur`, `price_original_amount`, `rating`, `min_field_confidence`) come
       back from `pg` as JSON **strings**, not bare numbers — the driver doesn't auto-parse them, to avoid float
       precision loss. A plain `Double?` `Decodable` property fails on a quoted number. Added
       `KeyedDecodingContainer.decodeFlexibleDouble(forKey:)` (`API/Wire/FlexibleDecoding.swift`) and gave
       `CompactCoffeeDTO`/`CoffeeDetailDTO` custom `init(from:)` using it for exactly those four fields —
       `INT`/`SMALLINT` columns (`weight_g`, `altitude_min_m`, …) don't have this problem and stay plain `Int`.
  - Two follow-ups flagged for whoever picks them up next, **not done here** because they're outside this
    lane's owned directories or blocked on backend scope:
    1. **UX wiring gap** (`Sources/{Features,DesignSystem}/**`, iOS UX lane's files): `DesignSystem/Thumbnail.swift`
       still renders via a plain `AsyncImage`, not `ImageStore`; and no view calls `CoffeeStore.toggleFavorite`/
       `.loadDetail` yet — the heart icon in `CoffeeRowView.swift` renders `coffee.isFavorite` but has no tap
       gesture, and `CoffeeDetailView.swift` never calls `.task { await store.loadDetail(for: coffee) }` to
       populate real notes/images (the compact snapshot doesn't carry them — PLAN.md §4). Both methods exist and
       are ready to call; this is presentation wiring, not new plumbing, so left for the UX lane.
    2. **Batch media-URL endpoint** (backend-owned, noted independently by the backend lane after #21): the
       compact snapshot has no per-row image URL at all, so bulk thumbnail prefetch (PLAN.md §5's "prefetch them
       all over Wi-Fi via the BGTask") has nothing to prefetch *from* yet — only `GET /api/coffees/:publicId`
       returns `thumbUrl`/`displayUrl` today, one coffee at a time. `ImageStore` is built and ready to consume such
       an endpoint once it exists; not inventing it here since `routes/**` is backend-owned. No BGTask registration
       was added either (`Info.plist`'s `ro.climbagain.mycoffee.refresh` id has never been registered anywhere in
       `Sources/App`) — same reasoning: its only real payload today (bulk thumbnail prefetch) is blocked on the
       same missing endpoint, so registering an empty handler now would be scaffolding without a job.
  - Commit: (see `git log` on `ios-staging`)

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

- [2026-08-02 00:00 UTC] Session check — no ready `ios-shell` row. Only rows
  are #17 and #22, both already `done` (the latter closed 2026-08-01 by the
  prior ios-shell session, after this routine's last "no ready row" check).
  The only other iOS-shell-adjacent row, #27 (ios-ux, phase 5), needs #22
  (done) + #24 (backend, still `blocked` on #23). Checked
  `git branch -r --list 'origin/claude/*'` per the integrate-before-you-start
  rule: every candidate branch (`determined-thompson-*`, `wizardly-thompson-eurlj6`,
  `relaxed-thompson-ceai5p`, `modest-newton-oxaddt`, `lanes-status-blockers-wws2lc`,
  `new-app-infrastructure-setup-h3r3wz`, `coffee-app-plan-9jdh0c`) diffs as pure
  deletions against current `ios-staging` in the owned paths — each predates
  #22 and carries no unmerged work. Merged `origin/main` into `ios-staging`
  (resolved a "Right now" conflict in `status/BACKLOG.md` by keeping both the
  ios-shell #22 note and the data #20 note — additive, no factual conflict)
  to pick up #20's landing before stopping. Stopping cleanly rather than
  inventing work or touching UX-owned paths.

- [2026-08-02 UTC] Session check — no ready `ios-shell` row, unchanged from
  the prior check earlier today. Only ios-shell rows are #17 and #22, both
  `done`. The only other iOS-adjacent row, #27 (ios-ux, phase 5), needs #22
  (done) + #24 (backend, still `blocked` on #23 — unstarted). Re-fetched
  origin and re-swept every `origin/claude/*` branch (`git rev-list --count
  origin/ios-staging..<branch> -- <ios-shell-owned paths>`) per the
  integrate-before-you-start rule: all 25 candidate branches show `0` commits
  ahead in the paths this lane owns (`Sources/{App,Store,API,Models,Query,
  Utilities}`, `project.yml`) — nothing stranded to adopt. Merged
  `origin/main` into `ios-staging` (resolved an additive conflict in
  `status/backend.md` — two backend session-check entries from the same UTC
  day, kept both, no factual conflict) before stopping. Stopping cleanly
  rather than inventing work or touching UX-owned paths.

- [2026-08-03 UTC] Session check — no ready `ios-shell` row. Only ios-shell
  rows are #17 and #22, both `done`. The only other iOS-adjacent row, #27
  (ios-ux, phase 5), needs #22 (done) + #24 (backend, still `blocked` on #23
  — unstarted). Re-swept every `origin/claude/*` branch (`git rev-list
  --count origin/ios-staging..<branch> -- <ios-shell-owned paths>`) per the
  integrate-before-you-start rule: the only candidate is this session's own
  fresh branch (`claude/wizardly-thompson-0d0ydb`), 0 commits ahead in any
  owned path — nothing stranded to adopt. Merged `origin/main` into
  `ios-staging` (fast-forward-style, no conflicts — just backend/UX session-
  check commits) before stopping. Stopping cleanly rather than inventing
  work or touching UX-owned paths.

## Abandoned

_none_
