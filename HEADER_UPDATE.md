# Coffee page — header update

Delta on the shipped build. Only what changes; everything not mentioned stays as it is. Visual reference: section `3a` of `MyCoffee Redesign.dc.html`. Icons per `UPDATE_BRIEF.md` §11.

Content order does not change: photo first, then the sheet. Nothing moves above the photo.

---

## 1. Photo controls — delete the capsule

The white glass capsule holding heart / share / edit goes, and so does the blue filled shape behind the active heart. The icons themselves clip inside those containers, which is what looks broken.

Instead, four **bare** controls on the photo — no capsule, no circle, no material, no fill:

| Control | Icon | Position |
| --- | --- | --- |
| Back | `chevron-left` 24pt | top-left, 12pt from the leading edge |
| Favourite | `heart` / `heart-fill` 22pt | top-right group |
| Share | `share` 21pt | top-right group |
| Edit | `pencil` 21pt | top-right group |

All **white**, 1.7pt stroke, 44×44pt hit areas, `.shadow(color: .black.opacity(0.55), radius: 3, y: 1)` on the icon. The trailing three in an `HStack(spacing: 0)`, 6pt from the trailing edge; all four on the same baseline, 50pt from the top of the frame.

Favourite is the only state change: outline heart when off, `heart-fill` when on, **still white, still no background**. Never a blue chip behind it.

To keep white icons legible on a pale bag, the photo gets one scrim: top **126pt**, linear gradient `black 42% → clear`. No bottom scrim.

Also remove the **expand button** in the photo's bottom-right. Tapping the photo opens it full screen.

**Acceptance:** no control on the photo has a visible background in any state; the only difference between favourited and not is the heart's fill.

---

## 2. Roaster medallion — the new header

An **86×86pt** tile, corner radius **22pt**, positioned at **top -40pt, leading 22pt** relative to the sheet: 40pt over the photo, 46pt inside the sheet.

- Background `#F3F2E8`, or the logo asset's own background colour.
- **White ring 3pt**, plus `.shadow(color: .black.opacity(0.16), radius: 14, y: 3)`.
- The logo inside with **9pt padding**, `.scaledToFit()`.

**Use the mark, not the lockup.** Where a roaster's logo is a wide lockup (mark + wordmark, as DAK's is), crop to the mark's bounding box with ~10% padding and cache that square per roaster. Square logos and standalone marks go in as-is. Never crop to a circle, never tint, never a template image. No logo means no tile — flag and name alone, no monogram.

The sheet **must not clip its children**: no `.clipped()` on it, or the medallion's top 40pt and its ring get sliced flat. The phone frame clips anyway.

**Acceptance:** the tile overlaps the photo by 40pt, corners and ring fully round, mark legible, not circular, not blue.

---

## 3. Sheet order — roaster first, then title, then rating

Today the sheet opens with the rating, then the roaster line, then the title. Reverse the first two so the medallion and the roaster own the header.

1. **Roaster row** — beside the medallion: a row of min-height **54pt**, leading padding **100pt** (86 + 14 gap), bottom-aligned, 6pt bottom padding. Line one: flag 13pt · roaster name **13pt semibold accent** · `chevron-right` 15pt neutral-400. Line two: **11pt neutral** — "Your best roaster · 4.6 avg". Whole row, medallion included, taps to the roaster page.
2. **Title** — 16pt below, 29pt heading 800, tracking -0.03em, full width, no actions on this row.
3. **Rating** — 12pt below: score 34pt accent, stars 13pt, review pill trailing.

The rating row keeps its content but loses its position at the top.

**Acceptance:** the roaster name never truncates on a 390pt screen; the order in the sheet is medallion+roaster → title → rating.

---

## 4. Stars — show the fraction

4.1 currently renders five solid stars, which reads as 5.0. Mask the fifth star to the fractional part (4.1 → 10% filled); the remainder is a 1.6pt neutral-400 outline star.

**Acceptance:** 4.1 and 5.0 are visibly different.

---

## 5. "Full text" → four facts

Replace the `Full text` link, and the empty band above it, with structured content.

- Label **FROM THE ROASTER**, 10pt, tracking 0.12em, neutral-700, 22pt below the section above it.
- A **2×2 grid**, gaps 12pt row / 18pt column. Each cell: caption 10pt tracking 0.06em neutral-600, value **13pt semibold** 2pt below.
- Facts in this order: **VARIETY · FERMENTATION · DRYING · WASHING STATION**. Unknown field → drop the cell and let the grid reflow; no dashes, no empty cells.
- 14pt below: **Read the full text**, 12pt semibold accent + `chevron-right` 14pt, opening the roaster's original text verbatim in a sheet.

Parsing is best-effort: the roaster's own labels first, then keywords ("anaerobic", "washed", "raised beds", "72 h"). Fewer than two facts extracted → skip the grid, show a two-line clamped excerpt with the same link.

**Acceptance:** no paragraph longer than two lines on this page; the full text is one tap away and unedited.

---

## 6. Shadows — three, total

| Element | Shadow |
| --- | --- |
| Photo controls | `black 55%, radius 3, y 1` on the icon |
| Roaster medallion | `black 16%, radius 14, y 3` |
| Sheet | none — the corner radius and the -20pt overlap carry it |

Nothing else: no shadow on chips, pills, cards, rail thumbs, the review nudge, or the tab bar.

---

## 7. Still open from the last round

Visible in the current build, not yet fixed:

- **The rail renders twice.** "More from DAK Coffee Roasters" appears again below the first one, clipped behind the tab bar. Render it once.
- **Rail cards are clipped** — ratings sliced in half. Size the rail to its content and add bottom content inset = tab bar height + 16pt.
- **Tab bar is still a custom capsule** with a tinted chip behind the selected tab. Use the system tab bar (`UPDATE_BRIEF.md` §3).

The value meter and its verdicts stay exactly as they are in the app — do not touch that logic.

---

## 8. Roaster page — same logo rules

The roaster page shows the logo in a **circle**, an **orange** star, and the description with raw markdown (`**Convection roasting precision**`) in a wall of prose.

- Logo: the same rounded-square tile as §2 — 22pt radius, own background, contained, never a circle.
- Star and rating: **accent blue**, matching the rest of the app. No orange anywhere.
- Description: strip markdown before display. Render `- **Label** — text` as the same label/value pattern used in §5, one row per bullet; leave the intro paragraph as prose, clamped to three lines with "Read more".

**Acceptance:** no asterisks visible on screen, no orange, logo not circular.
