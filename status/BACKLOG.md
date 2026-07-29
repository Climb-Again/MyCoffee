# Backlog — the work list the lane routines read

**This file, not the GitHub issue list, is what a scheduled lane session reads.**
Routine-fired sessions run without MCP connector tools, so they cannot query the
GitHub API. Everything a lane needs to choose its next task must be here.

Each row mirrors a GitHub issue of the same number — the issue holds the full
spec, this table holds the scheduling metadata. Full design detail is in `PLAN.md`.

**Status values:** `ready` · `blocked` · `claimed` · `done` · `human`
A lane may only pick a row whose status is `ready`, whose lane matches its own,
and **all of whose `needs` are `done`**. Lowest phase first, then lowest number.
After claiming, set the row to `claimed`; after finishing, `done`.

| # | Lane | Phase | Status | Needs | Item |
|---|---|---|---|---|---|
| 9  | publish   | 0 | done    | — | Real 1024² AppIcon — landed on `main` in `c427f3f` (verified 1024×1024, RGB, no alpha) |
| 10 | publish   | 0 | human   | — | First `publish=true` dispatch — prove `match` + signing under `PH2NNQ47UB`. **Unblocked: do this next.** |
| 11 | backend   | 0 | done    | — | Migrations 003, 004, 006 — extensions, vocab tables, FX table |
| 12 | data      | 0 | ready   | 11 | Migration 005 — vocabulary seed from the docx lists |
| 13 | data      | 0 | ready   | — | `src/lib/normalize.js` + `fuzzy.js` + tests |
| 14 | backend   | 0 | blocked | 11, 13 | `src/lib/vocab.js` + `fx.js` |
| 15 | backend   | 0 | done    | — | Gate the Railway deploy on backend tests |
| 16 | backend   | 0 | done    | — | Fix read auth (`requireAnyToken`) + `GET /api/config` |
| 17 | ios-shell | 0 | ready   | — | Create `ios-staging`; models, `CoffeeIndex`, filters/facets/bands, sample repo |
| 18 | ios-ux    | 0 | blocked | 17 | Design system + listing + filter sheet + sort + detail (sample data) |
| 19 | backend   | 1 | ready   | 11 | Migration 007 + images/media libs + `routes/photos.js` |
| 20 | data      | 1 | blocked | 19 | `ops/` Mac exporter + uploader (osxphotos + sips) |
| 21 | backend   | 2 | blocked | 11, 14 | Migrations 008–009 + snapshot + `routes/coffees.js` |
| 22 | ios-shell | 2 | blocked | 21 | Remote repository + SyncEngine + ImageStore + MutationOutbox |
| 23 | backend   | 3 | blocked | — | Extend `src/vertex.js` — images, responseSchema, thinkingConfig, usage |
| 24 | backend   | 3 | blocked | 21, 23 | Migrations 010–011 + worker + agents + adjudicate + review routes |
| 25 | data      | 3 | blocked | 20, 24 | Phase-0 rules-only pass ($0) + vocabulary confirmation |
| 26 | data      | 4 | blocked | 25 | **5-photo sample → stop and report**, then 25-record tuning, then ask before the full backfill |
| 27 | ios-ux    | 5 | blocked | 22, 24 | Review queue — batch cards, photo auto-zoom, mapping rules |
| 28 | ios-ux    | 5 | blocked | 22 | Insights (with statistical gates) + roaster and country pages |
| 29 | data      | 6 | blocked | 26 | Harden the incremental path — launchd monthly, `awaiting_text` sweep, admin sync |
| 30 | human     | — | human   | — | Manual: **set the Actions spending limit** (~$50–60). Railway's native trigger is already disconnected (`5d8b10e`) |

**Unblocking is a normal part of the job.** When you finish an item, flip every row
whose `needs` are now all `done` from `blocked` to `ready` in the same commit. If
you don't, the next lane has nothing to pick up.

## Right now

Ready rows: **#12, #19** (backend-unblocked, data/backend) · **#13** (data) ·
**#17** (ios-shell). The iOS UX lane is blocked on #17 and will correctly no-op
until it lands.

**#11, #15, #16 are done** (backend, this commit). Migrations 003/004/006
landed (extensions, vocab tables incl. a fixed `profiles` seed + the `Blend`
pseudo-country, and the `fx_rates` table structure); `railway-deploy.yml` now
gates `deploy` on a `test` job; `GET /api/brief` moved to `requireAnyToken` and
`GET /api/config` shipped. That unblocks **#12** and **#19**.

**Gap, not a blocker:** `fx_rates` (migration 006) has structure but **no seed
rows**. PLAN.md §1 calls for ~1,320 rows of real ECB monthly averages
(RON/CZK/PLN/HUF/SEK/DKK/NOK/GBP/USD/CHF) — fabricating those numbers would
silently corrupt every historical price, so the Backend lane left the table
empty rather than guess. Whichever lane picks up **#14** (`src/lib/fx.js`)
needs a real seed first; nothing in the backlog currently owns sourcing it.

**#9 is done** — a valid placeholder AppIcon landed on `main` (`c427f3f`), verified
1024×1024, RGB, no alpha. That unblocks **#10**, which is now the next thing to do
and is `human` on purpose: the first `match` run has to create a distribution
certificate under `PH2NNQ47UB` where none exists, and it is the riskiest step in
the project. Run it by hand, on the current placeholder app, while a red ship is
cheap to diagnose. The Compile and Publish routines stay disabled until it passes.

## Spend gates (data lane)

Radu's explicit instruction, in order:
1. Deterministic rules pass over the corpus — **free**, run freely.
2. **5 photos only** (~$0.35) → **stop and report every extracted field** so Radu
   can judge accuracy himself.
3. Only after he approves: 25-record tuning run, then re-adjudicate for $0 until
   thresholds settle.
4. **Never launch the full ~$62 backfill autonomously.** Prepare, set
   `EXTRACTION_MAX_SPEND_USD=80`, then ask.

Confirm current Vertex per-token rates before any LLM run — the figures in
`PLAN.md` §2 are estimates, and Gemini 2.5's thinking tokens dominate output cost.
