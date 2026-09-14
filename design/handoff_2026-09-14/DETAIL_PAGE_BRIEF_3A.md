# Coffee page — build brief (option 3A)

Authoritative for the coffee detail page. Supersedes `DETAIL_PAGE_FIXES.md`, which stays only as the record of what was wrong. Chrome, icon and value rules in `UPDATE_BRIEF.md` still apply — this document does not repeat them.

Visual reference: section `3a` of `MyCoffee Redesign.dc.html`. `3b` is the rejected alternative.

**Rules of engagement.** Order of content is fixed: photo first, then the sheet. Nothing moves above the photo. No card borders, no dividers, no gradients other than the one named scrim. If something here is genuinely impossible in SwiftUI, leave a `// DEVIATION:` comment saying what you did instead — do not substitute silently. Every item ends with **Acceptance**.

---

## 1. Photo

Full-bleed, edge to edge, **288pt** tall, `.scaledToFill()` clipped, ignoring the top safe area. The status bar sits over it.

A scrim only at the top: **126pt** tall, linear gradient `black 42% → clear`, so white controls hold on a pale bag. No bottom scrim.

Tapping the photo opens it full screen. There is **no expand button** in the corner.

**Acceptance:** the photo reaches all four edges of the top region, the status bar clock is legible on a white bag, and no button floats in the photo's bottom-right.

---

## 2. Photo controls

Four controls, all **44×44pt** hit areas, all **bare** — no circles, no capsules, no material behind them. Lucide outlines at 1.7pt in **white**, each with `.shadow(color: .black.opacity(0.55), radius: 3, y: 1)`.

| Control | Icon | Position |
| --- | --- | --- |
| Back | `chevron-left`, 24pt | top-left, 12pt from the leading edge |
| Favourite | `heart` / `heart-fill`, 22pt | top-right group |
| Share | `share`, 21pt | top-right group |
| Edit | `pencil`, 21pt | top-right group |

The three trailing controls sit in an `HStack(spacing: 0)`, 6pt from the trailing edge. All four align to the same baseline, 50pt from the top of the frame (just under the status bar).

Favourite is the **only** state change: `heart` outline white when off, `heart-fill` white when on. The button does not gain a background, a tint, or a colour when active.

**Acceptance:** no button has a visible background in either state; the only difference between favourited and not is the heart's fill; all four icons are white at 1.7pt.

---

## 3. Sheet

A white surface, corner radius **20pt** on the top two corners only, pulled **-20pt** up over the photo. Horizontal padding **22pt**. It scrolls; the photo scrolls with it (no parallax, no sticky hero).

**It must not clip its own children** — the logo medallion in §4 hangs 40pt above its top edge. Do not put `.clipped()` on it. The rounded corners come from the shape's own fill, and the phone frame clips everything anyway.

**Acceptance:** the medallion's white ring and top corners are fully round, not sliced flat.

---

## 3.1 Shadows and elevation

Three shadows in the whole page, no others.

| Element | Shadow |
| --- | --- |
| Photo controls (§2) | `.shadow(color: .black.opacity(0.55), radius: 3, y: 1)` on the icon itself, so the outline stays legible on a white bag |
| Roaster medallion (§4) | `.shadow(color: .black.opacity(0.16), radius: 14, y: 3)` — the only elevation in the content |
| Sheet (§3) | none. It reads as raised through the corner radius and the -20pt overlap alone |

No shadow on chips, pills, cards, rail thumbs, the review nudge, or the tab bar. No inner shadows, no strokes standing in for shadows. Shadow opacities are fixed values, not `.regularMaterial` or `.shadow(radius:)` defaults.

**Acceptance:** exactly three shadowed things on the page — the four photo icons, the medallion, nothing else.

---

## 4. Roaster medallion

The header element. An **86×86pt** tile, corner radius **22pt**, positioned absolutely at **top: -40pt, leading: 22pt** relative to the sheet — so 40pt of it sits over the photo and 46pt inside the sheet.

