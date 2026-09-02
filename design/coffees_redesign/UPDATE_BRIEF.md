# MyCoffee — Redesign brief v3 (supersedes v2 and README where they disagree)

## Why there is a v3

v2 asked for a custom blue header and a hand-built tab bar. That was the wrong call and it is the cause of almost everything that looks bad now: a full-bleed blue band that eats 300pt (doubled on Insights), a tab bar that lost iOS's glass material, a search field that lost system behaviour, and a black month bar from the *rejected* 1a treatment. The row content, the coffee page and the value/origin logic are close to right.

**The governing decision for v3: stop replacing iOS chrome. Use the native navigation bar, the native search, and the native tab bar with their standard materials — and spend the design entirely on content.** Blue stays as the app's accent, not as a painted band.

Anything in v2 or `README.md` that tells you to hide the nav bar, hide the tab bar, build a blue header block, or build a custom bottom bar is **revoked**. Sections A1, A2, A3 of v2: revoked, replaced by §1–§3 below.

**Rules of engagement**
- Prefer the native component every time. If you find yourself writing `.toolbar(.hidden, …)`, `.ignoresSafeArea`, or an `.overlay` to place chrome, stop — that is the mistake v2 caused.
- Do not add anything not asked for: no chevrons, no ringed icon buttons, no tinted process capsules, no gradients, no new icons.
- Every item ends with **Acceptance**. It is not done until that literal test passes on device.
- Work on a branch. Visual reference: section `2a` of `MyCoffee Redesign.dc.html`. `1a` is rejected — if anything in the build resembles 1a (black month bars, ruled rows, boxed country codes), it came from the wrong section.

---

## 1. Header — native large title, no blue band

**Now:** a blue rectangle ~200–300pt tall with an overline, a large title, and two ringed icon buttons; on Insights it renders twice (light blue safe area + solid blue band) with dead space between.

**Build instead:**
- Delete the custom header view entirely. Delete every `.toolbarBackground(…)`, `.toolbar(.hidden, for: .navigationBar)` and `.ignoresSafeArea(edges: .top)` added for it.
- Use a standard `NavigationStack` with `.navigationTitle("Coffees")` and `.navigationBarTitleDisplayMode(.large)`. Default material, default white/system background, ink title. It collapses to the compact inline title on scroll — that behaviour is the point.
- The stats line (`411 BAGS · 59 ROASTERS`) is **not** nav-bar chrome. It becomes the first list row: 10pt, letter-spacing 0.14em, `#0078ff`, 22pt leading padding, ~10pt vertical. It scrolls away with the content.
- Toolbar actions: **two** `ToolbarItem`s, both trailing, there is room for them:
  1. **Sort** — `sliders-horizontal`, opening the existing sort `Menu` (Date bought / Rating / Price / Price per 100 g, checkmark on the active one).
  2. **Settings** — a `settings` gear, opening Settings directly. A visible gear is required; do not bury Settings inside the sort menu.
  No `Circle().strokeBorder` rings around either.
- Insights uses the identical pattern with `.navigationTitle("Insights")` and its `364 OF 411 RATED` line as the first scrolling row.

**Acceptance:** at rest, no screen shows more than the standard iOS large-title bar; there is no blue rectangle anywhere; scrolling collapses the title to inline; Insights shows exactly one bar, with zero dead space above the section pills.

---

## 2. Search — native `.searchable`, nothing custom

**Now:** a big grey pill in its own white band with oversized pale placeholder text.

**Build instead:**
- Delete the hand-built `TextField` row. Use `.searchable(text: $store.filter.query, prompt: "Search coffees, roasters, farms")` on the List.
- Accept the system's placement and appearance completely — no capsule fill, no custom font, no `UISearchBar` appearance hacks. Standard placeholder colour is correct; the v2 pill instruction is revoked.

**Acceptance:** search looks and behaves exactly like Mail/Notes search on the same iOS version; it does not occupy a permanent band of its own.

---

## 3. Tab bar — native `TabView`, glass, and the `+` inside it

**Now:** an opaque white bar with a large detached blue circle overlaying content.

