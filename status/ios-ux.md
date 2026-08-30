# Lane: iOS UX

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-ux-history.md`](archive/ios-ux-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## Abandoned

_none_

## Session notes

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
