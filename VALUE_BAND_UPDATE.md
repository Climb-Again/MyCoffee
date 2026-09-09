# Value band — visual update

Delta on the shipped build, coffees list **and** coffee page. Only the value band's appearance changes. **The value logic is untouched** — which band a coffee falls into, the thresholds, and the suppression rules stay exactly as they are in the app. This is about making the five outcomes read apart at a glance.

The five bands, in order, worst to best — the app already assigns these; use whatever labels the app uses:

`1 · 2 · 3 · 4 · 5` → OVERPAID → POOR VALUE → FAIR VALUE → GOOD VALUE → GREAT VALUE (adjust to the app's real strings).

## The problem

Every band renders as blue pills that differ only in how many are lit. Five all-blue variations are hard to tell apart in a list — count is the only signal, and you have to stop and count. The band needs a second, faster channel: **depth**. Keep it in one hue — ink through to the app's accent blue — so it never competes with the coloured verdicts of a red/green scale and stays at home in the app's palette.

## The fix — a black-to-blue depth scale under the existing pill count

Keep the five-pill meter. Keep the lit count as the app sets it (1–5, following the logic). Add a **tone that moves with the band**, running from near-black at the worst to full accent blue at the best, so position and depth agree and either one reads the verdict on its own.

| Band | Lit pills | Lit colour | Verdict text |
| --- | --- | --- | --- |
| OVERPAID | 1 | `#1C1C1E` near-black | near-black |
| POOR VALUE | 2 | `#334155` slate | slate |
| FAIR VALUE | 3 | `#3A6EA5` muted blue | muted blue |
| GOOD VALUE | 4 | `#0A84FF` accent blue | accent blue |
| GREAT VALUE | 5 | `#0078FF` accent blue, bold | accent blue |

Worst = darkest and heaviest, best = the brightest, most saturated blue. The two top bands are both the app blue; GREAT is set apart by all five pills lit and the verdict in **weight 700** rather than 600.

- Unlit pills: the lit colour at **15% opacity**, so the track tints with the band too.
- Verdict text uses the **same** colour as the lit pills, one shared token per band. 10pt semibold (700 for GREAT), tracking 0.08em, as today.
- Pills unchanged in geometry: 8×4pt, 3pt apart, capsule. Same geometry on the list row and the coffee page so the two read as one system.

This gives three agreeing signals — length, tone and word — any of which resolves the band without reading the others.

> Fully monochrome alternative, if you'd rather no blue in the meter at all: run the same five steps in neutral only — `#1C1C1E`, `#3A3A3C`, `#636366`, `#8E8E93`, `#0078FF` for the top step only — i.e. a grey ramp where **only GREAT VALUE lights blue**. Worst-to-best still reads by depth; blue becomes the reward reserved for the best band.

## Contrast

These are chip- and label-scale marks, so the 3:1 floor applies, not 4.5:1. On the light ground `#F3F2E8` / white every step from near-black through the blues clears it with room to spare; the only care point is keeping the two lower-mid steps distinct from each other — hold the exact values above rather than nudging them together.

## Do not

- Do not change which band a coffee gets, the thresholds, or when the meter is hidden.
- Do not use red/green or any second hue — the scale stays in one tonal family, ink to blue.
- Do not add icons (no ✓ / ↑ / ↓) — depth plus length is enough, and glyphs at 4pt are noise.

## Acceptance

- The five bands are distinguishable at a glance in a scrolling list without counting pills.
- Lit pills, unlit track and verdict text all carry the band's one tone.
- An unrated coffee still shows no meter and no verdict.
- The band a given coffee shows is identical to before this change.
