# Nav bar refresh — Recipes + Shop tabs (v2)

Supersedes `design/nav_bar_2026-09-12/BRIEF.md`. Backlog row #195. Visual reference: section `4a` of `MyCoffee Redesign.dc.html`.

## Assets in this package

Everything visual the build needs is in the folder. Nothing is to be drawn by hand.

| Path | What |
| --- | --- |
| `lucide/book-open.svg` | Recipes tab glyph |
| `lucide/shopping-bag.svg` | Shop tab glyph |
| `lucide/settings.svg` | Shop nav gear (already vendored) |
| `lucide/chevron-right.svg` | "Why ›" disclosure (already vendored) |
| `lucide/README.md` | Xcode template-image settings, the `Icon` wrapper, sizes |
| `lucide/index.html` | Contact sheet of the full set |
| `MyCoffee Redesign.dc.html` §4a | The two phones this brief describes |

Same rules as every brief in this folder: native chrome, Lucide outlines, inline styles from the app's `Theme`, no silent substitutions — a `// DEVIATION:` comment when something is truly impossible. Light mode only for this round. No iPad comps — the 700 pt clamp rule from the Coffees list applies, nothing more.

---

## 1. Tab bar — 3 → 5

Native `TabView`, system glass, `.tint(Theme.Colors.accent)`. Order:

```
Coffees   Recipes   +   Shop   Insights
```

The `+` keeps its bounce-back-and-present-sheet behaviour (`RootTabView`). Nothing else about the existing three tabs changes.

### Icons — decided

| Tab | Lucide | Why |
| --- | --- | --- |
| Recipes | `book-open` | A catalogue you look things up in. `notebook-pen` says diary, `beaker` says lab, `chef-hat` says kitchen. |
| Shop | `shopping-bag` | The classic bag — reads "shop" instantly next to a cup and a chart. `bookmark` was considered and dropped: it reads "saved" but not *where*. |

**Stroke is 1.7, not 2.** Every icon shipped so far is 1.7 (`lucide/README.md`); two tabs at 2.0 beside three at 1.7 read heavier. **Both SVGs are supplied** — `lucide/book-open.svg` and `lucide/shopping-bag.svg`. Do not draw, trace or approximate an icon; if a glyph is missing from `lucide/`, stop and ask. **Asset names match the file**, no `lucide-` prefix — the existing sets are `coffee`, `circle-plus`, `bar-chart-3`, and `Icon`/`Lucide.*` look them up by that name. Add `Lucide.bookOpen` and `Lucide.shoppingBag`.

**Acceptance:** five tabs, system bar, all five glyphs at the same visual weight.

---

## 2. Recipes tab

**Correction to v1:** `Features/Brew/BrewCatalogueView` does not exist on `main`. Build the tab; if a Settings-side catalogue exists under another name, promote it, otherwise this is new.

### Layout

Large-title nav bar like Coffees: kicker **10 pt / 0.14 em / accent / semibold** — "48 TRIALS · 12 RECIPES" — over the 30 pt title **Recipes**. No search, no sort.

Four sections stacked, in this order: **RECIPES · DEVICES · GRIND SIZES · TEMPERATURES**. No segmented control — the sections *are* the kinds, and the whole list is short enough to scroll. Section label: **10 pt, 0.12 em tracking, uppercase, neutral-700** — matching the coffee page (v1 said 600; 600 is only for cell captions inside the roaster grid).

Row, 22 pt leading / 16 pt trailing, 10 pt vertical, no dividers:

- **Label** — 17 pt heavy, tracking -0.34, one line.
- **Secondary** — 12 pt neutral-700: the recipe's key parameters ("15 g · 250 g · 94 °C · 3:00") or, for devices/grind/temp, how many recipes use it.
- **Right column, 96 pt, trailing-aligned:** the win count **"7 of 12"** in **22 pt** heavy monospaced digits, one line (`lineLimit(1)`, `fixedSize`) — 26 pt wraps at two digits — and **WON** as a 10 pt / 0.08 em caption beneath. Accent blue when the win-rate is ≥ 60 %, text colour otherwise — the same rule as a ≥ 4.5 rating on Coffees.

Tap a row → **push** (within the Recipes stack) a Coffees list pre-filtered to that option. Do not switch tabs.

### States

- **`won 0 of 1`** — render the row as normal, but the right column in **neutral-400**. That is what "dim, don't hide" means: a trial you lost still counts, it just doesn't shout.
- **No trials at all** — a single empty state under the title: "No brews logged yet." in 17 pt, and one line in 12 pt neutral-700 with an accent link **Pick a coffee to brew ›** that switches to Coffees. No illustration.
- **A section with zero items** (e.g. no temperatures recorded) is omitted, label included.

