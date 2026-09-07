# Lane: iOS shell

Branch: `ios-staging` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/ios-shell-history.md`](archive/ios-shell-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

_none_

## Abandoned

- [2026-09-07 04:19 UTC] #130 Add Coffee submit-and-return, pending coffee in store — claimed then un-claimed same session: its `needs` (#118) turned out not to be on `main` despite reading `done` (see the #118 finding below). Genuinely `blocked`, not a stale-claim case.

## Session notes

- **2026-09-07 — found ~30 commits stranded on `origin/claude/adoring-ride-2q9qas`, never merged to `main`; #118 was falsely marked `done`.**
  Ran the Step-0 gate, saw #109/#112/#117/#130/#134 `ready`, claimed #109/#112/#130.
  Before touching #130 (needs #118), checked whether its dependency was real —
  `git branch -r --list 'origin/claude/*'` turned up one branch, and
  `git log origin/main..origin/claude/adoring-ride-2q9qas` showed **~30 unmerged
  commits**: backend #107/#118–129, data #110/#133 (roaster blurbs), and a
  Publish-lane note (`63a3593`) — none on `main`. `a73b520` (#118's backend
  route, `POST /api/coffees/quick-create`) is one of them.

  **Worse: production is running it anyway.** `curl -X POST
  .../api/coffees/quick-create` on the live Railway backend returned `400
  missing_photo_ids` (route matched) rather than 404, even though
  `origin/main`'s `backend/src/routes/coffees.js` has no such route. Someone
  deployed straight from a local checkout of the stray branch (`railway up`
  bypassing `railway-deploy.yml`'s push-to-`main` trigger). The next
  `main`-triggered backend push will silently remove this route from
  production — a live regression waiting to happen, not just a bookkeeping gap.

  **Did not attempt to merge it** — ~30 commits across backend/data/ops is well
  outside an ios-shell session's remit and needs real review (migrations, ops
  scripts I have no context on). Instead: corrected `#118`/`#130`/`#131` back to
  `blocked` in `BACKLOG.md` with the finding inline, un-claimed #130, and
  flagged this to Radu directly. **This needs a human or the backend lane to
  deliberately merge (or cherry-pick) `origin/claude/adoring-ride-2q9qas` onto
  `main` before #130/#131 can safely proceed**, and to verify the next backend
  deploy doesn't regress `quick-create` out of production in the meantime.

- **#109/#112 done this session** — see `BACKLOG.md`'s own DONE notes for the
  implementation summary (value-meter rework + the row-render perf fix).
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
