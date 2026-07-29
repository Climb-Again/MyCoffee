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
| 14 | backend   | 0 | blocked | 11, 13, 34 | `src/lib/vocab.js` + `fx.js` |
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
| 25 | data      | 3 | blocked | 20, 24, 33 | Phase-0 rules-only pass ($0) + vocabulary confirmation |
| 26 | data      | 4 | blocked | 25 | **5-photo sample → stop and report**, then 25-record tuning, then ask before the full backfill |
| 27 | ios-ux    | 5 | blocked | 22, 24 | Review queue — batch cards, photo auto-zoom, mapping rules |
| 28 | ios-ux    | 5 | blocked | 22 | Insights (with statistical gates) + roaster and country pages |
| 29 | data      | 6 | blocked | 26 | Harden the incremental path — launchd monthly, `awaiting_text` sweep, admin sync |
| 33 | backend   | 0 | ready   | — | **`vertex:false`** — `isConfigured()` can't see a full-SA-JSON credential. Blocks all extraction |
| 34 | data      | 0 | blocked | — | Seed `fx_rates` from Frankfurter (ECB). **Needs `api.frankfurter.dev` allowlisted** — `.app` only redirects |
| 30 | human     | — | human   | — | Manual: **set the Actions spending limit** (~$50–60). Railway's native trigger is already disconnected (`5d8b10e`) |

**Unblocking is a normal part of the job.** When you finish an item, flip every row
whose `needs` are now all `done` from `blocked` to `ready` in the same commit. If
you don't, the next lane has nothing to pick up.

## Right now

Ready rows: **#12, #19** (backend-unblocked, data/backend) · **#13** (data) ·
**#17** (ios-shell). The iOS UX lane is blocked on #17 and will correctly no-op
until it lands.

**#11, #15, #16 are done** (backend, `2f2c282`). Migrations 003/004/006
landed (extensions, vocab tables incl. a fixed `profiles` seed + the `Blend`
pseudo-country, and the `fx_rates` table structure); `railway-deploy.yml` now
gates `deploy` on a `test` job; `GET /api/brief` moved to `requireAnyToken` and
`GET /api/config` shipped. That unblocks **#12** and **#19**.

**Two P0 gaps found by live smoke test, now owned:**

- **#33 — `/api/status` reports `vertex:false`.** `isConfigured()` requires the three
  individual `GOOGLE_*` vars, but Railway holds the full SA JSON in
  `GOOGLE_PRIVATE_KEY` — which `loadCredentials()` supports and `isConfigured()`
  does not. **Blocks every extraction item (#23–#26).** Silent until the first
  model call, so fix it now.
- **#34 — `fx_rates` has structure but no rows.** Now owned, sourced from
  Frankfurter (ECB, no API key). `#14` depends on it. Watch the direction:
  Frankfurter returns EUR→X but the column is `rate_to_eur`, so invert.

**Environment note:** `mycoffee-production-bd43.up.railway.app` is allowlisted, so
lanes can now verify live — `/health`, `/api/status`, `/api/config` and
`/api/brief` were all confirmed green from a session.

**Frankfurter redirect trap (#34).** `api.frankfurter.app` is allowlisted and
resolves, but it **301-redirects to `api.frankfurter.dev/v1/…`** — a *different*
host that is NOT allowlisted, so following the redirect dies with
`CONNECT tunnel failed, response 403`. Symptom to expect: the allowlist looks
correct, a bare request returns 301, and `curl -L` then fails. **`api.frankfurter.dev`
must be added** before #34 can run in a session. Note also that the live API is
now `/v1/`-prefixed, so the query shape differs from the older `.app` examples —
confirm the exact parameter names against a real response rather than assuming.
Alternative: generate the seed on the Mac and commit the SQL.

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
