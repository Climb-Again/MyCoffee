# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-shell-history.md`](archive/ios-shell-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## Abandoned

_none_

## Session notes

- **2026-08-28 — #95 value meter is now quality-for-money (`UPDATE_BRIEF.md` §B).**
  `CoffeeIndex.valueBand(for:)` scored **price alone** — the coffee's
  `pricePer100gEur` quintile, inverted — so a cheap bag rated 3.2 read
  `FAIR VALUE`, which is backwards. It now buckets the library into five price
  bands, and inside a coffee's own band compares its rating to the mean rating of
  your bags there: pills are its rating rank within the band, the verdict comes
  from `delta = rating − bandMean`. Unrated or unpriced returns `nil` — no meter
  at all, where the old version still gave an unrated bag a verdict.
  `ValueRating.Band` gains `.overpaid` (replacing `.pricey`) and `band` is now
  **optional**, `nil` meaning "too few rated bags in this band to judge" —
  pills without a verdict rather than a guess.

  **The threshold was measured, not guessed.** Across the 94 rated-and-priced
  coffees, ±0.20 splits them ~26% overpaid / ~48% fair / ~27% great, which is the
  "clearly above / around / clearly below" the brief asks for; ±0.10 gives
  39/28/33 (trigger-happy) and ±0.30 gives 15/67/18 (timid). Band means rise
  3.95 → 4.40 across bands 1–4 then dip to 4.24 in band 5, so the metric does
  carry signal — pricier is not automatically better-liked.

  Two things worth knowing. **Only 94 of 411 coffees are both rated and priced**,
  so the meter is absent on roughly three quarters of the library by design.
  And per-band rating spread varies a lot (SD 0.15 in the cheapest band vs 0.40
  in the priciest), so one absolute cutoff is slightly harsher on the tight band;
  if that ever reads wrong the next refinement is scaling by each band's own SD.
  Both are recorded in the code comments.

  Band stats are precomputed in `CoffeeIndex.init` so `valueBand(for:)` stays
  O(log n) per row instead of rescanning the library for every visible cell.
