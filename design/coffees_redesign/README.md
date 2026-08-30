# Handoff: MyCoffee — Coffees list + Coffee page redesign

## Overview
A visual and hierarchy redesign of the three screens the app is used in most: the **Coffees** tab (the listing, which is also the home) and the **Coffee page** (detail), and the **Insights** tab. No new screens, no new data. The goals were: give the listing row a hierarchy instead of an even wall of facts, make filter state visible, surface the review queue without a tab, mark the user's own top roaster/origin per coffee, and take the palette from the app icon.

Two treatments are in the design file:
- **2a (chosen)** — minimal: no dividers, round touch targets, blue title field, chips.
- **1a (reference)** — the same UX in a flat, ruled, zero-radius treatment. Keep for comparison only.

Implement **2a**.

## About the design files
`MyCoffee Redesign.dc.html` is a **design reference built in HTML** — a prototype of look and behaviour, not code to port. Recreate it in the existing SwiftUI app using its established patterns (`List`, `NavigationStack`, `ToolbarItem`, `CoffeeStore`, the `DesignSystem/` components). Nothing in the HTML should be transliterated; every value below maps onto an existing Swift view.

## Fidelity
**High fidelity.** Colours, type sizes, spacing and copy are final. Recreate pixel-for-pixel where SwiftUI allows, preferring system behaviours (dynamic type, safe areas, `.searchable` placement) over exact pixel matches when they conflict — the design assumes a 390×844 frame.

## Design tokens

