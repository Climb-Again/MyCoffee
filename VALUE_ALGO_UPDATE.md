# Value algorithm — proposal (#218)

**Status: APPROVED 2026-09-15 — floor at 4.5 (Radu: "floor 4.5"). Ready to build;
see §8 for scope.** Trigger: Radu,
2026-09-15, on a shipped row — *"Anything 4.6 or higher cannot be poor value.
Let's update algo so it's not linear."* The screenshot: SPOJKA Colombia, **4.7 ★,
22,53 € / 11,26 € per 100 g → POOR VALUE**.

Every number below is measured against the live corpus (`/api/snapshot`,
2026-09-15, 414 coffees), not estimated.

## 1. It reproduces exactly, and it is worse than one row

The meter needs both a rating and a price, so it renders on **106 of 414**
coffees (367 are rated; only 114 are priced). Within those 106:

| | today |
|---|---|
| SPOJKA 4.7 @ 11.26 | ratingPct **0.924**, cheapPct **0.114**, score **0.444** → quintile 2 = **POOR VALUE** |
| coffees rated ≥ 4.6 | **15** |
| …of them in POOR or OVERPAID | **5**, including a **5.0 ★ → POOR VALUE** and a **4.8 ★ → OVERPAID** |

So the 4.7 is not an edge case: a third of the library's best coffees are being
called bad buys, and the single worst offender is a **5.0**.

## 2. Why — three causes, only one of which is the formula