**Build instead:**
- Native `TabView` with two tabs, **Coffees** and **Insights**. Do not hide it. Do not `.overlay` anything on it. It keeps the system's translucent glass material and its own height — that is what makes the app feel native.
- Add the coffee as a **third tab item** in the middle whose label is a `plus.circle.fill` (or the app's existing add glyph) at the standard tab-item size, tinted `#0078ff`; selecting it presents the Add Coffee wizard as a sheet and immediately restores the previous tab selection. **No 56pt floating circle. No shadow. No offset.**
- Tab tint `#0078ff` (set `AccentColor.colorset` to `#0078ff` — it is still brown `#a5824c` in the repo).

**Acceptance:** the bar is the system tab bar with content blurring under it; no circle floats above any row; nothing overlays the coffee-detail page; standard bar height.

---

## 4. Filter chips — they are missing and must be on screen

**Now:** built and working (chips, `2 of 411 bags`, `CLEAR`), but they sit below the blue header and the search band, so they are off-screen or half-lost on open. Fixing §1 and §2 recovers the space; the rest of this section is the spec they must match.

**Build:** a horizontally scrolling `ScrollView(.horizontal)` of chips as the **first content row of the List**, directly under the stats line (it scrolls away with content; it is not pinned).
- Chip: `Capsule()`, `minHeight 44`, padding 7/16, white fill, 1pt `#d7d3d3` border, label 12pt `#2d2b2b`, count 12pt weight 700 `#605d5d`, 7pt gap between label and count, 8pt between chips, 22pt leading inset.
- Selected: `#0078ff` fill and border, label and count white. Tapping the selected chip clears the filter.
- Directly below, **only while a filter is active**: one row with `96 of 411 bags` at 11pt `#605d5d` and `CLEAR` at 11pt semibold `#0078ff`, right-aligned.

**Acceptance:** opening Coffees shows the chip row without scrolling; tapping a chip lights it, filters the list, and shows the count line; tapping it again clears both.

---

## 5. Month headers — quiet, never black

**Now:** a full-width **black** band with grey text (this is 1a, the rejected treatment), and a large empty gap between sections.

**Build:** plain text on white — `AUGUST 2026`, 10pt, letter-spacing 0.14em, `#605d5d`, `.background(Color.white)`, `.listRowInsets(EdgeInsets(top: 20, leading: 22, bottom: 10, trailing: 22))`, no fill, no rule.
- Remove whatever is producing the ~120pt gap before a section header — almost certainly a section footer or default header inset. Sections are separated by the 20pt top inset only.

**Acceptance:** month labels are grey text on white with no band; consecutive sections are ~20pt apart, never a screen-height gap; a sticking label never shows a photo behind it.

---

## 6. Row — the details that drifted

Content and column order are right. Fix these six:

1. **Process is plain text, not a coloured capsule.** Delete the tinted `ProcessTag` from the row: red "Natural" and purple "Anaerobic" pills are the loudest thing on screen and are not in the design. Render the process as the last line of the middle column, 11pt `#605d5d` plain text. (`ProcessTag` may stay on the detail page.)
2. **No disclosure chevrons.** Remove the trailing `>` from every row — use `.listRowSeparator(.hidden)` and a plain `NavigationLink` with no indicator. The whole row is the tap target.
3. **Title is one line, truncated.** 17pt weight 800, `lineLimit(1)`, `.truncationMode(.tail)`. Two wrapped lines plus an ellipsis (as in "Keen Brazilia – Jaguara Anaero…") is what makes rows ragged and the list feel heavy.
4. **Origin is one line.** `lineLimit(1)`, truncate. A three-line farm name ("Chelchele washing and drying station, Ethiopia · 4.0") must become one truncated line. Show the farm only if it fits — otherwise country alone.
5. **Fixed row height.** With one-line title and one-line origin, every row is the same height (~112pt: 88pt photo + 12pt vertical padding). Rows must not vary.
6. **Value pills, not dots.** The meter is five 8×4 rounded **pills** with 3pt gaps — `#605d5d` (or `#0078ff` when great) against `#d7d3d3`. The current 3pt dots are illegible. Verdict below at 10pt semibold letter-spacing 0.08em.

Also: the favourite circle sits on the photo's bottom-right corner *inside* the photo bounds — do not let it hang outside the rounded rect; and the gutter is a single margin (`.listRowInsets(EdgeInsets())` on the row, row owns 22pt leading / 16pt trailing).

**Acceptance:** every row in a screenshot is the same height; no coloured process pill; no chevron; no wrapped title or origin; the five value pills are clearly readable as a meter.

---

## 7. Type and alignment

**Now:** sizes run large and headings use default weights, so the list reads soft and inconsistent.

- One family (the system font is fine), three weights only: 400 body, 600 semibold, **800** for titles and numbers. Titles and numbers use `.tracking(-0.02em)`.
- Sizes are exactly: row title 17, rating 26, price 13, €/100 g 10, roaster 10 (uppercase, 0.06em), origin 12, process 11, verdict 10, month label 10, chip 12, stats line 10. Do not scale them up.
- Everything is flush left except the right column, which is flush right. No centred text anywhere except tab labels.
- Numbers: `.monospacedDigit()` on rating, price and €/100 g so columns don't jitter while scrolling.

**Acceptance:** the right column's numbers align on a single right edge down the whole list; no text is centred; no title renders larger than 17pt.

---

## 8. Coffee page — three fixes only

The structure is right. 

1. **Hero toolbar**: the floating capsule reads cream/peach against the photo. Use a single `.ultraThinMaterial` capsule (no tint) holding favourite / share / edit, and the standard back button — or plain `.regularMaterial` circles. No warm tint.
2. **`Full text`** currently dumps raw scraped copy that overflows mid-sentence. Collapse it by default and, when open, give it 13pt body with proper line spacing and no truncation mid-word.
3. **Price block**: keep it, but the value meter here uses the same five pills as the row (currently dots).

**Acceptance:** no warm/cream tint over the photo; `Full text` is collapsed on open; pills match the row's.

---

## 9. Insights — chrome only

**The charts are pie/donut charts. Keep them.** This has been asked for twice. Every ranked-bar-list and "breakdown card" instruction anywhere in `README.md` or earlier briefs is **revoked** — do not convert a donut into a list, and do not add a list beside it. `CategoryPieChart` stays, with its dimension chip row and its legend. Change only:
- The double blue band → native large title (§1).
- Section pills (`Insights / Charts / Data`): `minHeight 44`, 13pt semibold — they currently render ~56pt tall with 15pt text. Same chip style as §4.
- The dimension chip row must not clip a chip mid-word at the screen edge ("Roaster cou…"): give the `ScrollView(.horizontal)` a 22pt trailing inset and let it scroll.
- Legend rows: 11pt `#605d5d`, count and average as they are now.

**Acceptance:** one bar; pills are 44pt tall; no chip is cut off at the right edge; charts unchanged.

---

## 10. Perceived performance

"Sluggish" with 411 rows is usually these three:
- `List` rows must not recompute derived values per render. Compute `valueBand`, origin averages and top-roaster sets **once** in `CoffeeIndex` and cache them by coffee id — never inside `body`.
- Thumbnails: downsample to the displayed size (88×88 @3x = 264px) when decoding, and cache decoded images. Full-resolution decode per row is the usual cause of scroll stutter.
- Use `LazyVStack`/`List` (already) but ensure the section grouping is precomputed, not recalculated on each `body` evaluation.

**Acceptance:** scrolling the full library holds 60fps on device with no blank photo flashes.

---

## 11. Icons — replace the stock SF Symbols (asked for twice, still not done)

The build still uses default SF Symbols (filled cup, filled bar-chart, filled heart, `chevron`, filled plus circle). The design uses **Lucide** outlines throughout — this is the design system's rule and it is what makes the app look considered rather than default.

- Vendor the Lucide SVGs the app needs into the asset catalogue as **template images** (or use an SF Symbol only where an exact Lucide equivalent exists). Do not keep the filled SF variants.
- Style for every icon: **outline only, 1.7pt stroke, round caps and joins, no fill**, sized 22pt in the nav bar, 25pt in the tab bar, 14–19pt inline.
- The set:

| Where | Lucide name |
| --- | --- |
| Nav bar — sort | `sliders-horizontal` |
| Nav bar — settings | `settings` |
| Tab — Coffees | `coffee` |
| Tab — Add | `circle-plus` |
| Tab — Insights | `bar-chart-3` |
| Favourite (row + hero) | `heart` — outline when off, **filled** only when on |
| Search field | `search` |
| Detail hero — back / share / edit | `chevron-left` / `share` / `pencil` |
| Disclosure (detail rows only) | `chevron-right` |
| Review nudge | `chevron-right` |

**Acceptance:** no filled SF Symbol remains in the row, tab bar or nav bar; every icon is a 1.7pt outline; the only filled icon in the app is an active favourite heart.

---

## 12. Glass — use iOS materials, don't paint solids

The redesign is meant to sit on iOS's materials. Anywhere chrome overlaps content, use a system material and let content blur through:

- **Tab bar**: system default (do not set a background) — it is already glass once you stop replacing it (§3).
- **Nav bar**: system default material; it goes translucent and shows the list blurring under it as you scroll. Never set an opaque or coloured background.
- **Search**: native `.searchable` — already glass.
- **Detail hero controls**: one `.ultraThinMaterial` capsule / circles, **no tint** (§8).
- **Sort and Settings menus**: native `Menu` — its glass is free.
- **Unselected filter chips**: `.background(.thinMaterial, in: Capsule())` with the 1pt `#d7d3d3` border instead of a flat white fill. Selected chips stay solid `#0078ff` — the contrast between glass and solid is what shows selection.
- Nothing else gets a material: rows, cards and the photo stay opaque. Glass belongs to chrome only.

**Acceptance:** scrolling the list, content is visibly blurred beneath both the nav bar and the tab bar; no bar has an opaque or coloured fill; unselected chips read as frosted, selected as solid blue.

---

## Value meter logic (unchanged from v2, restated because it must not regress)

Value is **quality for money**, only for **rated** coffees:
- Price bands = quintiles of `price_per_100g_eur`. For the coffee's band, take the mean rating of your bags in that band. `delta = thisRating − bandMean`.
- Pills (1–5) = the coffee's rating rank within its price band. Verdict: clearly above → `GREAT VALUE` (blue); around → `FAIR VALUE`; clearly below → `OVERPAID`.
- Unrated or no price → no meter, no verdict. Fewer than ~5 rated bags in a band → pills only, no verdict.
- The build currently also shows `POOR VALUE`; use only the three labels above.

**Acceptance:** a €6/100 g bag rated 3.2 → `OVERPAID`; a €22/100 g bag rated 4.7 → can be `GREAT VALUE`; unrated → nothing.

## Origin line (unchanged from v2)

`flag · Country · 4.1` in `#605d5d` on **every** row, always with your average for that country; name alone only when there are fewer than ~3 rated bags. No per-row blue on origin. Blue in a row is only: a top **roaster** name, and the rating at ≥4.5.

**Acceptance:** no origin line is blue; every origin with data shows an average.

---

## Files
- `Features/Coffees/CoffeesListView.swift` — §1, §2, §4, §5, §7, §10
- `Features/Root/RootTabView.swift` — §3
- `Features/Coffees/CoffeeRowView.swift` — §6, §7, origin, verdict
- `Features/Coffees/CoffeeDetailView.swift` — §8
- `Features/Insights/InsightsView.swift`, `InsightsCharts.swift` — §9
- `Store/CoffeeIndex.swift` — value band, cached derived values (§10)
- `Resources/Assets.xcassets/AccentColor.colorset` — `#0078ff`

## Do not touch
Coffee-page structure and fields, flavour profile, rails, the pie charts, the Data section, the Edit sheet.

## Done checklist
- [ ] Native large-title nav bar; no blue band; one bar on Insights.
- [ ] Native `.searchable`; no custom search field.
- [ ] Native glass tab bar; `+` is a tab item; nothing floats over content.
- [ ] Filter chips visible on open, with the filter-state line.
- [ ] Month labels grey on white; no black band; ~20pt between sections.
- [ ] Rows uniform height; one-line title and origin; no chevrons; no coloured process pill; five readable value pills.
- [ ] Type sizes per §7; numbers monospaced and right-aligned.
- [ ] Hero toolbar neutral material; `Full text` collapsed.
- [ ] Insights: 44pt pills, no clipped chip, charts untouched.
- [ ] 60fps scroll; derived values cached; thumbnails downsampled.
- [ ] Value verdicts: only GREAT VALUE / FAIR VALUE / OVERPAID, rated only.
- [ ] Origin lines uniform grey with averages.
- [ ] Icons are Lucide outlines at 1.7pt; no filled SF Symbols; only an active heart is filled.
- [ ] Nav bar and tab bar are system materials; content blurs under both; unselected chips are frosted.
- [ ] A settings gear is visible in the nav bar.
- [ ] Charts are still pie/donut.
- [ ] AccentColor is `#0078ff`.