**Acceptance:** four labelled sections in order, no seg control, right column dims at 0 wins, tap pushes a filtered Coffees list.

---

## 3. Shop tab

### Layout

Same nav bar pattern: kicker "7 SHORTLISTED · LAST 30 DAYS", title **Shop**, one trailing gear (`settings`) opening the extension's scoring settings. Default sort: highest fit-score first, 30-day rolling window; no sort or filter UI this round.

Rows **mirror `CoffeeRowView`** exactly — reuse the view or its sub-views; do not fork the styling:

- 88 pt thumb, radius `Theme.Radius.photo`. **No favourite circle** (a shortlist item cannot be favourited).
- Roaster — 10 pt semibold uppercase, 0.6 tracking, neutral-700, `lineLimit(1)`. Every text line in the middle column is one line, tail-truncated, as in `CoffeeRowView`.
- Title — 17 pt heavy, one line, tail-truncated.
- Origin line — flag + "Ethiopia · experimental" 12 pt neutral-700 (origin · process, as the extension writes it).
- **Freshness line** — 11 pt: "roasted 10d ago" then "seen 11h ago" in neutral-700. Roast age colours only when the extension marks it: ≤ 14 d **accent**, > 60 d **neutral-400** (not green/red — the app has one hue).
- **IN YOUR LIBRARY** micro-tag under the title when the coffee is already owned: 10 pt / 0.08 em / semibold / **accent-700**. It replaces the freshness line's colour cue — an owned coffee needs no freshness nudge.

Right column, **84 pt**, trailing (12 pt narrower than the library row — there is no bag price or meter to hold):

- **Fit-score** in the rating slot: the extension's 0–100 integer, **26 pt heavy monospaced**, accent when ≥ 60, text colour below — matching the extension's own threshold in the screenshots.
- **€/100g** — **12 pt** semibold, monospaced, compact format **"€16.23/100g"** with no spaces (the extension's format; the spaced library format does not fit beside a two-digit score). It is the row's only price line.
- **No value pills.** The value verdict is *your rating* vs price band, and a shortlisted coffee has no rating. Leave the slot empty; do not show the extension's fit pills here — they would read as a value verdict beside library rows that mean something else.

### "Why" — the fit explanation

The extension writes one sentence per coffee ("You've bought Friedhats before; Ethiopia is familiar ground; …"). Show it **collapsed**: a 12 pt accent **Why ›** under the freshness line. Tap toggles the sentence inline — 12 pt neutral-700, full text, no clamp — and flips the label to **Hide**. Tapping anywhere else on the row opens the **source URL in Safari** (`openURL`). One expanded row at a time.

### States

- **No image** — the same neutral-100 tile with a 9 pt "NO PHOTO" caption the library rows use.
- **Empty** — under the title: "Nothing shortlisted yet." 17 pt, then 12 pt neutral-700 "Save coffees from roaster shops with the MyCoffee extension." No install button — the extension is live and installs from the browser, not from here.

**Acceptance:** rows are visually indistinguishable from library rows except: no heart, fit-score instead of rating, single price line, no pills; row tap leaves the app; Why toggles inline.

---

## 4. Changes to the existing design

These land in the same pass because the new tabs expose them.

1. **`Lucide` enum and `Icon` wrapper** gain `bookOpen` and `shoppingBag`; asset names unchanged in style.
2. **`CoffeeRowView`** is split so Shop can reuse it: extract the middle column and the right column into sub-views that take a small `RowFacts` struct (roaster, title, origin line, secondary line, headline number + colour, price lines, optional value rating, optional micro-tag). Coffees keeps rendering exactly as today — this is a refactor with a pixel-identical result, verified by screenshot diff.
3. **Section label token.** Wherever a section label is neutral-600 today, it becomes neutral-700; neutral-600 stays for cell captions only. One search, one change.
4. **Row tap in Recipes pushes a filtered `CoffeesListView`** — that view needs to accept an initial filter argument if it doesn't already.

---

## 5. Pins (unchanged)

Accent `#0078FF`, text `#1C1C1E` on `#FFFFFF`. Three shadow tiers only. No capsule backgrounds on icon buttons; the value pills and the coffee page's review nudge are the only capsules. 44 pt hit target minimum. 700 pt clamp on iPad.

## 6. Non-goals

The `+` behaviour, the three existing tabs' icons, `NavigationSplitView` on iPad, dark mode, iPad comps.