- Background `#F3F2E8` (a light neutral; if the roaster's own asset has a background colour, use that instead).
- **White ring 3pt** all round (`.overlay(RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 3))` or an outer shadow spread), plus a soft shadow: `black 16%, radius 14, y 3`.
- Inside: the roaster's logo, **9pt padding**, `.scaledToFit()`.

**Use the mark, not the lockup.** The app already has the roaster logos. Where a logo is a wide lockup — mark plus wordmark, as DAK's is — the wordmark is illegible at 86pt, so render the **square mark region** of the asset: crop to the mark's bounding box with roughly 10% padding and cache that square per roaster. (`design_handoff_coffees_redesign/dak-logo-mark.png` shows the intended cut for DAK.) Where the logo is already square or a standalone mark, use it as-is. Never crop a logo to a circle, never tint it, never render it as a template image. A roaster with no logo shows no tile: fall back to the flag and name alone, and no monogram.

**Acceptance:** the tile overlaps the photo by 40pt, the mark reads clearly, the logo is not circular and not blue.

---

## 5. Roaster line

Beside the medallion, in a row of **min-height 54pt** with **leading padding 100pt** (86 tile + 14 gap), bottom-aligned, 6pt bottom padding.

- Line one: flag emoji 13pt · roaster name **13pt semibold in accent blue** · `chevron-right` 15pt in neutral 400.
- Line two: **11pt neutral** — "Your best roaster · 4.6 avg". When the roaster is not one of your best, drop the qualifier and show "4.6 avg over 31 bags".

Whole row taps through to the roaster's page, medallion included.

**Acceptance:** the roaster name never truncates or ellipsises on a 390pt screen; both lines clear the medallion.

---

## 6. Title

`Gasharu` — **29pt**, heading font, weight 800, tracking **-0.03em**, 16pt below the roaster row, full width, `text-wrap: pretty` equivalent (`.lineLimit(nil)`, no truncation). No actions on this row.

---

## 7. Rating

12pt below the title, one row, baseline-aligned:

- Score **34pt** heading font weight 800, tracking -0.03em, **accent blue**.
- Five stars, **13pt**, 2pt apart, in accent blue. The fifth star is **partial**: mask the filled star to the fractional part of the score (4.1 → 10% of the fifth). Unfilled remainder is a 1.6pt neutral-400 outline star.
- Trailing: the review nudge as a pill — accent-100 background, accent-700 text, 11pt semibold, 7×14pt padding, capsule. Copy: "2 fields to review". Hidden when nothing is missing.

**Acceptance:** 4.1 and 5.0 are visibly different; the pill disappears on a fully reviewed coffee.

---

## 8. Attribute chips

16pt below the rating, wrapping row, 7pt gaps. Capsules, 11pt, 5×11pt padding, `white-space: nowrap`.

1. **Origin** — accent-100 background, accent-700 text, semibold: flag + country + your average for that origin ("🇷🇼 Rwanda 3.8").
2. **Process** — neutral-100 background, neutral-800: "Anaerobic natural".
3. **Altitude** — neutral: "1750 m".
4. **Weight** — neutral: "250 g".

Only the origin chip is ever blue. Omit any chip whose value is missing; never show an empty capsule.

---

## 9. Price and value

20pt below the chips, one row, bottom-aligned.

- **PRICE** — 10pt label, tracking 0.1em, neutral-700; value **22pt** heading 800: "€ 15.95".
- **PER 100 G** — same treatment: "€ 6.38".
- Pushed to the trailing edge: the **value meter** — five pills, each 8×4pt, 3pt apart, capsule; lit pills in accent blue, unlit at accent 15%. Below it, right-aligned, the verdict in **10pt semibold accent**, tracking 0.08em.

Lit count follows the verdict: **GREAT VALUE 5 · FAIR VALUE 3 · OVERPAID 1**. Never all five for every coffee. Verdict logic and suppression rules are in `UPDATE_BRIEF.md` §6 — unchanged.

**Acceptance:** a FAIR VALUE and a GREAT VALUE coffee show a different number of lit pills; an unrated coffee shows neither meter nor verdict.

---

## 10. Purchase facts

22pt below the price row, three rows, 9pt apart, **12pt** type: label in neutral-700 leading, value semibold trailing.

Purchased · Roasted · Farm. Omit a row when its value is unknown; do not print "—".

---

## 11. Flavour profile

22pt below. Label **FROM THE BAG** in 10pt, tracking 0.12em, neutral-700 — then wrapping capsules 8pt below: accent-100 background, accent-800 text, 11pt semibold, 5×11pt padding. One chip per note, in the roaster's own order.

---

## 12. From the roaster — structured, not a wall of prose

This replaces the "Full text" link and the collapsed paragraph. The roaster's copy is parsed into facts; the prose stays one tap away.

- Label **FROM THE ROASTER**, 10pt, tracking 0.12em, neutral-700, 22pt below the flavour section.
- A **2×2 grid**, gaps 12pt row / 18pt column, 10pt below the label. Each cell: caption 10pt tracking 0.06em neutral-600, value **13pt semibold** 2pt under it.
- The four facts, in this order: **VARIETY · FERMENTATION · DRYING · WASHING STATION**. When a field is unknown, drop that cell and let the grid reflow — do not leave a gap or print a dash.
- 14pt below the grid: **Read the full text** in 12pt semibold accent with a 14pt `chevron-right`, opening the roaster's original text in a sheet, verbatim and unedited.

Parsing is best-effort and cheap: match the roaster's own labels first, then a small set of keywords ("anaerobic", "washed", "raised beds", "72 h"). If fewer than two facts can be extracted, skip the grid entirely and show a two-line clamped excerpt with the same "Read the full text" affordance.

**Acceptance:** on a coffee with a long roaster description, no paragraph longer than two lines appears on this page; the full text is reachable in one tap and is not rewritten.

---

## 13. Rail

"More from {roaster}" — rendered **exactly once**, at the bottom of the scroll. Cards ordered by your rating, highest first. Each card shows thumb, title, rating. Bottom content inset = tab bar height + 16pt so the last row clears the tab bar and no digit is sliced.

**Acceptance:** one heading, no clipped ratings, last card scrolls clear of the tab bar.

---

## Checklist

- [ ] Photo 288pt, full-bleed, one top scrim, no expand button.
- [ ] Four bare white controls; only the heart's fill changes.
- [ ] Sheet does not clip; medallion overlaps the photo by 40pt with round corners.
- [ ] Three shadows only: photo icons, medallion, nothing else.
- [ ] Wide lockups cropped to their mark; logo on its own light tile, uncropped to circle and untinted.
- [ ] Roaster name never truncates.
- [ ] Fifth star partial; review pill hides when complete.
- [ ] Only the origin chip is blue.
- [ ] Value pills lit by verdict, not always five.
- [ ] Roaster prose shown as four facts plus "Read the full text".
- [ ] Rail once, with bottom inset.
- [ ] Native tab bar, no capsule overlay (`UPDATE_BRIEF.md` §3).
