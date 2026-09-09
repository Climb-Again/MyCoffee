# Lane: iOS UX

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-ux-history.md`](archive/ios-ux-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## Abandoned

_none_

## Session notes

- **2026-09-09 — #186 value band depth ramp, off-cycle fire (Radu asked for
  this run specifically to catch the 2026-09-10 20:00 UTC publish).**
  `VALUE_BAND_UPDATE.md`'s blue table, exactly: `Theme.Colors` gained five new
  adaptive tokens (`valueOverpaid`/`valuePoor`/`valueFair`/`valueGood`/
  `valueGreat`, light hexes from the spec, dark hexes the row's own
  contrast-checked default) plus `Theme.Weight.bold` (700, GREAT VALUE only —
  every other verdict stays `semibold`). `CoffeeRowView` and
  `CoffeeDetailView` each got a local `bandColor(_:)` (verbatim-copied, same
  as the `valueMeter`/`verdictLabel` pair they sit beside — #181 will absorb
  all three together) replacing the old `Band.isPositive ? accent :
  neutral700` two-tone split; the unlit track is now the band's own tone at
  15% opacity instead of a fixed `neutral300`. Value logic untouched —
  `CoffeeIndex.valueBand(for:)`, thresholds and suppression are byte-for-byte
  as they were, only `bandColor`'s output changed. `Band.isPositive`
  (`CoffeeIndex.swift:42`, shell-owned) now has no caller; left in place
  unused per the row's own note rather than touching a shell file for this.
  Did not touch #181 (dedupe) or any other ready row this run — Radu's fire
  instruction scoped this session to #186 alone.

- **2026-09-09 — #141-#148 coffee-page header redesign + roaster-page
  cleanup, `HEADER_UPDATE.md`. Landed `aea6542`, compile-green on run #106
  (queued at 11:02 UTC, success by 11:04).** #141 bare white photo controls
  (heart/share/edit) with the old capsule/chip removed; the back chevron is
  deliberately left as the system button rather than rebuilt as a fourth
  overlay control — a custom overlay back button is the documented cause of
  a past edge-swipe-back/duplicate-arrow regression (see the file's own doc
  comment), so this is a known, deliberate partial gap against §1's exact
  spec. #142 new `DesignSystem/RoasterLogoTile.swift` — the 86×86 rounded-
  square medallion shared by the coffee page and the roaster page, with a
  "use the mark not the lockup" crop: since there's no per-roaster crop
  metadata and no vision framework in play, wide (lockup-shaped) logos get
  a leading-square crop heuristic rather than true bounding-box detection —
  documented as an approximation, not a promise of pixel-perfect mark
  isolation. #143 sheet order is now roaster row → title → rating. #144
  fractional star fill generalizes to any rating via `rating - index`
  clamped 0...1, not a fifth-star special case. #145 new
  `Features/Coffees/RoasterFactParser.swift` for the FROM THE ROASTER grid
  — label-first, then a named-keyword sniff (the exact four keywords named
  in the row) for whichever fact wasn't labelled; falls through to the
  plain excerpt whenever fewer than two facts land, so a parser miss never
  breaks the page. #146: grepped the whole app for `.shadow(`/`themeShadow`
  before touching anything — found **zero** shadows anywhere, so the
  "exactly three" audit was really "add exactly two" (photo controls +
  medallion); nothing to remove. #147: (a) the "rail renders twice" and (c)
  "custom capsule tab bar" complaints are **already fixed** by earlier
  work — verified against current source, only one `ForEach(rails)` call
  site exists (`CoffeeDetailView.railsSection`), and `RootTabView` has used
  a native `TabView` since the v3 redesign (`fae4cf4`). Treating those two
  as stale carryover in the handoff doc rather than reopening non-bugs; (b)
  is real and fixed — added a fixed 84pt trailing spacer after the rails so
  the last one clears the tab bar rather than sitting flush against it (no
  API here for the live bar height, so this is a constant approximation of
  "bar height + 16pt", not measured). #148: roaster page now uses the same
  `RoasterLogoTile` (never a circle, no monogram fallback — deleted
  `DesignSystem/MonogramAvatar.swift`, confirmed zero remaining call
  sites), markdown-strips the blurb via new
  `Features/Insights/EntityPages/RoasterBlurbParser.swift` (bold spans +
  `- **Label** — text` bullets rendered as §5's label/value row pattern),
  and the star/rating is accent blue instead of orange.
  **Not verified visually** — no bundled sample roaster carries a
  `logoUrl`/`blurb` (`SampleData.swift`, shell-owned, untouched), so the
  medallion crop and the blurb bullet rendering were never seen on-device
  or in a preview; compile-green is the only signal this session had.
  Flagging in case a future session wants to add a sample roaster with
  both fields for real visual QA of #142/#148. #149-#151 (Coffees list:
  filter-state header, row density, filtered facet counts) are a separate,
  similarly-sized cluster — left `ready`, not touched this session, to keep
  this batch to one coherent screen redesign.

- **2026-09-07 — #125 "Evaluate this coffee" — picked up, then re-blocked on
  a new row (#136) — no UX code written.** Read the row and the live backend
  (`backend/src/routes/coffees.js:583`, `backend/src/lib/scoring.js`'s
  `evaluateCoffee`) to confirm the exact response shape before touching
  anything. Unlike #135 in this same session, this one genuinely can't be
  built UX-only: `POST /api/coffees/evaluate` is a brand-new endpoint with no
  existing client plumbing at all (nothing like `CoffeeIndex.coffees` to read
  off of), so it needs a new `APIClient`/`SyncEngine`/`CoffeeRepository`/
  `CoffeeStore` method — all shell-owned files this lane must not touch.
  Filed **#136** (`ios-shell`, `ready`, phase 9) with the exact request/response
  contract and a pointer to mirror `extractWizardDraft`'s existing ephemeral-
  draft pattern rather than `quickCreateCoffee`'s persisted one. Set #125 to
  `blocked` on `106, 136` rather than leaving it `ready` — `ios-shell`'s own
  Step-0 gate only greps `ios-shell` rows, so without a shell-lane row this
  would sit forever the way #12/#13/#34 did before "Integrate before you
  start" existed (`status/README.md`). Once #136 lands, #125 comes back
  `ready` for this lane.

- **2026-09-07 — #135 roaster-country pie: unique roasters, not coffees —
  built without the shell-side helper the row proposed.** The row suggested
  splitting this across both iOS lanes (a `CoffeeIndex` helper on the shell
  side, consumed by a UX-side change), same shape as #27/#28's flagged
  shell-surface gaps. Checked first: `Coffee.roasterId`/`roasterCountryId`
  are already synced fields on every row, and `CoffeeIndex.coffees`/
  `.clearing(_:)` are already internal (module-visible, already used by UX
  code building throwaway `CoffeeIndex`es elsewhere in this same file), so
  the whole grouping — bucket `windowedCoffees` by `roasterCountryId`, count
  distinct `roasterId`s per bucket — is doable entirely inside
  `InsightsView` by *reading* the existing shell surface, not editing it.
  No `Store/Query` file touched, no cross-lane claim needed. Landed
  `8929e97`. Left open per the row: whether the legend's ★ average should
  become an average-over-roasters instead of staying coffee-weighted —
  Radu's call, not made here.

- **2026-09-07 — #120 wizard rating: 0.0 vs UNRATED — already fixed by #131,
  no new commit needed.** Traced the root cause the row names ("the rating
  control likely defaults to 0 and is included in the save") to the wizard's
  old confirm step: `fieldOrder` included `"rating"`, so if the backend's
  light-extraction draft ever returned a `rating` field, `editedValues` seeded
  it from `field.value` and `save()` sent it unconditionally in `edits` — no
  `hasRating`-style gate existed there (unlike `CoffeeEditSheet`, which
  already guards correctly, `hasRating` at line 360). #131 (`de0e4a6`, same
  session) deleted that entire confirm step: the quick-create flow now sends
  **zero** fields, only `photoIds`, so there is no longer any code path in the
  wizard that can send a spurious `rating`. Verified the two rendering asks
  too: `CoffeeDetailView.ratingHeader` already shows "Unrated" for `rating ==
  nil` and `CoffeeRowView.rightColumn` already omits the rating line entirely
  via `if let rating = coffee.rating` — both pre-existing, both correct.
  **Not fixed by this: the specific DAK/Gasharu bag already has `rating: 0.0`
  stored server-side** (a real zero, not NULL) — that pre-existing bad record
  needs a backend/data-lane correction. `CoffeeEditSheet`'s "Rating known"
  toggle only controls whether a *new* rating edit is sent, not an explicit
  clear-to-null instruction, so the app has no UI path to unset an already-set
  rating either. No lane action queued for the stored bad record since the
  row's fix section was about preventing new imports, not repairing old data
  — flagging here in case Radu wants a follow-up row for either the one-off
  correction or a general "clear rating" affordance.

- **2026-09-07 — #131 Add Coffee wizard: submit-and-return, "extracting…"
  indicator.** `AddCoffeeWizardView` dropped the extract → confirm step
  (`extractWizardDraft`/`createWizardCoffee`, still in `CoffeeStore` for now
  since that's shell-owned) in favour of calling `quickCreateCoffee(photoIds:)`
  right after photo + text upload, then dismissing straight back to the
  Coffees tab. `CoffeeRowView`/`CoffeeDetailView` render a subtle
  `ProgressView` + "Extracting…" badge whenever `reviewState == "unextracted"`
  — a third state alongside the existing `needs_review`/`clean` branches; on
  the detail page it replaces the review pill rather than stacking with it,
  since a just-created coffee has no reviewable fields yet. Landed `de0e4a6`.
  **Couldn't visually verify the badge against `BundledSampleRepository`** —
  `SampleData.swift` (shell-owned) has no `reviewState: "unextracted"` row and
  `SampleCoffeeRepository.quickCreateCoffee` throws `notConfigured` by design
  (no live backend in previews), so the wizard's save button errors in sample
  mode same as `createWizardCoffee` always did. Compile-check is the only
  verification available this session; flagging in case the shell lane wants
  to add an unextracted sample row for future UX work on this state.

- **2026-08-28 — #100 dark mode made legible (real adaptive palette).** Radu's
  screenshot showed the shipped build rendering the entire listing near-black on
  black. Root cause was not a missing dark *design* but a missing dark *mechanism*:
  `Theme.Colors` held fixed light-only literals, nothing set
  `preferredColorScheme`, and `surface` was painted in only two places — so the
  system supplied a black ground under near-black ink. Offered Radu the one-line
  `.preferredColorScheme(.light)` lock (faithful to the handoff, which specifies
  no dark palette) versus a real adaptive palette; **he chose the palette.**
  Landed in `1d87ad4`, compile-green on run **#79**.
  The non-obvious part was not the palette but the **coupled literals**: three
  controls filled with a `Color.white` literal while labelling with an adaptive
  token, so flipping the tokens alone would have produced light-grey-on-white —
  a worse bug than the one being fixed. Found by grepping every `Color.white` /
  `Color.black` in `Features/` and checking each against the ink drawn on it.
  Also note run #79 is the first compile check fired by the **push trigger**
  rather than a dispatch — and it only fired after `main` was merged into
  `ios-staging`, because GitHub reads the workflow file from the branch being
  pushed. A push to `ios-staging` before that merge silently ran nothing.

- **2026-08-28 — #101 one flag per origin country.** A blend rendered a lone
  white flag beside text that already named both countries, because the row
  passed `coffee.isBlend ? nil : …` into `FlagView` and `nil` *is* the
  white-flag fallback. New `FlagsView` renders one flag per resolved origin.
  Checked the live data before designing: blends carry 2 origins (x8) or 3 (x3),
  max 3 of 411 — so no truncation or "+N" affordance was warranted. Compile-green
  run #80.

- **2026-08-28 — #102 coffee rows open from every stack.** From a coffee page,
  "More from …" listed coffees but tapping one did nothing. The app registered
  `navigationDestination(for: String.self)` once (`CoffeesListView`) and built
  `CoffeeDetailView` once, inside it — while every off-listing row lived in a
  view pushed **closure-style** yet linked **value-style**, which cannot resolve
  the stack's destination. `InsightsView` separately had its own stack with no
  destination at all. Fixed with `CoffeeLink`, a link carrying its own
  destination, across all five sites; the registration is deleted as unreachable
  and `String` is gone as a navigation key. Compile-green run #82. **Still needs
  an on-device pass** — no Xcode in a session.

- **2026-08-28 — #96 verdict rename + uniform origin line (`UPDATE_BRIEF.md` §B/§C).**
  `.pricey` → `.overpaid` ("you rated it low for the price", not "it was
  expensive") in both `CoffeeRowView` and the detail price block, and the verdict
  is now hidden entirely when #95 returns `band: nil` (too few rated bags in the
  price band to judge) while the pills still show. §C: the origin line is grey on
  **every** row and always carries the country average — the old rule drove both
  the colour and the number off top-origin membership, so the feed alternated
  blue-with-a-number and grey-without and read as arbitrary. Two deliberate
  exceptions where the name shows alone: fewer than 3 rated bags from that
  country, and **blends** — `originSubtitle` lists several countries there, and a
  single trailing number could not say which one it belonged to. The detail page
  and Insights keep their top-origin emphasis.
