# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-shell-history.md`](archive/ios-shell-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

- [2026-09-09 04:26 UTC] #117(a) Unknown postings for the 4 band dimensions — branch `ios-staging`
- [2026-09-09 04:26 UTC] #136 Client API surface for POST /api/coffees/evaluate — branch `ios-staging`
- [2026-09-09 04:26 UTC] #139 Re-weight value algorithm to ~65/35 rating/price — branch `ios-staging`

## Abandoned

_none_

## Session notes

- **2026-09-07 — RETRACTED: a "stranded branch" finding earlier this session
  was my own git mistake, not a real problem.** Mid-session I flipped
  `#118`/`#130`/`#131` to `blocked` and un-claimed `#130`, believing
  `a73b520` (#118's backend route) existed only on `origin/claude/adoring-ride-2q9qas`
  and not on `main` — based on `git merge-base --is-ancestor a73b520 origin/main`
  failing. That check ran against a **stale local `origin/main`**: this session's
  container never ran `git fetch origin main` before the check (only
  `git fetch origin ios-staging`, earlier), so the local `origin/main` ref was
  whatever the container started with, not current. A later `git fetch origin main`
  showed `a73b520` (and the whole ~30-commit range I'd flagged) **is** an
  ancestor of the real `origin/main` — #118 was correctly `done` all along, and
  the "production running an out-of-band deploy" alarm was wrong too (the
  `quick-create` 400 response was just main's own deployed route). Reverted
  `#118`/`#130`/`#131` to their original status in `BACKLOG.md`. Sorry for the
  noise — flagging the mistake here so nobody wastes time chasing a phantom
  merge. Lesson for next time: fetch every ref you're about to diff against,
  not just the one you're checking out.

- **#109/#112/#130 done this session** — see `BACKLOG.md`'s own DONE notes for
  implementation summaries (value-meter rework, the row-render perf fix, and
  the quick-create client wiring). #113 (value band in filters/sort/tiebreaker)
  is now `ready`, unblocked by #109+#112; left for a future session — it's a
  bigger architectural change (postings + `SortOption` need `CoffeeIndex`
  access they don't have today) that deserves its own claim rather than being
  squeezed in after this session's detour. #131 (ios-ux) is unblocked by #130.
  Session notes below are for #112's predecessor, #95:

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
