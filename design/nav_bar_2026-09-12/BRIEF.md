# Nav bar refresh — Recipes + Shop tabs (designer brief)

_Radu, 2026-09-12. Companion backlog row: #195 (`status/BACKLOG.md`)._

## Context in one paragraph

MyCoffee is Radu's personal coffee library (iOS SwiftUI, TestFlight). The nav
bar is a native `TabView` on the system's translucent glass — no custom
overlay, no floating buttons. Icons today are **Lucide outline glyphs at
~22 pt, single-stroke 2 px**, tinted `#0078FF` when selected, neutral
otherwise. Whatever you design has to sit next to `coffee`, `circle-plus`,
`bar-chart-3` from the Lucide set and read as part of the same family.
Repo: `Climb-Again/MyCoffee`.

## What's changing

Tab bar goes from **3 items → 5**, in this order:

```
Coffees   Recipes   +   Shop   Insights
(exists)   NEW    (exists) NEW   (exists)
```

## Deliverables

### 1. Two tab icons — Lucide outline, 24×24 SVG

- **Recipes** — the tab opens a *catalogue* of brew methods, grind sizes,
  temperatures and recipes with per-item win-rates ("V60 4:6 won 7 of 12").
  Not a diary, not a shopping list. First-pass suggestions from Lucide:
  `notebook-pen`, `beaker`, `book-open`, `chef-hat`. Radu leans practical
  over cute — pick one, don't invent a new glyph. If none fit, `mug` reads
  well and doesn't collide with `coffee`.
- **Shop** — the tab is Radu's *shortlist* of coffees he's found while
  browsing roaster shops (via a Chrome extension he uses). Not owned;
  things he's considering. Suggestions: `shopping-bag`, `bookmark`, `tag`,
  `store`. `bookmark` reads "saved" better than "spending". Radu's call.

Export each as a stroked SVG with `stroke="currentColor"`,
`stroke-width="2"`, `fill="none"`, no baked colour. Drop into
`ios/MyCoffee/Resources/Assets.xcassets/lucide-<name>.imageset/`.

### 2. Recipes tab — layout comps (mobile + iPad landscape)

**What it shows:** four sections stacked — Recipes · Devices · Grind sizes ·
Temperatures. Each section is a segmented catalogue: label · secondary
line · per-item "won N of M" badge. Tap a row → deep-link to Coffees
filtered to that option.

**Reuse cues:** the existing `Features/Brew/BrewCatalogueView` already
renders this content from Settings. Same rows, same seg-control at top for
kind, promoted to a first-class tab. Section labels: **10 pt, 0.12 em
tracking, uppercase, neutral-600** (matches Coffee detail page).

**Notes for you to solve:** empty state (no trials logged yet, nudge to a
coffee), and how "won N of M" reads when it's `won 0 of 1` (dim it, don't
hide it).

### 3. Shop tab — layout comps (mobile + iPad landscape)

**What it shows:** a ranked list of coffees Radu shortlisted from roaster
shops (the browser extension writes them). Each row **must mirror the
app's existing `CoffeeRowView`** — image · UPPERCASE roaster name · heavy
one-line title · origin · right column with fit-score (in the rating
slot), €/100g and five value pills (8×4 pt, 3 pt gap, capsule). Rows
already saved as owned show an **IN YOUR LIBRARY** micro-tag under the
title.

Tap a row → opens the source URL in Safari (this is a *shortlist*, not a
coffee page inside the app).

**Notes for you to solve:** how the row degrades when the shortlisted
coffee has no image (fallback treatment consistent with library rows);
empty state ("Nothing shortlisted yet — install the extension");
sort/filter affordance or none (default: highest fit-score first, 30-day
rolling window).

## Design system pins

- Accent `#0078FF` · surface light `#FFFFFF` / dark `#141212` · text
  `#1C1C1E` light / `#F2F2F2` dark — every colour must be adaptive.
- Three shadow tiers only. No capsules on interactive elements except
  pills. 44 pt hit target minimum.
- Prefer max-width clamp (~700 pt centred) over full-bleed on iPad — same
  rule the Coffees list follows.

## Non-goals

Don't redesign the `+` behaviour, don't touch the existing three tabs'
icons, don't propose a `NavigationSplitView` on iPad. The tab structure is
set.
