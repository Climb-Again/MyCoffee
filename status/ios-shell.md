# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- [2026-08-18 UTC, later session] Session check — unchanged from the check
  right below. No ready `ios-shell` row: #17/#22/#41/#46 all `done`, #71(a)'s
  seam confirmed consumed. Only `ready` row anywhere in `BACKLOG.md` is `#57`
  (ios-ux, persisted photo rotation) — re-confirmed independently (repo-wide
  grep for `rotation_quarter_turns`/`rotationQuarterTurns` still empty outside
  status-file prose) there is nothing concrete on the backend side yet for
  this lane's named seam to build against. Re-swept the top commit-ahead-count
  `origin/claude/*` candidates in this lane's owned paths
  (`confident-cerf-{t1flso,j8in2k,9y3vqr}`, `modest-newton-oml7h8`,
  `confident-cerf-fti5j5`) — all confirmed net-deletions against current
  `ios-staging`, nothing stranded to adopt. Merged `origin/main` into
  `ios-staging` (`8647fcd`), resolving one additive conflict in
  `status/backend.md` (two independent same-day backend session-check
  entries) by keeping both. Stopping cleanly rather than inventing work.

- [2026-08-18 UTC] Session check — no ready `ios-shell` row. #17/#22/#41/#46
  remain the only rows tagged `ios-shell`, all `done`; #71(a)'s seam (this
  lane's own prior session, same day as this file's most recent entry below)
  is confirmed consumed by ios-ux's #71 half. The only `ready` row anywhere in
  `BACKLOG.md` is `#57` (ios-ux, persisted photo rotation) — re-checked its
  named shell seam (`CoffeeImage`/detail model field + API surface for a
  per-photo `rotation_quarter_turns`) and confirmed again there is still
  nothing concrete to build against: no backend column, write endpoint, or
  snapshot field exists yet (repo-wide grep for `rotation_quarter_turns` and
  `rotationQuarterTurns` still empty outside status-file prose), same
  conclusion as every prior check. #72 (backend, What's New refresh) landed
  `done` on `main` since this lane's last check but hadn't been merged into
  `ios-staging` yet — merged `origin/main` in (`199f5cf`), resolving one
  additive conflict in `status/BACKLOG.md`: `ios-staging` and `main` each had
  an independent, correct `done` update to a different row in the same
  `#71`/`#72` table block (this lane's own #71 close-out vs. backend's #72
  close-out) — kept both rather than picking one side, same precedent as
  every prior session's handling of this exact conflict shape.
  - Swept `git branch -r --list 'origin/claude/*'` (109 candidates after
    fetching) per the integrate-before-you-start rule: sampled the highest
    commit-ahead-count candidates in this lane's owned paths
    (`confident-cerf-{t1flso,j8in2k}` ×17, `modest-newton-oml7h8`/
    `confident-cerf-fti5j5` ×14, `peaceful-mccarthy-71uw7l`/
    `relaxed-thompson-uq5f21` ×8, `hopeful-johnson-3xcwg7` ×6,
    `determined-thompson-yjymsr` ×4) and confirmed by `git diff --stat` that
    every one is a **net deletion** against current `ios-staging` — stale
    pre-#71(a)/pre-#46/pre-#41 snapshots, same pattern every prior sweep has
    found. Nothing stranded to adopt.
  - Stopping cleanly rather than inventing work or touching UX-owned paths.