Palette derived from `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (blue ground #0078ff, kettle #caf0f8).

| Token | Hex | Use |
| --- | --- | --- |
| accent | `#0078ff` | title field, rating, top-preference text, add button, active chip, favourite |
| accent-600 | `#005eff` | pressed accent |
| accent-100 | `#eef6ff` | review-pill fill, flavour chips fill |
| accent-200 | `#caf0f8` | counts on the blue field |
| accent-700 | `#0047c4` | accent-coloured body text (paragraph-size) |
| accent-800 | `#00337f` | text on accent-100 fills |
| neutral-100 | `#f8f4f4` | search field fill |
| neutral-300 | `#d7d3d3` | chip outline, unfilled value pill, frame border |
| neutral-700 | `#605d5d` | all small grey type (≥4.5:1 on white — do not use lighter) |
| neutral-900 | `#2d2b2b` | chip label |
| text | `#201e1d` | body ink |
| surface | `#ffffff` | screen background (2a is white, not the theme's #f3f2f2) |

**Note:** `AccentColor.colorset` currently holds `#a5824c` (brown), which matches neither the icon nor this design. Update it to `#0078ff` — it drives every default SwiftUI tint.

Radii: `10` (photo), `999` (chips, search, buttons, favourite), `20` (detail card top corners).
Shadows: `sm` = `0 1px 2px rgba(45,43,43,0.14)`; `md` = `0 3px 10px rgba(45,43,43,0.16)`.
Type: single family, weights 400/600/800. Sizes used: 36 / 27 / 26 / 22 / 17 / 13 / 12 / 11 / 10.
Minimum hit target: **44×44** everywhere (visual glyph may be smaller inside).

## Screen 1 — Coffees tab (`Features/Coffees/CoffeesListView.swift`)

### Header — new
A solid `#0078ff` field spanning the safe area to the top of the content:
- Status bar content white.
- Overline: `862 BAGS · 41 ROASTERS`, 10pt, letter-spacing 0.14em, colour `#caf0f8`.
- Title `Coffees`, 36pt weight 800, letter-spacing −0.03em, white. Replaces `.navigationTitle` chrome (`.toolbarBackground(.hidden)` + custom header, or a tinted large-title bar).
- Trailing: Filter and Sort as 44×44 white-glyph buttons (1.6pt stroke, 20pt glyph). Settings moves into the Sort/overflow menu or stays as a third button — keep all three actions of the current toolbar.

### Review nudge — new
Below the header, only when `store.reviewQueueCount > 0`: a 44pt-tall button, `3 bags need review` at 12pt semibold `#0047c4` with a chevron. Taps into the review queue. **The Review tab is removed** — see Tab bar.

### Filter chips — replaces `TopFilterCardsRow`
Horizontal scroll, 8pt gaps, 22pt outer padding. Each chip: pill (radius 999), `min-height 44`, padding 7/16, white fill, 1pt `#d7d3d3` border, label 12pt `#2d2b2b`, count 12pt weight 700 `#605d5d`, 7pt gap between them. Selected: `#0078ff` fill + border, label and count white. Tapping the selected chip **clears** the filter (the current "replace the whole filter" rule is unchanged).

### Filter state line — new
Visible only while filtered, directly under the chips: `96 of 862 bags` at 11pt `#605d5d`, and `CLEAR` at 11pt semibold `#0078ff` right-aligned. This is what makes "tap replaces the whole filter" legible.

### Sections
Month headers lose the grey background: `JULY 2026`, 10pt, letter-spacing 0.14em, `#605d5d`, 20pt above / 10pt below, no rule. Sticky as today.

### Row — replaces `CoffeeRowView`
Left padding 22, no row dividers, 20pt between rows.
- **Photo** 88×88, radius 10, grayscale, `Thumbnail` with rotation as today. Favourite pinned to its bottom-right corner: 44×44 transparent hit area holding a 28pt circle — filled `#0078ff` with a white heart when favourite, white with a 1pt `#d7d3d3` border and a `#605d5d` outline heart when not. (Keeps the nested-button hit-test trick already in `CoffeeRowView`.)
- **Middle column**, 3pt gaps: roaster name 10pt semibold uppercase, letter-spacing 0.06em, single line with ellipsis — `#0078ff` when the roaster is one of the user's top-rated, else `#605d5d`. Title 17pt weight 800, letter-spacing −0.02em, up to 2 lines. Origin line: flag emoji 13pt + `Nekisse, Ethiopia · 4.5` 12pt in `#605d5d` — **uniform on every row**: always append the user's average for that origin (one decimal); show the name alone only when there are too few rated bags (< ~3) to average. No per-row blue on the origin line — the top-origin emphasis lives on the detail page and Insights, not here (it fragments the list otherwise). Process last: the **tinted `ProcessTag` capsule** — reverted 2026-08-29 (#104) after Radu asked for the oval back; this line previously read "11pt `#605d5d` plain text, no tinted capsule". Omitted entirely when the process is unknown.
- **Right column**, 96pt wide, right-aligned: rating 26pt weight 800 (`#0078ff` when ≥4.5, else ink) — no star; price 13pt semibold; €/100 g 10pt `#605d5d`; then the value meter: five 8×4 pills, radius 999, 3pt gaps — filled `#605d5d` (or `#0078ff` when great) against `#d7d3d3`; then the verdict at 10pt semibold letter-spacing 0.08em — `FAIR VALUE` / `PRICEY` in `#605d5d`, `GREAT VALUE` in `#0078ff`.
- **Removed from the row:** altitude, weight, the process capsule, the country-code boxes for origin (flag instead), the star glyph, the full-width grey date strip. The purchase date lives in the month header.

**Value meter rule** (new derived value, no schema change): value is **quality for money**, never price alone — a cheap bag you rated badly is not "fair value". Score each **rated** coffee by how its rating compares to what its price predicts:
- Bucket the library into price bands by `price_per_100g_eur` (quintiles of €/100 g).
- Within the coffee's own price band, take the mean rating of the user's bags. `delta = thisRating − bandMeanRating`.
- Pills = the coffee's rating rank *within its price band* (1–5). Verdict from `delta`: clearly above the band mean → `GREAT VALUE` (blue); around it → `FAIR VALUE`; clearly below → `OVERPAID` (was "PRICEY" — the point is you rated it low for the price, not that it's expensive).
- **Shown only when the coffee has a rating.** No rating → no meter, no verdict (an unrated bag has no value judgement yet). `nil` price → no meter either.

Plain reading: "for what this cost, did you like it more or less than your other bags in the same price range." A €6/100 g bag you rated 3.2 lands `OVERPAID`; a €22/100 g bag you rated 4.7 can still be `GREAT VALUE`.

**Top-preference rule** (new derived value): a roaster or origin country qualifies when it is in the user's highest-average set with at least ~5 rated bags. Show its average to one decimal. This is the only place blue appears in a row besides the rating.

### Search
`.searchable` stays, docked at the bottom as today, restyled as a pill: `#f8f4f4` fill, radius 999, padding 10/16, placeholder 13pt `#605d5d`, magnifier 15pt.

### Tab bar — `Features/Root/RootTabView.swift`
Three slots become **Coffees · + · Insights**. The Review tab is removed (its count now reaches the user via the nudge). The centre slot is a 56pt `#0078ff` circle with a white 24pt plus and shadow `md`, opening the **Add Coffee wizard** (BACKLOG #77 / PLAN §6.8). Tab labels 9pt letter-spacing 0.1em; active `#0078ff`, inactive `#605d5d`; icon stroke 1.7pt. No top divider.

## Screen 2 — Coffee page (`Features/Coffees/CoffeeDetailView.swift`)

Structure follows the existing view; treatment changes.

- **Hero** 300pt, full-bleed, grayscale, tap for the full photo as today. Overlay controls, all 44×44 circles: back (white 92% fill) leading; favourite (`#0078ff` fill, white heart), share and edit (white 92% fill) trailing. Keep the real `ToolbarItem` back button behaviour — do not hide the nav bar back.
- **Card** overlaps the hero by 20pt, white, top corners radius 20, 22pt horizontal padding.
- **Rating header**: 40pt weight 800 `#0078ff`, letter-spacing −0.03em, with four filled + one outline 13pt stars beside it. Right: review pill — `2 fields to review`, 11pt semibold `#0047c4` on `#eef6ff`, radius 999, `min-height 44`, opens `CoffeeReviewSheet` (same gating as today: only when the feed has reviewable tasks).
- **Roaster row**: flag 13pt + name 13pt semibold `#0078ff` + `· your best roaster, 4.6 avg` 11pt `#605d5d` + trailing chevron. Two tap targets as today (flag → country page, name → roaster page).
- **Title** 27pt weight 800, letter-spacing −0.03em.
- **Pill row**: capsules, 11pt, radius 999, `white-space: nowrap`, 7pt gaps — origin `🇪🇹 Ethiopia 4.5` on `#eef6ff` in `#0047c4` (average only when it's a top origin); process, altitude, weight on `#f8f4f4` in `#201e1d`. Blend/decaf pills as today.
- **Price block** — new, replaces price inside the fact rows: `PRICE` / `€ 18.50` and `PER 100 G` / `€ 9.25` as 10pt labels over 22pt weight-800 values, side by side, with the five-pill value meter and its verdict to the right.
- **Fact rows**: `Purchased`, `Roasted`, `Farm` — 12pt, label `#605d5d` left, value semibold right, 9pt apart, no rules. (Price rows move to the block above.)
- **FLAVOUR PROFILE** — new section: 10pt letter-spacing 0.12em label, then flavour chips (11pt semibold, `#eef6ff` fill, `#00337f` text, radius 999) and the caption `Read from the roaster's own copy on the bag.` at 11pt `#605d5d`. **No schema field exists for this today** — it is parsed from `roaster_copy_note`. Either extract the notes server-side into a new `flavour_notes text[]` column (preferred, makes them filterable and railable) or render a client-side parse and treat the chips as read-only.
- **Note blocks**: `FARM & LOT`, `BREW GUIDE` — same 10pt label, body 13pt `#201e1d`. `From the roaster` stays a disclosure (13pt semibold + chevron), as does `Full text`.
- **Rails**: unchanged logic (rating-ordered, hidden below 2 items). Header 13pt semibold with `More` in 11pt semibold `#0078ff`. Cards 92pt wide: 92×92 photo radius 10, title 11pt semibold 2 lines, rating 11pt semibold — `#0078ff` when ≥4.5, else `#605d5d`.

## Screen 3 — Insights tab (`Features/Insights/InsightsView.swift`)

Same blue header field as the listing: overline `604 OF 862 RATED` (10pt, 0.14em, #caf0f8) over `Insights` at 36pt weight 800 white.

### Section control — replaces the `.segmented` Picker
Three equal pills in a row, 6pt gaps, 22pt outer padding, `min-height 44`, radius 999: unselected white with a 1pt `#d7d3d3` border and `#2d2b2b` 12pt semibold label; selected `#0078ff` fill and border, white label. Sections stay **Insights / Charts / Data** with the same contents as today.

### Headline
Two stats side by side, 28pt apart, no card: `862` at 34pt weight 800 over `coffees` at 11pt `#605d5d`; `4.21` at 34pt weight 800 `#0078ff` with a 14pt filled star, over `average rating`. The current rounded-rectangle `secondarySystemBackground` card goes away.

### Brief card (`BriefCard`)
`#eef6ff` fill, radius 14, padding 16/18. Label `THIS MONTH` 10pt semibold 0.12em `#0047c4`; body 14pt `#00337f`, line-height 1.45. Server copy as today — the mock's text is placeholder.

### Findings
Heading `What tends to score well` 17pt weight 800. The z-score toggle becomes a pill button (`min-height 44`, radius 999, same selected/unselected treatment as the section control) labelled `Adjust for yearly rating drift`.
Each finding is one 14pt sentence, line-height 1.45: the **subject phrase in `#0078ff` semibold** (the tappable deep-link, unchanged), the effect in ink, and the `(n=41 vs 563)` / `(ρ = 0.21, n=548)` clause in `#605d5d`. 14pt vertical gaps, no bullets, no cards. Gates, ordering, cap and the "not enough rated coffees yet" empty state are unchanged.

### Charts section (`InsightsCharts.swift`, `CategoryPieChart`)
Designed — see the "INSIGHTS · CHARTS" frame.
- **Time window**: the segmented Picker becomes four equal pills (All / 12m / 18m / By year), 6pt gaps, `min-height 44`, radius 999, selected `#0078ff`. Year chips in "By year" mode reuse the listing chip style (white, 1pt `#d7d3d3`, selected blue) at `min-height 44`.
- **Window summary**: one line, 12pt `#605d5d` — `862 coffees · ★ 4.21 average`.
- **Breakdown card — replaces the donut + legend entirely.** `CategoryPieChart` goes away. One bordered card (1pt `#d7d3d3`, radius 16, padding 16/18) holds: a title (`What you rate highest`, 17pt weight 800); a chip switcher for the dimension — `Origins` / `Roasters` / `Process`, pills at `min-height 44`, 13pt semibold, selected `#0078ff` filled, others white with a 1pt `#d7d3d3` border; then the ranked rows.
- **Row**: full-width button, 13pt vertical padding, hairline `#eae7e7` between rows (none on the last). Name 15pt weight 700; under it a 13pt line — blue star, the average in weight 700 ink, then `Based on 218 bags` in `#605d5d`; trailing 18pt chevron. Ordered by **average rating**, not count, since the card answers "what do I rate highest" — the sample size is stated on every row so a thin slice can be judged. Each row keeps the existing deep-link into the filtered listing.
- The remaining dimensions (roaster country, farm, decaf, rating/price/altitude bands, year) stay available through the same switcher rather than as eleven stacked charts — one card, one dimension at a time.
- **Palette**: no categorical palette needed. `ChartPalette` is only kept for `YearlyStackedChart`, with its first hue retinted to `#0078ff`.
- "Other" is not shown in this card: with one dimension at a time and a rating order, an aggregate bucket has no meaning — the switcher's full list is reachable through the filter sheet as today.

### Data section
Not redesigned. Apply the shared treatment only: 17pt weight-800 titles, 11–12pt `#605d5d` supporting text, 44pt rows, no cards.

### Tab bar
Insights is the right-hand tab, active tint `#0078ff`.

## Interactions & behaviour
- Chip tap: replaces the whole filter; tapping the active chip clears it. The filter line appears/disappears with it.
- `CLEAR` resets to the unfiltered list.
- Favourite toggles optimistically through `store.toggleFavorite` (unchanged).
- Review nudge and review pill both open the existing review flows.
- Centre `+` presents the Add Coffee wizard.
- Insights section control and the drift toggle are plain state flips; findings' subject phrases keep the existing `mycoffee-finding://` deep-link into the filtered Coffees tab.
- No new animations. Standard SwiftUI navigation transitions.

## State
No new persisted state. Two derived values, both computable in `CoffeeIndex`:
- `valueBand(for: Coffee) -> .great | .fair | .overpaid` plus a 1–5 pill count. **Requires a rating.** Compares the coffee's rating to the mean rating of bags in the same €/100 g price band (see Value meter rule) — quality-for-money, not price percentile. Returns `nil` when the coffee is unrated or has no price.
- `topRoasterIDs` / `topOriginCountryIDs` with their averages, from rated coffees with a minimum count.

## Suggested implementation order

1. **Tokens first.** Add a `Theme` (or extend `DesignSystem/`) with the palette below, and set `AccentColor.colorset` to `#0078ff`. Everything else references these.
2. **`CoffeeRowView`** — the biggest visible win, and self-contained.
3. **`CoffeesListView`** — blue header field, chip filter row, filter-state line, quiet month headers, pill search.
4. **`RootTabView`** — drop the Review tab, add the centre `+`; wire the review count into the listing nudge.
5. **`CoffeeDetailView`** — hero controls, rating header, pill row, price block, facts, flavour profile, rails.
6. **`InsightsView`** — header, section pills, headline, brief card, findings; then replace `CategoryPieChart` with the breakdown card.
7. **Derived values** (`CoffeeIndex`): value band, top roaster/origin. Ship the UI against them last so the views don't hard-code sample numbers.

## Definition of done

- No screen uses a tinted capsule for process, a grey date strip, or a donut chart.
- Every tappable element measures ≥44×44 (chips, legend/breakdown rows, hero circles, favourite, toggles).
- Small grey text is `#605d5d` or darker — never `#9b9797` on white.
- Blue appears only on: the header field, rating, top roaster/origin, value "great", the add button, the selected chip, and links. If it appears anywhere else, it has lost its meaning.
- The filter chip row, the filter-state line and the list always agree: a lit chip means a filtered list.
- "Other" buckets never rank among named values.
- Nothing invented: no field is displayed that `Coffee` doesn't carry, except the two derived values above and flavour notes (see below).
- The value meter never appears on an **unrated** coffee, and a cheap-but-badly-rated bag reads `OVERPAID`, never `FAIR VALUE`.

## Open questions for the developer

- **Flavour notes** have no column. Either add `flavour_notes text[]` server-side (extracted in the same pass that produces `roaster_copy_note`) or parse client-side and treat them as read-only. The design assumes 3–5 short notes.
- **Roasted date** shows on the coffee page whenever `roastedOn` exists; the mock shows it populated. No change needed, just don't hide the row.
- **Value band** now keys off rating-vs-price-band, not price percentile. The band count (quintiles) and the `delta` cutoffs for great/fair/overpaid are starting points — tune against the real distribution. With few rated bags in a price band the mean is noisy; suppress the verdict (show pills only, or nothing) below ~5 rated bags in the band.

## Assets
- App icon `AppIcon-1024.png` — source of the palette; also included here.
- Country flags: emoji, as the existing `FlagView` does for origins. Roaster country in the listing row is dropped in 2a (the roaster name carries it); keep `FlagView` on the detail page.
- Photography renders grayscale in the mock; that is a design-system convention of the HTML reference, **not** a requirement — ship colour photos unless you want that look.

## Files in this bundle
- `MyCoffee Redesign.dc.html` — the design reference. Section `2a` is the one to build; `1a` below it is the earlier ruled treatment.
- `AppIcon-1024.png` — palette source.
- Repo files this maps onto: `Features/Insights/InsightsView.swift`, `Features/Insights/BriefCard.swift`, `Features/Insights/InsightsCharts.swift`, `Features/Coffees/CoffeesListView.swift`, `CoffeeRowView.swift`, `TopFilterCardsRow.swift`, `CoffeeDetailView.swift`, `RailView.swift`, `Features/Root/RootTabView.swift`, `DesignSystem/ProcessTag.swift` (process capsule retires from the row), `Query/TopFilterCard.swift`, `Store/CoffeeIndex.swift` (new derived values), `Resources/Assets.xcassets/AccentColor.colorset`.
