<!-- Landed 2026-08-27 from Radu's `Improve_MyCoffee_UXUI_1.zip` handoff. -->

> ## Where these files live in this repo
>
> - This brief — `design/coffees_redesign/UPDATE_BRIEF.md`
> - The canvas the brief calls `MyCoffee Redesign.dc.html` — `design/coffees_redesign/MyCoffee-Redesign.dc.html`
>   (same file, hyphenated to match the path already referenced by rows #83–#89). **Screen `2a`** is the reference; `1a` is the rejected alternative.
> - `README.md` in the same folder has been updated in the same commit, so its
>   §Row and §Value-meter passages now agree with this brief rather than
>   contradicting it.
>
> **Verified against `ios-staging` on 2026-08-27, before filing the work:**
> every problem this brief describes is real and reproducible in the code —
> `.searchable` + the two `.toolbarBackground(...)` calls and the in-`List`
> header (A1/A2), `Circle().strokeBorder` in `headerIcon` (A5), the coffee rows
> and `monthHeader` missing `.listRowInsets(EdgeInsets())` (A6), `monthHeader`
> with no opaque background (A4), the `+` as an `.overlay(alignment: .bottom)`
> on the `TabView` (A3), and `valueBand(for:)` scoring pure price quintiles with
> a `.pricey` case (B).
>
> **One correction:** the brief says `AccentColor.colorset` is "still brown
> `#a5824c`". It is not — it is already `#0078FF` (`red 0.000, green 0.471,
> blue 1.000`), fixed by #83. Nothing to do there; the last checklist item is
> already satisfied.
>
> Filed for the lanes as backlog rows **#93–#96**. Per the intake rule nothing
> here is implemented yet — say the word and the lanes (or a session) will pick
> them up.

---

# MyCoffee — Redesign update brief (v2)

**Read this first.** This is the single authoritative spec for the current round. It supersedes the header/search/tab-bar/value/origin passages of the earlier `README.md` wherever they disagree. The build already got the **row content, the coffee page, the chips, and the value meter's placement** right — do **not** rewrite those. This round fixes the parts that shipped wrong: the screen chrome, the value *logic*, and the origin line.

**Rules of engagement**
- These instructions are decisive. Where one conflicts with a SwiftUI default or an iOS-26 convenience (e.g. `.searchable` docking, `.toolbarBackground`), **follow the instruction and drop the convenience** — the last round's problems all came from keeping the convenience. If an instruction is genuinely impossible on the deployment target, leave a `// DEVIATION:` comment saying why and what you did instead, and don't silently substitute.
- Do not add anything not asked for: no new icons, no new fields, no decorative rings, no gradients.
- Work on a branch. Screen `2a` in `MyCoffee Redesign.dc.html` is the visual reference; `1a` in that file is a rejected alternative — ignore it.
- Each item below ends with an **Acceptance** line. The change isn't done until that literal test passes on-device.

Design tokens (palette from the app icon) are unchanged from `README.md` §Design tokens. `AccentColor.colorset` must be `#0078ff` (still brown `#a5824c` in the repo — fix it).

---

## A. Chrome (the biggest visible problems)

### A1 — One header. No empty blue band.
The build paints the native nav bar blue **and** adds a blue header row, so a ~300pt empty blue rectangle stays pinned when you scroll.

- Remove **both** `.toolbarBackground(Theme.Colors.accent, for: .navigationBar)` and `.toolbarBackground(.visible, ...)`, and hide the bar: `.toolbar(.hidden, for: .navigationBar)`.
- Lift the header **out of the `List`** into a `VStack(spacing: 0) { header; searchField; List{…} }`.
- The header is a **fixed, compact** blue band: title `Coffees` + the stats overline + the existing toolbar actions on one row, **≤ 108pt tall including the status-bar inset**. Draw its blue with `.ignoresSafeArea(edges: .top)` and pad the top for the status bar.
- **Acceptance:** scrolling the list shows white under the header immediately; there is never an empty blue area below the title; the header is one band, not two.

### A2 — Search is a legible white pill, below the header.
The build's search is a translucent field on blue, above the title.

- Remove `.searchable` from this view. Add a plain `searchField` row between header and List: `TextField` bound to `store.filter.query`, 15pt ink text, magnifier glyph `#605d5d`, inside a `Capsule().fill(Theme.Colors.neutral100)` (#f8f4f4), on white, 22pt side margins, `minHeight 44`.
- **Acceptance:** the search field is white with dark, fully legible placeholder, sits directly under the header, and typing filters the list.

### A3 — The `+` lives in the bar and never overlaps content.
The build floats the `+` as a global `.overlay` on the `TabView`, so it covers list rows **and** the detail page's body text.

- Hide the system tab bar (`.toolbar(.hidden, for: .tabBar)`) and build the three-slot bar the design shows via `.safeAreaInset(edge: .bottom)`: **Coffees · (+) · Insights**. Because it's a safe-area inset, the list and the detail page inset above it — nothing overlaps.
- The `+` is the 56pt `#0078ff` circle, white 24pt plus, `md` shadow, centred between the two tab items. It opens the Add Coffee wizard.
- **Acceptance:** the `+` sits in the bottom bar; it does not paint over any row; it does **not** appear on the coffee-detail page.

### A4 — Sticky month headers are opaque.
Month labels currently print over the next row's photo when they stick.

- Give `monthHeader` `.background(Color.white)` and full width.
- **Acceptance:** while scrolling, `AUGUST 2026` never shows a photo behind it.

### A5 — No new icons, no rings.
The header grew three ringed circle buttons that weren't in the app.

- Remove the `Circle().strokeBorder` ring from `headerIcon`. Keep the app's **existing** toolbar glyphs in their existing form; prefer folding sort/settings into one overflow menu over a cluster of three buttons on the blue.
- **Acceptance:** the header has the title, the stats line, and at most a small action affordance — no new icons, no circle outlines.

### A6 — Listing gutter is a single margin.
Rows sit in too far because `List(.plain)`'s default row insets stack on top of the row's own `.padding(.leading, 22)/.trailing 16`.

- Add `.listRowInsets(EdgeInsets())` to the coffee rows **and** the month-header rows, so the row's own padding is the whole gutter. Target a single ~16–22pt margin; if still wide, drop the row to `.leading 16 / .trailing 12`.
- **Acceptance:** the photo's left edge and the rating's right edge sit ~16–22pt from the screen edges, not ~40pt.

---

## B. Value meter logic (it was price-only; it must be quality-for-money)

A cheap bag you rated badly currently reads `FAIR VALUE`. Wrong — value has to include rating.

Redefine `valueBand(for:)` in `CoffeeIndex`:
- Compute **only for rated coffees**. Unrated → `nil` → no meter, no verdict.
- Bucket the library into price bands = quintiles of `price_per_100g_eur`. For the coffee's own band, take the **mean rating of your bags in that band**. `delta = thisRating − bandMean`.
- Pills (1–5) = the coffee's rating rank within its price band.
- Verdict from `delta`: clearly above → `GREAT VALUE` (blue); around → `FAIR VALUE`; clearly below → **`OVERPAID`** (rename the `.pricey` case). Update `verdictLabel` and the `ValueRating.Band` enum in both `CoffeeRowView` and the detail price block.
- If a price band has **< ~5 rated bags**, the mean is noisy — suppress the verdict (pills only, or nothing).
- **Acceptance:** a ~€6/100 g bag rated 3.2 shows `OVERPAID`; a ~€22/100 g bag rated 4.7 can show `GREAT VALUE`; an unrated bag shows no meter at all.

---

## C. Origin line — uniform on every row

Today some origin lines are blue with an average and others grey with none (the top-origin rule drives both colour and the number), so the feed looks arbitrary.

- The origin line is **`flag · Country · 4.1` in `#605d5d` on every row**, always showing your average for that country (one decimal). Show the country name **alone** only when there are genuinely too few rated bags (< ~3) to average — for that reason only.
- Remove the `topOriginAverage`-driven colouring from `CoffeeRowView.originLine`. Keep `topOriginCountryIDs` — it still feeds the **detail page** ("top origin") and **Insights**, just not the row.
- The **roaster** line keeps its blue when the roaster is a top roaster (one signal per row is fine); the rating still turns blue at ≥ 4.5. Those are the only blues in a row.
- **Acceptance:** scanning the list, every origin line looks the same (grey, with an average where one exists); none is blue; none is missing a number except genuinely low-data origins.

---

## Files this touches
- `Features/Coffees/CoffeesListView.swift` — A1, A2, A4, A5, A6
- `Features/Root/RootTabView.swift` — A3
- `Features/Coffees/CoffeeRowView.swift` — B (verdict), C
- `Features/Coffees/CoffeeDetailView.swift` — B (verdict rename in price block); `+` must not overlay it (A3)
- `Store/CoffeeIndex.swift` — B (valueBand redefinition), C (origin averages still available)
- `Resources/Assets.xcassets/AccentColor.colorset` — set to #0078ff

## Do NOT touch
- Row layout/typography, coffee-page structure, chips, filter-state line, flavour profile, rails, Insights breakdown card. They're correct.

## Full done checklist
- [ ] One compact blue header; no empty blue band on scroll.
- [ ] White pill search under the header, legible, filters the list.
- [ ] `+` in the bottom bar; never overlaps rows or the detail page.
- [ ] Opaque sticky month headers.
- [ ] No new header icons or rings.
- [ ] Single ~16–22pt listing gutter.
- [ ] Value meter is rating-vs-price-band; unrated → hidden; cheap-and-bad → OVERPAID.
- [ ] Origin line uniform grey with average on every row; no per-row blue.
- [ ] AccentColor is #0078ff.