- [2026-08-17 UTC] 71(a) `RelativeWindow` seam for the listing filter — branch `ios-staging`
  - No `ios-shell`-tagged row was `ready` this cycle (`#17`/`#22`/`#41`/`#46` all `done`). But
    `#71` (ios-ux, ready, no needs) explicitly names a shell-owned seam — `status/ios-ux.md`'s
    2026-08-17 entry confirms the UX lane already looked at this row, found part (a) touches
    `Query/{CoffeeFilter,CoffeeIndex,FilterDimension}.swift` (shell-owned), and deliberately
    left it rather than guess the wire shape — same precedent as `#50`'s tab-selection seam
    (2026-08-14 entry below). Picked it up instead of stopping on a no-op session.
  - Checked `#57` (the other `ready` row naming a shell seam, persisted photo rotation) first:
    still nothing to build against — no backend column/endpoint exists yet (confirmed via
    `status/backend.md` and a repo-wide grep for `rotation_quarter_turns`), same conclusion
    every prior session reached. Left it for whenever backend lands its half.
  - **New `Query/RelativeWindow.swift`**: `enum RelativeWindow { case last12m, last18m }` with
    `months: Int` and a `cutoff(now:)` that reuses `Calendar.utc` (`Utilities/PlainDate.swift`,
    already shell-owned) — the exact same `Calendar.utc.date(byAdding: .month, value: -months,
    to: Date())` computation `InsightsView.coffeesSince(months:)` already does for the Charts
    tab's own `ChartWindow.last12m`/`.last18m`, so the listing filter and the Charts tab agree
    on what "last 12 months" means. Deliberately has no `.all`/`.years` cases — those are
    already covered by `relativeWindow == nil` and the existing `years: Set<Int>` field
    respectively, per the row's own "kept distinct from years" framing.
  - **`CoffeeFilter`**: added `var relativeWindow: RelativeWindow?` (nil = no window
    constraint) and folded it into `isEmpty`. Deliberately did **not** add a `FilterDimension`
    case for it — `clearing(_:)`/`facets(for:)`/`topFilterCards()` all key off
    `FilterDimension` to compute per-value pill counts, but a relative window isn't a
    multi-select vocab-style facet (there's no "count if the other window were selected"
    question to answer), it's a single active toggle exactly like the Charts tab's own
    segmented control — which is a plain `Picker`, not a facet pill list. Modeling it as a
    bare optional keeps `clearing(_:)` correct for free: since no dimension case owns it,
    `clearing(.roaster)` (etc.) leaves `relativeWindow` untouched, exactly the "only clear
    the one dimension being cleared" contract every other cross-cutting field (`query`,
    `isDecaf`, `favoritesOnly`) already relies on.
  - **`CoffeeIndex.matches(_:)`**: applies the cutoff directly (`coffees.indices.filter {
    $0.purchasedOn.utcMidnight >= cutoff }`) right after the free-text `query` intersection,
    with the same one-line justification `query` already has in a comment: both depend on
    "now"/live input, so neither can live in the prebuilt `postings` map (built once from
    static data) the way vocab/band/bool dimensions do.
  - **UX lane: two wiring pieces remain, not new plumbing.** (a) The filter sheet needs a
    control that sets `store.filter.relativeWindow` — no existing pill loop fits (it's not a
    `FilterDimension`), so this is a new small section, e.g. a segmented control mirroring
    `InsightsView`'s own Charts-tab window picker. (b) `InsightsView.selectInCoffees(dimension:
    key:)` (`#50`/`#53`/`#54`'s existing deep-link, `InsightsView.swift:310`) builds a fresh
    `CoffeeFilter()` and should also copy the Charts tab's current `window` across as the
    matching `RelativeWindow` case (`.last12m`→`.last12m`, `.last18m`→`.last18m`, `.all`/
    `.years` → leave `relativeWindow` `nil`) before setting `store.filter` — the row's own
    part (b) ask. Not making either UI change myself — `Features/Coffees/**` and
    `Features/Insights/**` are UX-owned.
  - Not locally compiled (no Xcode here) — the new file mirrors `RatingBand.swift`'s exact
    shape (a plain `CaseIterable`/`Hashable`/`Sendable` enum with computed properties, no
    associated values), and both edited files are small, additive, single-purpose insertions
    into already-compiling functions — a red compile check here should point at a typo, not a
    design gap.
  - `ios/MyCoffee/Sources/Query/{CoffeeFilter,RelativeWindow}.swift`,
    `ios/MyCoffee/Sources/Store/CoffeeIndex.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-17 UTC] Session check — no ready `ios-shell` row. #17/#22/#41/#46
  remain the only rows tagged `ios-shell`, all `done`. The only `ready` rows
  in the whole backlog this cycle are backend (#67, #69) and ios-ux (#50,
  #53, #54, #55, #57, #58, #66, #68 per `main`'s stale copy of the table —
  but a later `ios-ux` session already flipped #50/#53/#54/#55/#58/#66/#68 to
  `done` on `ios-staging` itself, confirmed live in `Features/Insights/**`,
  `DesignSystem/ZoomableImageView.swift`, and `RootTabView.swift`; only #57
  is genuinely still open). `#57` (persisted rotate photo) names a shell
  piece (`CoffeeImage`/detail model field + API surface for a per-photo
  `rotation_quarter_turns`), but its own row and the ios-ux session note
  both confirm no backend column/write-endpoint/snapshot field exists yet —
  nothing concrete for this lane's half to build against, so not guessing a
  wire shape blind.
  - **Merged `origin/main` into `ios-staging`** (`d27b4e5`) — the two
    branches had diverged the usual way: `ios-staging` already knew
    #50/#53/#54/#55/#58/#66 were `done` (a later ios-ux session verified and
    flipped them) while `main`'s copy (last touched from the data lane's
    #29/#67 close-out) still showed them `ready` and had #67's lane
    corrected to `backend` plus a new #69 row `ios-staging` didn't have yet.
    Resolved the `status/BACKLOG.md` conflict as the union of both sides'
    newer knowledge (kept `ios-staging`'s `done` status for #66/#68, kept
    `main`'s corrected #67 lane tag + new #69 row) and kept both `status/
    backend.md` session-check entries (additive, no factual conflict, same
    precedent as every prior session-check merge in this file). Confirmed
    post-merge every row number in the table appears exactly once (no
    duplicate rows from the conflict) and that no `ios-shell`-owned path was
    touched by the merge (`git diff origin/ios-staging HEAD --stat` shows
    only `status/*.md`).
  - Re-swept all 122 `origin/claude/*` branches (up from ~100 at the last
    check) for stranded `ios-shell` work per the integrate-before-you-start
    rule: dozens show a nonzero `git rev-list --count` in this lane's owned
    paths, but every naming cluster sampled (`confident-cerf-*` including
    four new branches at the highest ahead-count of 14, `determined-
    thompson-*`, `peaceful-mccarthy-*`, `modest-newton-oml7h8`, `hopeful-
    johnson-3hio6h`, `relaxed-thompson-uq5f21`) diffs as a **net deletion**
    against current `ios-staging` (missing `SyncEngine`/`SampleCoffeeRepository`
    content later commits added) — the same stale pre-#22/#41/#46 snapshot
    pattern every prior sweep in this file has found. Nothing stranded to
    adopt.
  - Stopping cleanly rather than inventing work or touching UX/backend/
    data-owned paths.

- [2026-08-16 UTC] Session check — no ready `ios-shell` row. #17/#22/#41/#46
  remain the only rows tagged `ios-shell`, all `done`. The only `ready` rows
  in the whole backlog are ios-ux (#50, #53, #54, #55, #57, #58, #66, #68) and
  data (#29, #67) — #50/#53/#54/#57 each note a possible "seam" surface
  (`CoffeeStore`/tab-selection/rotation field) this lane might eventually need
  to add, but none of them is itself an `ios-shell` row yet, so not inventing
  that work ahead of an actual claim.
  - **Found and fixed a real problem while merging `origin/main` in**:
    `ios-staging` hadn't merged `main` since before backend's Vertex→Gemini
    migration (#61/#64/#65 era) — `git merge-base` showed the two branches'
    common ancestor was `a3ca39c` (the #55 backlog filing), well behind both
    tips. Worse, `ios-staging` itself carried two backend commits
    (`08b6185`/`ed33303`, same "migrate to Gemini Developer API" /
    "gemini-2.5-flash + billing labels" work as `main`'s `fbe0879`/`5ac265a`)
    that some prior session pushed to the wrong branch — a lane-boundary
    violation (`backend/**` is backend-owned, not `ios-shell`'s to touch, and
    backend pushes to `main` not `ios-staging`). Those stray commits diverged
    just enough from `main`'s own (further-evolved, e.g. `9b6ffcd`'s
    retryDelay-body-parsing fix) that `git merge origin/main` produced real
    content conflicts in `backend/src/{config,vertex}.js` and
    `backend/src/lib/agents.js`, plus additive conflicts in
    `status/BACKLOG.md`/`status/backend.md` (duplicated Right-now entries).
    Resolved by taking `origin/main`'s content wholesale for every
    backend/data-owned path (`backend/**`, `ops/**`, `status/BACKLOG.md`,
    `status/backend.md`) — confirmed post-merge the working tree is
    byte-identical to `origin/main` for all of those paths (`git diff
    origin/main -- backend/ ops/ status/BACKLOG.md status/backend.md` empty)
    and that no `ios-shell`-owned path was touched by the merge. Pushed the
    merge commit (`fc57a67`) to `ios-staging`.
  - Re-swept all 100 `origin/claude/*` branches for stranded `ios-shell` work
    per the integrate-before-you-start rule (`git rev-list --count
    origin/ios-staging..<branch> -- ios-shell-owned paths`): 44 candidates
    show a nonzero count, but every one checked by actual diff content
    (`determined-thompson-*` ×24 identical net-deletion pattern,
    `peaceful-mccarthy-*` ×6, `wizardly-thompson-{0g9i90,eurlj6}`,
    `hopeful-johnson-{3xcwg7,bdpy3r,icvqmr}`, plus the long-known
    `coffee-app-plan-9jdh0c`/`new-app-infrastructure-setup-h3r3wz`/
    `relaxed-thompson-ceai5p`/`modest-newton-oxaddt`/
    `mycoffee-publish-autopilot-rv8cve`/`lanes-status-blockers-wws2lc`) is a
    pure net-deletion against current `ios-staging` — stale pre-#22/#41/#46
    snapshots, same pattern every prior sweep has found. Nothing stranded to
    adopt. Stopping cleanly rather than inventing work or touching
    UX-owned paths.

- [2026-08-16 UTC] Session check — no ready `ios-shell` row. #17/#22/#41/#46
  remain the only rows tagged `ios-shell`, all `done`. The #50 cross-tab seam
  (`CoffeeStore.selectedTab`/`RootTab`, `47f2934`) is confirmed fully consumed —
  #50/#52/#53/#54/#55 are all `done` on `origin/ios-staging`. `#57` (ios-ux,
  ready, "persisted rotate photo") names a shell piece (`CoffeeImage`/detail
  model field + API surface for a per-photo `rotation_quarter_turns`), but it
  depends on a backend column + write endpoint + snapshot field that don't
  exist yet — no backend row is even filed for that half — so there is nothing
  concrete for this lane to build against yet; picking a wire shape blind would
  just be guessing. `#58` (ios-ux, search-bar placement) and `#59` (data, EXIF
  fix) are outside this lane's owned paths.
  - **Found and fixed a real data-integrity bug while merging `origin/main` in**:
    the merge duplicated the entire `#56`–`#59` table block (two copies of
    `#56`/`#58`/the dup-note, and two different versions of `#57` — an older
    "view-only, scope question for Radu" row and the newer "persistence
    required" row that supersedes it after Radu's follow-up directive). Git's
    line-based merge didn't recognize the two `#57` texts as the same logical
    row, so it kept both instead of replacing. Deduped by removing the stale
    block and keeping the newer `#57` (Radu's persistence directive is later
    and explicit: "I need a permanent fix. So rotate should save."). Verified
    afterward that every row number 1–60 now appears exactly once in the table.
  - Swept `git branch -r --list 'origin/claude/*'` (98 candidates after
    fetching): sampled the highest commit-ahead-count candidates in this
    lane's owned paths (`confident-cerf-{01kgu0,0ol0nh,r7skfk}`,
    `relaxed-thompson-uq5f21`, all showing 8 commits ahead) and confirmed by
    `git diff --stat` they're pure net deletions (296 lines removed, 7 added,
    against `MutationOutbox`/`SyncEngine`/`RemoteCoffeeRepository`) — stale
    pre-batch-edit snapshots, same pattern every prior sweep has found.
    Nothing stranded to adopt.
  - Merged `origin/main` into `ios-staging`, resolving one additive conflict
    in `status/backend.md` (backend's own `#60` session-check entry landing
    independently on each branch — kept both, no factual conflict, same as
    prior sessions' precedent for this exact file).
  - Stopping cleanly rather than inventing work or touching UX/backend/data-owned paths.

- [2026-08-15 UTC, later session] Session check — no ready `ios-shell` row. #17/
  #22/#41/#46 are all `done`; the seam this lane added for #50 on 2026-08-14
  (`CoffeeStore.selectedTab`/`RootTab`, `47f2934`) has since been fully consumed
  by ios-ux — #50/#53/#54/#55 all landed `done` on `origin/ios-staging` before
  this session started (`348b8cc`, `8cbeb5c`, `06dd1aa`), confirmed by reading
  `Sources/Store/CoffeeStore.swift` and `Features/Root/RootTabView.swift`
  directly rather than trusting `BACKLOG.md`'s text alone. Only `ready` rows in
  the whole backlog are `#29` (data), `#57`/`#58` (ios-ux) — none name a
  shell-owned gap (`#57` even flags persistence as a *possible* cross-lane
  pull into shell, but only if Radu opts into that over the default
  view-only scope, which hasn't happened). Checked `git branch -r --list
  'origin/claude/*'`: only this session's own fresh branch exists, 0 commits
  ahead of `ios-staging` in any owned path — nothing stranded to adopt. Merged
  `origin/main` into `ios-staging` (clean, no conflicts — backend's #51/#56
  session-check and code commits) before stopping. Stopping cleanly rather
  than inventing work or touching UX-owned paths.

- [2026-08-15 UTC] Session check — no ready `ios-shell` row. Only rows tagged
  `ios-shell` are #17/#22/#41/#46, all `done`. Both `ready` rows this cycle,
  #29 (data) and #51 (backend, wiring #48(b)'s caption-city override into
  `worker.js`), are outside this lane's owned paths. #50 (ios-ux)'s shell seam
  (`CoffeeStore.selectedTab`/`RootTab`) is already landed (`47f2934`) and
  already consumed by ios-ux's own #50 commit (`348b8cc`) — verified by
  reading `Sources/Store/CoffeeStore.swift` directly, not just the row text.
  `ios-staging` and `main` had diverged the usual way (this lane's #50 seam
  landed on `ios-staging` while data's #48(b)/#51 landed on `main`, neither
  branch aware of the other) — merged `origin/main` into `ios-staging`
  (`96e3f24`, clean auto-merge, no conflicts) to reconcile `status/BACKLOG.md`
  and pick up #48(b)/#51. Re-swept all 92 `origin/claude/*` branches for
  stranded work in this lane's owned paths per the integrate-before-you-start
  rule: 68 candidates show nonzero commits ahead, but every naming cluster
  sampled (`confident-cerf-*`, `determined-thompson-*`, `peaceful-mccarthy-*`,
  `hopeful-johnson-*`, `modest-newton-*`, plus the long-known
  `coffee-app-plan-9jdh0c`/`new-app-infrastructure-setup-h3r3wz`/
  `wizardly-thompson-0g9i90`) diffs as a **net deletion** against current
  `ios-staging` — pre-#42/#46-era snapshots missing `MutationOutbox`/
  `SyncEngine`/`RemoteCoffeeRepository` work that's since landed, not new work
  to adopt. Nothing stranded. Stopping cleanly rather than inventing work or
  touching UX/backend/data-owned paths.

- [2026-08-14 UTC] Seam for #50 (ios-ux) — `CoffeeStore.selectedTab` — branch `ios-staging`
  - No `ios-shell`-tagged row was `ready` this cycle (`#29`/`#48` are data-owned). But `#50`
    (ios-ux, ready, needs 46 — done) explicitly names a gap in a shell-owned file: tapping an
    Insights legend label needs to both set `CoffeeStore.filter` (already writable — no shell
    work needed there) *and* switch `RootTabView`'s active tab to Coffees, and there is
    currently no tab-selection surface at all — `RootTabView.swift`'s `TabView` has no
    `selection:` binding. The row's own text asks shell to claim this seam if a surface has
    to be added; picked it up instead of stopping on a no-op session, same precedent as the
    2026-08-06/08-11 entries below (`loadBrief()`, `editCoffeeFields`).
  - Added `enum RootTab { case coffees, insights, review }` + `@Published var selectedTab:
    RootTab = .coffees` to `Sources/Store/CoffeeStore.swift`, next to `filter`/`sort` (same
    seam pattern the file's own doc comment describes — shell publishes, UX consumes).
  - **UX lane: wiring, not new plumbing.** `RootTabView.swift`'s `TabView` needs a `selection:
    $store.selectedTab` binding plus a `.tag(RootTab.x)` on each of the three tab views; the
    Insights tap handler for #50(b) then sets `store.filter`/`unknownDimensions` and
    `store.selectedTab = .coffees` in the same action. Not making this change myself —
    `Features/Root/**` and `Features/Insights/**` are UX-owned.
  - No `BACKLOG.md` row number for this (not new scope, just unblocking a flagged seam in an
    already-owned file) — left `#50`'s own row text as the pointer, per the "no invented
    scope" convention this file already follows.
  - Not locally compiled (no Xcode here) — a 9-line addition (one enum, one `@Published`
    property) to a file that already compiles, so a red compile check here would be a typo.
  - `ios/MyCoffee/Sources/Store/CoffeeStore.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-14 UTC] Session check — no ready `ios-shell` row. Only rows tagged
  `ios-shell` are #17/#22/#41/#46, all `done`. All `ready` rows this cycle are
  data-owned (#29, #48(b)) or backend-owned (#49) — nothing in
  `Sources/{App,Store,API,Models,Query,Utilities}` or `project.yml` to pick up.
  Checked `git branch -r --list 'origin/claude/*'` per the
  integrate-before-you-start rule: only stranded branch is this session's own
  (`claude/wizardly-thompson-1bgub6`), 0 commits ahead of `ios-staging` in any
  owned path — nothing to adopt. Merged `origin/main` into `ios-staging`
  (`e09c928`) to pick up backend's #39/#49 and data's #48(a) — resolved one
  additive conflict in `status/backend.md` (two same-day backend session-check
  entries; kept both) and picked up the accompanying `status/BACKLOG.md`/
  `status/data.md` changes cleanly. No code changes this session — stopping
  cleanly per the work loop rather than inventing work.

- [2026-08-13 UTC, later session] Session check — no ready `ios-shell` row.
  Only rows tagged `ios-shell` are #17/#22/#41/#46, all `done`. Found `main`
  had moved strictly ahead of `ios-staging` since the earlier session today —
  `git merge-base origin/main origin/ios-staging` equaled `origin/ios-staging`'s
  own tip, i.e. `main` had already merged `ios-staging` in and then added data
  lane commits on top (`#48(a)` migration `015_fix_uncommon_roaster_country.sql`,
  a new AppIcon, `status/BACKLOG.md`/`status/backend.md` updates) — the opposite
  direction from the usual "ios-staging is stale" case, so checked
  `git merge-base`/`git rev-parse` explicitly rather than assuming which side
  needed the merge. `git merge origin/main` into `ios-staging` was a clean
  fast-forward (`14b0e34..fb86696`), no conflicts. Post-merge, the only `ready`
  rows in `BACKLOG.md` are `#29`/`#48`/`#39`, all `data`-tagged — confirmed none
  are `ios-shell`. Re-swept all 85 `origin/claude/*` branches per the
  integrate-before-you-start rule: 44 show nonzero commits ahead in this lane's
  owned paths, but every one sampled (`determined-thompson-*`, `confident-cerf-*`,
  `peaceful-mccarthy-*`, `hopeful-johnson-*`, `wizardly-thompson-*`, plus the
  known scaffolding branches) diffs as a large net deletion (e.g. `33 files
  changed, 1 insertion(+), 2746 deletions(-)`) against current `ios-staging` —
  stale pre-#22/#41 snapshots, not new work. Nothing stranded to adopt. Pushed
  the fast-forward merge to `ios-staging`. Stopping cleanly rather than
  inventing work or touching UX-owned paths.

- [2026-08-13 UTC] Session check — no ready `ios-shell` row. #17/#22/#41/#46 are all
  `done` (this session's own designated branch had a stale copy of `status/BACKLOG.md`
  showing #41/#46 as `ready` — checking out `origin/ios-staging` directly showed both
  already landed, `81ac0b9`/earlier, with #42/#47 on top). Only `ready` rows remaining
  are `#39`/`#48`, both `data`-tagged (`normalize.js`/vocab-owned) — none for this lane.
  Merged `origin/main` into `ios-staging` to pick up backend's session-check commits
  (`4d0a771`/`f30b450`/`613176d`); resolved one additive conflict in `status/backend.md`
  (two session-check entries landing independently on each branch) by keeping both,
  no factual conflict. Re-swept all 83 `origin/claude/*` branches per the
  integrate-before-you-start rule: the two largest by ahead-count in this lane's owned
  paths (`wizardly-thompson-0g9i90`, `hopeful-johnson-3xcwg7`, both 6 commits ahead)
  diff as pure net-deletions (601 removed / 46 added, across `MutationOutbox.swift`,
  `CoffeeStore.swift`, `WhatsNewWire.swift`, etc.) — stale pre-#41/#46 snapshots, not
  new work. Nothing stranded to adopt. Stopping cleanly rather than inventing work or
  touching UX-owned paths.

- [2026-08-12 UTC, later session] 46 `whatsNew()` API surface (PLAN.md §13) — branch `ios-staging`
  - `APIClient.whatsNew() async throws -> WhatsNewResponseDTO` (`GET /api/whatsnew`), plus the new
    `API/Wire/WhatsNewWire.swift`: `WhatsNewResponseDTO{live, plan}`, `WhatsNewPlanDTO{byLane, needsApproval}`,
    `WhatsNewItemDTO{title, detail, area}` (`area` only populated on `live` items, `nil` on plan items — matches
    `backend/src/data/whatsnew.json`'s actual shape and `backend/test/whatsnew.test.js`'s assertions).
  - **Lenient decode**, per the row's own ask: every array (`live`, each `byLane` lane, `needsApproval`) decodes via
    `[FailableDecodable<WhatsNewItemDTO>].self.compactMap(\.value)` — the same `FlexibleDecoding.swift` helper the
    snapshot/review feeds already use — so one malformed curated card is dropped, never a fatal decode that blanks
    the whole screen.
  - Session first checked out `ios-staging` and discovered its own `status/BACKLOG.md` already had `#41`/`#42`
    marked `done` (landed 2026-08-11/12) while `main`'s copy — this session's merge source — still showed `41
    ready`/`42 blocked`; merging `origin/main` in also surfaced that `main` had `#45` done and `#46` freshly flipped
    `blocked`→`ready`. Reconciled `status/BACKLOG.md`'s merge conflict by keeping `ios-staging`'s truth for #41/#42
    (done) and `main`'s truth for #45/#46 (done/ready) rather than picking one side — same "each branch is stale
    about the other's lane" pattern prior sessions have hit, not a new code conflict. Pushed that reconciliation
    (`8d9a3c7`) before starting #46's actual code.
  - Also swept all 80 `origin/claude/*` branches for stranded ios-shell work per the integrate-before-you-start
    rule: every candidate that touches this lane's owned paths (`confident-cerf-*`, `determined-thompson-*`,
    `hopeful-johnson-*`, `peaceful-mccarthy-*`, plus the four already-known stale ones) diffs as a **net deletion**
    against current `ios-staging` — pre-#22/#41 snapshots missing work that's since landed, not new work to adopt.
    Nothing stranded.
  - Not locally compiled (no Xcode here) — new file mirrors `ReviewWire.swift`'s exact shape (custom
    `CodingKeys`-based `init(from:)`, `FailableDecodable` for every array), so a red compile check should point at
    a typo, not a design gap.
  - Scope stayed inside `API/` per the row's own note (no `CoffeeStore`/`CoffeeRepository` wrapper) — unlike `#41`'s
    `editField`, this one has no offline-mutation angle, and `#28`'s `loadBrief()` precedent shows a bare
    `APIClient` call is an accepted shape for a UX view to call directly from a `.task`; not inventing a `CoffeeStore`
    method the row didn't ask for.
  - `ios/MyCoffee/Sources/API/{APIClient,Wire/WhatsNewWire}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-12 UTC] No open `BACKLOG.md` row for `ios-shell` this cycle — `#41` (this
  lane's only other row besides `#17`/`#22`) was already `done` on `ios-staging`
  (`5b76a6c`, 2026-08-11), and `#42` (ios-ux) had already landed on top of it
  (`be0b40a`, same day). This session initially claimed `#41` off `main`'s stale
  copy of `status/BACKLOG.md` — `main` still showed `41 ready`/`42 blocked` because
  the dev/ship split means `ios-staging` never pushes its `status/BACKLOG.md`
  updates to `main` until the Publish lane merges; `ios-staging`'s own copy already
  read `done`/`done`. Retracted that claim once `git checkout ios-staging` surfaced
  the real state, rather than redoing already-landed work.
  - **Picked up a real, already-flagged, already-scoped gap instead of stopping**
    (same precedent as the 2026-08-06 entry below): `status/ios-ux.md`'s `#42`
    write-up flagged that the backend's batch `{edits:[...]}` endpoint (`#40`) has
    no client-side batch caller — `APIClient.editCoffeeField`/`CoffeeStore.editField`
    (`#41`) only expose one field per HTTP request, so `CoffeeEditSheet` fires one
    request per changed field with no ordering guarantee between them (e.g. an
    explicit `roasterCountry` edit racing the `roasterCountryId` a same-save
    `roaster` edit derives). UX's note named the exact ask: "an `APIClient.
    editCoffeeFields(publicId:edits:)` + a matching `CoffeeStore` batch wrapper... 
    claim in both lane files per the seam rule if picked up." Closed it:
    - `APIClient.editCoffeeFields(publicId:edits:)` → the same `POST
      /api/coffees/:id/edit` route, body `{edits:[{field,value},...]}` instead of
      `{field,value}` — confirmed against `routes/coffees.js`: all edits resolve
      before the coffees row is written once, so a single 422 aborts the whole
      batch rather than partially applying.
    - New `CoffeeFieldEdit: Codable` (`{field, value}`) — shared by the API call,
      a new `PendingMutation.editBatch(coffeeId:edits:)` case (one outstanding
      batch per coffeeId, same replace-not-accumulate rule as `.edit`), and
      `MutationOutbox.enqueue/pendingEditBatch`. Extended both exhaustive
      `PendingMutation` switches (`isReviewMutation`, `shouldKeep`) — `shouldKeep`
      reuses the existing 4xx-drops/5xx-retries split unchanged.
    - `SyncEngine.editFields` mirrors `editField`'s queue→flush→re-fetch-detail
      shape; `CoffeeRepository.editFields` + `RemoteCoffeeRepository`/
      `SampleCoffeeRepository` (no-op, same reasoning as `editField`'s) conform;
      `CoffeeStore.editFields(coffeeId:edits:)` is the call the edit sheet should
      switch to whenever `edits.count > 1`.
  - **UX lane: one call-site swap, not new plumbing.** `Features/Coffees/
    CoffeeEditSheet.swift`'s save currently fires `store.editField(...)` once per
    changed field. When more than one field changed in the same save, swap that
    loop for one `store.editFields(coffeeId:edits:)` call instead — the atomicity
    fix only takes effect once the sheet stops calling the single-field path in a
    loop. Not making this swap myself — `Features/Coffees/**` is UX-owned.
  - No new `BACKLOG.md` row (not a numbered issue, just closing a flagged gap in
    already-owned files — same as the 2026-08-06 entry's precedent); added a
    pointer in `BACKLOG.md`'s `#42` row + "Right now" section instead so the UX
    lane sees it without reading this file.
  - Not locally compiled (no Xcode here) — every new piece mirrors `editField`'s
    existing shape 1:1, so a red compile check should point at a typo, not a
    design gap.
  - `ios/MyCoffee/Sources/{API/APIClient,Store/CoffeeRepository,Store/CoffeeStore,
    Store/MutationOutbox,Store/RemoteCoffeeRepository,Store/SampleCoffeeRepository,
    Store/SyncEngine}.swift`
  - Commit: (see `git log` on `ios-staging`)


- [2026-08-11 UTC, later session] Session check — no ready `ios-shell` row.
  Only `ios-shell` rows in `BACKLOG.md` are #17/#22/#41, all `done` (#41
  landed earlier this same day, `5b76a6c`, and its dependent #42 (ios-ux) is
  also already `done`, `be0b40a`). Checked `git branch -r --list
  'origin/claude/*'` per the integrate-before-you-start rule: the only
  candidate is this session's own branch
  (`origin/claude/wizardly-thompson-lv7do1`), which carries no unmerged
  `ios-shell`-owned work (its one commit, the "Year bought" label fix, is
  already on `main`/`ios-staging`). Merged `origin/main` into `ios-staging`
  (clean, no conflicts — backend's session-check commit plus two `ios-ux`-owned
  file tweaks) before stopping. Only other `ready` row in the whole backlog is
  `#39` (data lane, `normalize.js` altitude/weight/rating sanity envelopes) —
  out of this lane's scope. Stopping cleanly rather than inventing work or
  touching UX-owned paths.

- [2026-08-11 UTC] 41 Edit API surface (PLAN.md §12) — branch `ios-staging`
  - `APIClient.editCoffeeField(publicId:field:value:)` → `POST /api/coffees/:id/edit`, same
    raw-string-in shape as `resolveReview` (checked `resolveField.js`'s `canonicalize()`: every
    field case runs the raw value through a string parser — `parseAltitude`/`parsePrice`/
    `resolveVocab`/etc — so there's no structured-value shape to bridge, unlike the review DTOs).
  - `MutationOutbox` gets a fourth `PendingMutation` case, `.edit(coffeeId:field:value:)`, with
    `enqueueEdit`/`pendingEdit` mirroring `enqueueFavorite`/`pendingFavorite` (one outstanding
    edit per `(coffeeId, field)`, replace-not-accumulate) and a `shouldKeep` branch that falls
    into the existing 4xx-drops/5xx-retries split for free — a 422 (unresolvable value, e.g. an
    unknown country) is exactly as terminal as `resolveReview`'s.
  - `SyncEngine.editField` queues + flushes like `setFavorite`, then — the one real difference
    from favorite/review — re-fetches detail on success via the existing `loadDetail`, since an
    edit's backend-derived side effects (e.g. editing `roaster` also derives `roasterCountryId`)
    can't be guessed at locally the way a favorite bool can. Returns `nil` while still queued
    (offline) or rejected (422 — the row didn't change, nothing new to merge).
  - `CoffeeRepository.editField` protocol method; `RemoteCoffeeRepository` delegates to the
    engine; `SampleCoffeeRepository`'s is a no-op returning `nil` (same reasoning as its
    `resolveReview`/`dismissReview` no-ops — duplicating the backend's canonicalization in the
    fixture isn't this lane's job). `CoffeeStore.editField(coffeeId:field:value:)` is the
    fire-and-forget wrapper the UX lane's edit sheet (#42) will call; merges the refreshed
    `Coffee` into `index` via `replacingCoffee` on success, same as `loadDetail(for:)`.
  - Not locally compiled (no Xcode here) — everything is a straight mirror of `setFavorite`'s/
    `resolveReview`'s existing shapes, so a red compile check should point at a typo, not a
    design gap.
  - `ios/MyCoffee/Sources/{API/APIClient,Store/CoffeeRepository,Store/CoffeeStore,
    Store/MutationOutbox,Store/RemoteCoffeeRepository,Store/SampleCoffeeRepository,
    Store/SyncEngine}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-10 UTC, later session] Session check — no ready `ios-shell` row.
  #17/#22 remain the only rows tagged `ios-shell`, both `done`; the only
  `ready` row in the whole backlog is `#39` (data lane, `parseAltitude`/
  `parseWeight`/`parseRating` sanity envelopes) — not shell-owned. Merged
  `origin/main` into `ios-staging` (clean, no conflicts). Swept
  `git branch -r --list 'origin/claude/*'`: only this session's own branch
  exists, touching no `ios-shell`-owned path — nothing stranded to adopt.
  **One real, already-flagged fix picked up instead of inventing work**:
  `status/ios-ux.md`'s 2026-08-06 entry flagged `Store/ImageStore.swift`'s
  doc comment as stale (it said "Not yet wired into `Thumbnail.swift`" and
  "no batch-media-URL endpoint exists yet"), left for this lane since the
  file is shell-owned. Both premises are now false — `Thumbnail.swift` calls
  `ImageStore.shared.thumbnail(for:maxPixelSize:)` directly, and the compact
  snapshot row (`toCompactCoffee` in `backend/src/routes/coffees.js`) has
  carried a signed `thumbUrl` since `SNAPSHOT_VERSION=2`, so no separate
  batch endpoint was ever needed. Updated the comment to describe the real,
  already-wired state instead of a stale gap. No compile risk — comment-only
  change to a shell-owned file, no signature/behavior touched.
  - `ios/MyCoffee/Sources/Store/ImageStore.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-10 UTC] Session check — no ready `ios-shell` row. #17/#22 remain the
  only rows tagged `ios-shell`, both `done`. Merging `origin/main` into
  `ios-staging` surfaced a real divergence, not just stale session-check
  noise: `ios-staging` still carried `#37` (ios-ux) `done`/`#38` (data)
  `ready`, while `main` had the reverse — `#37` `ready`/`#38` `done` (the data
  lane's 2026-08-10 roaster-country migration). Resolved the `status/
  BACKLOG.md` conflict as the union of both branches' newer knowledge (`#37`
  done, `#38` done) rather than picking one side, since each branch was
  correct about the row it actually has direct knowledge of. No `ios-shell`
  row unblocks from this — neither `#37` nor `#38` lists `ios-shell` as a
  dependent. Re-swept all 69 `origin/claude/*` branches for stranded work in
  this lane's owned paths (`git rev-list --count origin/ios-staging..<branch>
  -- ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities}
  ios/project.yml`): 17 candidates show nonzero commits ahead, but every one
  diffs as a **net deletion** against current `ios-staging` (pre-#22 or
  pre-#17 snapshots missing files #22 later added) — confirmed by `git diff
  --stat`, not just the commit count. Nothing stranded to adopt. Pushed the
  merge commit (`e66cd10`) to `ios-staging`. Stopping cleanly rather than
  inventing work or touching UX-owned paths.

- [2026-08-09 UTC] Session check — no ready `ios-shell` row. #17/#22 are the
  only rows tagged `ios-shell`, both `done`. #37 (ios-ux, needs 35/36 — both
  `done`) is the only `ready` row in the whole backlog and is UX-owned, not
  shell-owned; #29 (data, phase 6) still `blocked` on #26, still `human`.
  Re-fetched all `origin/claude/*` branches (65 candidates) and swept each
  with `git diff --stat origin/ios-staging..<branch> -- <ios-shell-owned
  paths>` per the integrate-before-you-start rule: 17 candidates showed a
  nonzero `rev-list --count`, but every one of those diffs as a **net
  deletion** against current `ios-staging` (missing `SyncEngine.swift`/
  `CoffeeCoding.swift`/`PlainDate.swift`/etc. that #22 later added, or
  pre-rename shapes like `JSONDecoder+Coffee.swift`) — i.e. each is a stale
  pre-#22 snapshot being diffed backwards, not new work ahead. Nothing
  stranded to adopt. Merged `origin/main` into `ios-staging` (`52ddd23`,
  clean — two other lanes' status-only session-check commits, no code)
  before stopping. Stopping cleanly rather than inventing work or touching
  UX-owned paths.

- [2026-08-08 UTC, later same day] Session check — still no ready
  `ios-shell` row. Since the earlier check below, Radu's accept-by-default
  directive landed on `main` (`aaacc88`, merged in via `git merge origin/main`
  — no conflicts) adding `BACKLOG.md` #35/#36 (backend, both `ready` not
  `done` yet) and #37 (`ios-ux`, `blocked` on 35/36) — none of that is
  ios-shell-owned or unblocked. Re-swept `origin/claude/*` for stranded work
  in this lane's owned paths: only new candidate is this session's own branch
  (`wizardly-thompson-ofd9vn`), zero prior commits, nothing to adopt.
  Confirmed the 2026-08-05 "decode leniently" follow-up (skip a malformed
  snapshot row instead of failing the whole array) is already resolved —
  `de55557` added `FailableDecodable` and applied it to `SnapshotWire.swift`'s
  `coffees`/vocab arrays. Stopping cleanly; pushing the merge to
  `ios-staging`.

- [2026-08-08 UTC] Session check — no ready `ios-shell` row. Only ios-shell
  rows are #17/#22, both `done`. #26 (data, phase 4) is still `human`
  (Radu's 5-photo accuracy verdict still pending — confirmed via today's
  backend-lane session check, which independently re-verified the same
  state), so #29 (data, phase 6) stays `blocked`; nothing else in
  `BACKLOG.md` is tagged `ios-shell`. `git merge origin/main` into
  `ios-staging` pulled in one commit (`fc88d0e`, backend's own no-op session
  check touching only `status/backend.md`) — no conflicts, no shell-owned
  file changed. Re-fetched and swept all 61 `origin/claude/*` branches for
  stranded work in this lane's owned paths
  (`ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities}`,
  `ios/project.yml`): checked the three recurring nonzero-diff candidates
  plus the newest branches (`relaxed-thompson-wrqfk0`,
  `wizardly-thompson-eurlj6`) by actual diff content, not just commit count —
  `coffee-app-plan-9jdh0c` and `new-app-infrastructure-setup-h3r3wz` are both
  pure net-deletions (2465 lines removed, 1 inserted) against current
  `ios-staging`, i.e. stale pre-#17 scaffolding already superseded;
  `wizardly-thompson-0g9i90` is the same pre-`loadBrief()`/pre-`roasterId`-fix
  snapshot every prior sweep found (its diff deletes the review-feed/brief
  API methods and reverts `roasterId` back to non-optional); `wrqfk0` and
  `eurlj6` show zero commits ahead in owned paths. Nothing stranded to adopt.
  No cross-lane ask pending either — `status/ios-ux.md`'s only open item
  (the `/api/brief` wiring ask) was already closed by this lane's own
  2026-08-06 entry (`CoffeeStore.loadBrief()`). Stopping cleanly rather than
  inventing work; pushing the `origin/main` merge to `ios-staging` per
  CLAUDE.md §3.

- [2026-08-07 UTC, note from an `ios-ux` session, not this lane's own work]
  `origin/main` had advanced to `da12d12` ("iOS: listing photos, review
  scroll/back fixes, coffee-page cleanups") via another off-lane push straight
  to `main` — touched this lane's `API/Wire/{CoffeeMapping,SnapshotWire}.swift`
  and `Store/SyncEngine.swift` (mapping the snapshot's `thumbUrl` into
  `Coffee.images`) alongside `ios-ux`-owned files. The `ios-ux` session that
  ran that day merged it into `ios-staging` (`9b9fc95`) and reconciled one
  conflict (in a `ios-ux`-owned file only) — see `status/ios-ux.md`'s matching
  entry for detail. Recording it here too per the same precedent this file's
  own 2026-08-06 entry set ("recording it here too since this branch is where
  it originated"): nothing for this lane to do, `Store`/`API` content landed
  as-authored, no shell-owned conflict to resolve.

- [2026-08-07 UTC, later same day] Session check — unchanged from the check
  earlier today. No ready `ios-shell` row: #17/#22 done, #26 (data, phase 4)
  still `human` (Radu's 5-photo verdict pending), so #29 stays `blocked`.
  `ios-staging` already at `90834f4` (ios-ux's later no-op session merged
  `origin/main`'s `e0cfea2` in already) — nothing to merge. Re-swept all 59
  `origin/claude/*` branches (3 more than the earlier check's 56): same 7
  nonzero-diff candidates as before in this lane's owned paths
  (`coffee-app-plan-9jdh0c`, `hopeful-johnson-icvqmr`, `modest-newton-oxaddt`,
  `mycoffee-publish-autopilot-rv8cve`, `new-app-infrastructure-setup-h3r3wz`,
  `relaxed-thompson-ceai5p`, `wizardly-thompson-0g9i90`) — no new branches
  appeared since. Stopping cleanly rather than inventing work.

- [2026-08-07 UTC] Session check — no ready `ios-shell` row. Only ios-shell
  rows are #17/#22, both `done`. #26 (data, phase 4) is still `human`
  (awaiting Radu's 5-photo accuracy verdict), so #29 (data, phase 6) stays
  `blocked`. `git merge origin/main` into `ios-staging` was a no-op (already
  up to date — both at `e0cfea2`). Re-fetched and swept all 56
  `origin/claude/*` branches for stranded work in this lane's owned paths
  (`git rev-list --count origin/ios-staging..<branch> -- <ios-shell-owned
  paths>`): 7 showed a nonzero count (`coffee-app-plan-9jdh0c`,
  `hopeful-johnson-icvqmr`, `modest-newton-oxaddt`,
  `mycoffee-publish-autopilot-rv8cve`, `new-app-infrastructure-setup-h3r3wz`,
  `relaxed-thompson-ceai5p`, `wizardly-thompson-0g9i90`), but commit count is
  misleading across diverged histories, so checked actual file content: the
  same three pure-deletion/pre-fix-snapshot candidates as every prior check,
  plus unrelated publish/compile-lane branches that predate `ios-staging`'s
  creation, plus `hopeful-johnson-icvqmr` (an `ios-ux` branch) whose
  Store/API/Models files are byte-identical to what's already on
  `ios-staging` — its actual new content was `Features/Insights` wiring,
  already landed via `4e491be`. Nothing stranded to adopt. Stopping cleanly
  rather than inventing work or touching UX-owned paths.

- [2026-08-06 UTC, later same day] Session check — no ready `ios-shell` row.
  #17/#22 done; #27/#28 (ios-ux) done; #29 (data, phase 6) still `blocked` on
  #26, still `human` (awaiting Radu's verdict). The cross-lane `ios-ux` ask
  under `## Claimed` and the `loadBrief()` follow-up were already closed by
  an earlier session today (commit `ef50a07`, see the entry right below) —
  verified `## Claimed` is empty and the work is present on `origin/ios-staging`,
  so not redoing it. Swept `origin/claude/*` (55 candidates after fetch) for
  stranded work in this lane's owned paths: same three pure-deletion
  candidates as prior checks (`coffee-app-plan-9jdh0c`,
  `new-app-infrastructure-setup-h3r3wz`, `wizardly-thompson-0g9i90`), nothing
  new to adopt. Merged `origin/main` (2 backend session-check commits,
  `status/backend.md` only) into `ios-staging`, clean, no conflicts. The
  unclaimed leniency follow-up (decode `coffees` array skipping malformed
  rows instead of failing whole-array) stays flagged, not picked up — no
  backlog row, and inventing scope isn't this loop's job. Stopping cleanly.

- [2026-08-06 UTC] No open `BACKLOG.md` row for `ios-shell` (#17/#22 are the only rows and both `done`), but two
  legitimate, already-claimed cross-lane asks were still open, so picked those up instead of stopping — same
  precedent as the earlier review-feed wiring below.
  - **Closes the "Cross-lane request from `ios-ux`" claim above** (the `reviewItems`/`resolveReview`/`dismissReview`
    APIClient methods and the `CoffeeStore` wiring it also asked for already landed — see the off-lane-main-push
    note right below). What was still missing: `createReviewRule(kind:canonicalId:alias:)` (`POST /api/review/rules`,
    added to `APIClient.swift`) and the `.reviewResolve`/`.reviewDismiss` cases on `MutationOutbox`'s
    `PendingMutation` its doc comment reserved room for. Added both, plus `CoffeeRepository.resolveReview(taskId:
    value:)`/`.dismissReview(taskId:)` (both conformers — `RemoteCoffeeRepository` delegates to two new
    `SyncEngine` methods that enqueue-then-flush exactly like `setFavorite` does; `SampleCoffeeRepository`'s are
    no-ops, there's no review feed in the sample fixture) and `CoffeeStore.resolveReview(taskId:value:)`/
    `.dismissReview(taskId:)`, fire-and-forget wrappers mirroring `toggleFavorite`'s shape.
  - **One real bug caught while writing `MutationOutbox.flush`**: naively retrying every failed mutation forever
    (the existing `favorite` behavior) is wrong for `reviewResolve` — a 422 (the backend's documented response for
    a value it can't canonicalize) is a *terminal* rejection, not a transient one, and blind retry would hammer
    `/api/review/:id` every sync forever without ever succeeding. `flush` now drops any 4xx response instead of
    requeuing it (matches the fire-and-forget behavior it replaces: the item just stays open server-side for the
    next `GET /api/review` load) and only keeps genuinely transient failures (offline, 5xx) queued. This changes
    `favorite`'s retry behavior too (a 4xx there now also drops instead of retrying forever) — arguably a
    correctness fix there as well, not just added for review.
  - **UX lane: the wiring is one call-site swap, not new plumbing.** `Features/Review/ReviewQueueView.swift`'s
    `load()` currently does `Task { try? await client.resolveReview(...) }`/`client.dismissReview(...)` directly
    against `APIClient`, bypassing the outbox entirely (the exact gap flagged in `status/ios-ux.md`). Swap those two
    calls for `store.resolveReview(taskId:value:)`/`store.dismissReview(taskId:)` on the shared `CoffeeStore`
    instance (already available via `.environmentObject` per `RootTabView`) and persistence survives offline/app
    restart. Not making this swap myself — `Features/Review/**` is UX-owned.
  - Also added `CoffeeStore.loadBrief() async -> Brief?` (`Models/Brief.swift` + `API/Wire/BriefWire.swift` +
    `APIClient.brief()`, decoding `GET /api/brief`'s `{ok, brief, message?}` envelope) — the ask `status/ios-ux.md`
    flagged under `#28`'s Insights writeup for the "This month" editorial section PLAN.md §6.4 wants. No local
    caching (mirrors `loadDetail`'s fetch-and-return shape, not `index`-published state, since a brief isn't part
    of the coffee snapshot). `Brief`'s wire shape and domain model are identical today (no NUMERIC-string or
    nullable-vs-required quirks to bridge), so `BriefResponseDTO` decodes straight onto `Brief` rather than adding
    a parallel DTO type.
  - Not locally compiled (no Xcode here) — if the next compile check goes red, check `MutationOutbox.swift`'s
    `shouldKeep` pattern-match on `APIClient.APIError.http` first; everything else is a straight mirror of
    `setFavorite`'s existing shape.
  - `ios/MyCoffee/Sources/{API/APIClient,API/Wire/BriefWire,Models/Brief,Store/CoffeeRepository,Store/CoffeeStore,
    Store/MutationOutbox,Store/RemoteCoffeeRepository,Store/SampleCoffeeRepository,Store/SyncEngine}.swift`
  - Commit: (see `git log` on `ios-staging`)

- [2026-08-06 UTC] **Note on the off-lane push to `main`, not new work**: this session's designated branch
  (`claude/wizardly-thompson-1zauox`) already carried two real commits pushed straight to `origin/main` from an
  earlier turn in this same session (`de55557`/`63ac9a5`/`9bb27d6` — the Country.isoCode empty-shell fix and the
  Review-tab wiring), crossing lane boundaries (one of the three touched `backend/src/routes/review.js`, backend-
  owned) and bypassing the `ios-staging` dev/ship split entirely (CLAUDE.md §5, §12's "never push `ios/**` to
  `main`"). **Already caught and reconciled by a later `ios-ux` session** (`status/ios-ux.md`'s 2026-08-05 entry,
  commit `6d5bedc` on `ios-staging`) before this session started — verified tree-identical, nothing lost, nothing
  to redo. Recording it here too since this branch is where it originated, for anyone auditing why `main`'s history
  briefly had `ios/**` commits on it. Not repeating the mistake: this session's work above went straight to
  `ios-staging`.

- [2026-08-05 UTC, later same day] Session check — unchanged from the check
  below. Still no ready `ios-shell` row: #17/#22 done, #27/#28 (ios-ux) done,
  #29 (data, phase 6) still `blocked` on #26, which is still `human`
  (awaiting Radu's accuracy verdict on the 5-photo sample per the spend
  gate). Re-swept all `origin/claude/*` branches (49 candidates) for
  stranded work in this lane's owned paths — same four candidates as the
  prior check (`coffee-app-plan-9jdh0c`, `new-app-infrastructure-setup-h3r3wz`,
  `confident-cerf-yylzob`, `wizardly-thompson-0g9i90`), and confirmed by tree
  diff (not just commit-ancestry count) that none carry new work: the first
  two are pre-#17 scaffolding superseded by later commits, `wizardly-
  thompson-0g9i90` is a pre-`roasterId`-fix snapshot, and `confident-cerf-
  yylzob` is tree-identical to `ios-staging` (its commit already landed
  there under a different SHA). `git merge origin/main` pulled in
  `deb313c`/`de55557` (backend's session check + the same empty-shell fix,
  already present on `ios-staging` since `f43e4c4` — tree-identical, no
  conflict) — pure history reconciliation, no new file changes. Stopping
  cleanly; not re-litigating the leniency follow-up flagged below, still
  unclaimed and still not blocking anything.

- [2026-08-05 UTC] Session check — no ready `ios-shell` row. #17/#22 are
  `done`; #27/#28 (ios-ux, needing #22/#24) are now also `done`; #29 (data,
  phase 6) needs #26, still `human`. Re-fetched all `origin/claude/*`
  branches (45 candidates) and swept each with `git rev-list --count
  origin/ios-staging..<branch> -- <ios-shell-owned paths>` per the
  integrate-before-you-start rule: `coffee-app-plan-9jdh0c` and
  `new-app-infrastructure-setup-h3r3wz` both diff as pure deletions (they
  scaffold the same files #17 later superseded); `wizardly-thompson-0g9i90`
  is a stale pre-fix snapshot of `Coffee.swift`/wire files predating the
  `roasterId` fix below. Nothing stranded to adopt. `git merge origin/main`
  into `ios-staging` was a no-op (already up to date).
  - **Documentation gap closed, not new code**: commits `16814c3` ("Fix empty
    Coffees shell: roasterId is nullable, was decoded as required") and
    `55031b9` ("Fix build: make the DTO roasterId properties optional too")
    are already on `origin/ios-staging` (Radu's first real-data build showed
    zero coffees because `CompactCoffeeDTO`/`CoffeeDetailDTO` decoded
    `roasterId` as a required `Int`, and the compact snapshot legitimately
    sends `roasterId: null` for coffees whose roaster isn't resolved yet —
    one null row threw and dropped the whole all-or-nothing array decode).
    That prior ios-shell session (`session_01JLFd9wZxpbWRZ959RrcSM3`) never
    recorded it here, so this file understated what's landed. Recording it
    now for the next session's accuracy, per `status/README.md`'s
    "correcting a task means correcting this file" rule.
  - **Follow-up flagged in that commit's own message, not done here** (no
    backlog row, and this session found no other ios-shell work to bundle it
    with): decode the `coffees` array in `SnapshotWire`/`CoffeeDetailWire`
    leniently — skip a single malformed row instead of failing the whole
    array — so no future nullable/malformed field can blank the entire app
    again. Flagging rather than guessing scope for an unclaimed hardening
    task.
  - No commit needed for the sweep itself; the fix above is already merged.

- [2026-08-04 UTC] Session check — no ready `ios-shell` row. Only ios-shell
  rows are #17 and #22, both `done`. The only other iOS-adjacent row, #27
  (ios-ux, phase 5), needs #22 (done) + #24 (backend, still `blocked` on #23
  — unstarted). Fetched all `origin/claude/*` branches (34 candidates,
  including this session's own `claude/wizardly-thompson-0g9i90`) and swept
  each with `git rev-list --count origin/ios-staging..<branch> --
  ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities} ios/project.yml`
  per the integrate-before-you-start rule: every one shows `0` commits ahead
  in this lane's owned paths — nothing stranded to adopt. Merged
  `origin/main` into `ios-staging` (clean, no conflicts — just backend's
  latest session-check commit) before stopping. Stopping cleanly rather
  than inventing work or touching UX-owned paths.

- [2026-08-03 UTC] Session check — no ready `ios-shell` row. Only ios-shell
  rows are #17 and #22, both `done`. `#27` (ios-ux, phase 5) needs #22 (done)
  + #24 (backend, still `blocked` on #23, which is unstarted). Swept every
  `origin/claude/*` branch (`git rev-list --count origin/ios-staging..<branch>
  -- ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities} ios/project.yml`)
  across all 27 candidates fetched fresh this session — every one shows `0`
  commits ahead in this lane's owned paths, so nothing stranded to adopt.
  Merged `origin/main` into `ios-staging` to pick up backend's session-check
  commits; resolved one additive conflict in `status/backend.md` (two backend
  session-check entries for the same UTC day) by keeping both, no factual
  conflict. Stopping cleanly rather than inventing work or touching
  UX-owned paths.

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

- [2026-08-04 00:00 UTC] No open backlog row for `ios-shell` (only #17/#22 exist for this
  lane and both are `done`). Merged `origin/main` into `ios-staging` to pick up backend
  #23/#24/#25 and resolve a `status/BACKLOG.md` divergence: `ios-staging` didn't know
  `main` had promoted #25→`done`/#26→`human`; `main` didn't know `ios-staging` already
  had #22/#27/#28 done. Reconciled the table + prose (no code conflicts — the only
  conflicting file was `status/BACKLOG.md`) and pushed to `ios-staging`. No new
  `ios-shell`-owned code this session — not inventing work per the loop's own rule.
  - Commit: `5dec242` (merge), on `ios-staging`

## Abandoned

_none_