Today (`CoffeeIndex.swift`, `cheapForQualityScore`, #139):

```
ratingPct = percentile of rating across all rated coffees
cheapPct  = 1 − percentile of €/100g across all priced coffees
score     = ratingPct^0.65 · cheapPct^0.35        ← weighted geometric mean
band      = library-wide quintile of that score   ← 1…5, band == pill count
```

1. **The trade-off is symmetric, so price can always outvote quality.** At
   0.65/0.35 the weights are fixed for every coffee. SPOJKA's rating term is
   `0.924^0.65 = 0.947` — nearly perfect — but its price term is
   `0.114^0.35 = 0.475`, which halves the score outright. No rating, not even
   5.0, can survive a bottom-decile price.
2. **`cheapPct` reaches exactly 0.** `1 − percentileRank` returns 0 for the most
   expensive bag in the library, and a geometric mean with a zero factor is
   zero. **The priciest coffee you own is guaranteed OVERPAID at any rating.**
3. **The bands are quotas, not judgements.** The band is a quintile *of the
   score*, so exactly 20 % of priced coffees read OVERPAID and 20 % read POOR —
   always, by construction, however good the library gets.

## 3. What does not work, and it is worth knowing why

**Any change that preserves the score's ordering changes nothing.** The band is
a quintile of the score's *rank*, so it is purely ordinal. Clamping `cheapPct`
to a 0.05 floor — the obvious fix for cause 2 — I measured at **0 of 106 rows
changed**. It fixes the divide-by-zero in principle and is still worth keeping
for robustness, but on its own it is a literal no-op. The fix has to **reorder**,
which means it has to be rating-dependent.

## 4. Proposal — the price weight fades as the rating rises

The non-linearity goes in the *weighting*, not the score: a coffee earns the
right to be expensive by being excellent.

```
w(rating) = 0.65 + 0.30 · clamp((rating − 4.5) / 0.5, 0, 1)
cheapPct  = max(cheapPct, 0.05)                    // cause 2, cheap insurance
score     = ratingPct^w · cheapPct^(1 − w)
band      = max(quintile(score), rating ≥ 4.5 ? 3 : 1)   // Radu's rule, as an invariant
```

| rating | w (rating weight) | price weight |
|---|---|---|
| ≤ 4.5 | 0.65 | 0.35 — **unchanged from #139** |
| 4.6 | 0.71 | 0.29 |
| 4.7 | 0.77 | 0.23 |
| 4.8 | 0.83 | 0.17 |
| 5.0 | 0.95 | 0.05 |

**Below 4.5 nothing changes at all**, which keeps #139's 65/35 decision intact
for 90 % of the library; the curve only opens above the point where the app
already treats a rating as special (the `4.5+ ★` filter card, the accent-coloured
rating). It keeps the geometric mean, so "both must be decent" still holds and a
cheap mediocre bag still cannot buy its way to GREAT.

The floor is Radu's rule stated as an invariant rather than a hope. At **4.5**
(his call, 2026-09-15 — the proposal defaulted to the 4.6 he first named) it
shares its anchor with the curve's knee, so one number governs both: from 4.5
upward the price weight starts fading *and* the verdict cannot fall below FAIR.

It fires on **two** rows today, both rated exactly 4.5 — see §7. Above 4.5 it is
inert: the curve alone already lifts all 15 coffees rated ≥ 4.6 out of POOR, so
for Radu's original sentence the floor is pure insurance against a future
corpus.

## 5. Measured effect — every coffee rated ≥ 4.6

| rating | €/100g | today | proposed |
|---|---|---|---|
| 5.0 | 7.20 | GREAT | GREAT |
| 5.0 | 8.02 | GREAT | GREAT |
| 5.0 | 11.46 | **POOR** | **GREAT** |
| 4.9 | 9.98 | FAIR | GREAT |
| 4.9 | 10.03 | FAIR | GREAT |
| 4.9 | 10.03 | FAIR | GREAT |
| 4.8 | 9.16 | GOOD | GREAT |
| 4.8 | 10.80 | **POOR** | GOOD |
| 4.8 | 13.37 | **OVERPAID** | FAIR |
| 4.8 | 25.00 | **OVERPAID** | FAIR |
| 4.7 | 10.40 | FAIR | FAIR |
| **4.7 | 11.27** | **POOR** ← the screenshot | **FAIR** |
| 4.6 | 6.88 | GREAT | GREAT |
| 4.6 | 9.17 | FAIR | GOOD |
| 4.6 | 9.93 | FAIR | FAIR |

Rule violations: **5 → 0.** The 4.8 at 25 €/100 g — nearly twice the next most
expensive bag — settles at FAIR rather than GREAT, which is the intended shape:
excellence buys immunity from *POOR*, not a free pass.

## 6. The cost, stated plainly

**27 of 106 rows change band: 11 up, 16 down.** The demotions are not a bug in
the proposal — they are the quota (cause 3) doing its job. Bands are a fixed
20 % each, so the promotions must push other rows down to pay for them. The
demoted rows are the mid-table: mostly 3.8–4.2 coffees dropping one band. Because
the floor lifts two rows without displacing anyone, the bands no longer come out
exactly 20 % each — 20 / 19 / 24 / 21 / 22 rather than 21 / 21 / 21 / 21 / 22.

## 7. Decided — the floor sits at 4.5 (Radu, 2026-09-15)

The proposal asked 4.6-as-stated vs 4.5, and defaulted to 4.6. Radu chose **4.5**,
and the data says he was right: at 4.6 the floor leaves **two** rows stranded,
not the one §6 originally flagged.

| rating | €/100g | curve alone | floor 4.6 | floor 4.5 |
|---|---|---|---|---|
| 4.5 | 10.03 | POOR | POOR | **FAIR** |
| 4.5 | 20.00 | OVERPAID | OVERPAID | **FAIR** |

The second row is the one that settles it. A **4.5 ★ at 20 €/100 g reading
OVERPAID while a 4.6 ★ at 25 €/100 g reads FAIR** is a one-tenth-of-a-star cliff
across a 5 €/100 g price gap — indefensible on sight, and exactly the class of
result that produced the original complaint. At 4.5 the floor and the curve's
knee share one anchor and that cliff does not exist.

After the change: **0 coffees rated ≥ 4.5 read POOR or OVERPAID** (today: 8).

Still not proposed, and flagged only so the decision is on record: **removing the
quintile quota** (cause 3 — absolute score thresholds instead of a forced 20 %
per band, so "everything I own is good value" becomes expressible). It is the
deepest of the three causes, it changes what the meter *means* rather than how it
ranks, and it should not ride along with a fix Radu asked for narrowly. File it
separately if the demotions in §6 annoy him.

## 8. Scope when approved

- **One file, one lane:** `ios/MyCoffee/Sources/Store/CoffeeIndex.swift` —
  `cheapForQualityScore` plus the two call sites that already share it (`init`'s
  precompute and `valueBand(for:)`'s fallback). **ios-shell** owns `Store/**`.
- **`.value` sort must follow — this is now load-bearing, not theoretical.**
  `coffees(matching:sortedBy:)` orders by `valueScoreByRow`, the raw score. The
  4.5 floor *does* fire (§7), so two rows would sort among the OVERPAID/POOR tail
  while printing FAIR. Sort by `(band, score)` so order and verdict cannot
  disagree.
- **No UI change.** #186's depth ramp, the five labels, the pill geometry and
  the `pillCount == band.rawValue` invariant all stand untouched.
- **Not in scope: `backend/src/lib/scoring.js`.** The extension scores *unowned*
  shop coffees, where there is no rating to weight — it predicts affinity and
  compares it to the mean of the price band. Different problem, deliberately
  different model; this change does not apply to it and must not be copied there.
- **Tests:** the rows in §5 make natural fixtures, with the 5.0 @ 11.46 and the
  4.8 @ 25.00 pinning the curve's intent, and **§7's 4.5 @ 20.00 pinning the
  floor** — it is the one row whose verdict comes from the floor rather than the
  score, so it is the only test that fails if the floor is dropped or set at 4.6.
