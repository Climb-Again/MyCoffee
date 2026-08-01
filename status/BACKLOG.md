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
| 10 | publish   | 0 | done    | — | **First TestFlight upload GREEN** (run #15, sha `1336a4b` = current `main`). Autopilot fixed legacy-profile-dir + team-from-profile + `CFBundleExecutable`. Processing (~20 min) → check ASC/email |
| 11 | backend   | 0 | done    | — | Migrations 003, 004, 006 — extensions, vocab tables, FX table |
| 12 | data      | 0 | done    | 11 | Migration 005 — vocab seed (42 countries/89 roasters/148 aliases). Consolidated to `main`, Postgres-validated |
| 13 | data      | 0 | done    | — | `src/lib/normalize.js` + `fuzzy.js` + tests — consolidated to `main`, all green |
| 14 | data      | 0 | done    | 11, 13, 34 | `src/lib/vocab.js` — resolution (exact alias + fuzzy fallback) against `004_vocab.sql`, `origin_country_ids` referential-integrity + multi-value origin split, city→country lookup, DB loaders. 24 new tests, 86/86 green |
| 15 | backend   | 0 | done    | — | Gate the Railway deploy on backend tests |
| 16 | backend   | 0 | done    | — | Fix read auth (`requireAnyToken`) + `GET /api/config` |
| 17 | ios-shell | 0 | done    | — | Models, `CoffeeIndex`, filters/facets/bands, sample repo — **merged to `main`, compile-green** (run #18, `29c1def`) |
| 18 | ios-ux    | 0 | done    | 17 | Design system + listing + filter sheet + sort + detail — **merged to `main`, compile-green** (run #18) |
| 19 | backend   | 1 | done    | 11 | Migration 007 + images/media libs + `routes/photos.js` |
| 20 | data      | 1 | ready   | 19 | `ops/` Mac exporter + uploader (osxphotos + sips) |
| 21 | backend   | 2 | ready   | 11, 14 | Migrations 008–009 + snapshot + `routes/coffees.js` |
| 22 | ios-shell | 2 | blocked | 21 | Remote repository + SyncEngine + ImageStore + MutationOutbox |
| 23 | backend   | 3 | blocked | — | Extend `src/vertex.js` — images, responseSchema, thinkingConfig, usage |
| 24 | backend   | 3 | blocked | 21, 23 | Migrations 010–011 + worker + agents + adjudicate + review routes |
| 25 | data      | 3 | blocked | 20, 24 | Phase-0 rules-only pass ($0) + vocabulary confirmation |
| 26 | data      | 4 | blocked | 25 | **5-photo sample → stop and report**, then 25-record tuning, then ask before the full backfill |
| 27 | ios-ux    | 5 | blocked | 22, 24 | Review queue — batch cards, photo auto-zoom, mapping rules |
| 28 | ios-ux    | 5 | blocked | 22 | Insights (with statistical gates) + roaster and country pages |
| 29 | data      | 6 | blocked | 26 | Harden the incremental path — launchd monthly, `awaiting_text` sweep, admin sync |
| 33 | backend   | 0 | done    | — | `vertex:false` — newline in the env var *name*. Fixed `0b38388`; `/api/status` now `vertex:true` |
| 34 | data      | 0 | done    | — | `fx_rates` seed (1510 rows) + `fx.js` — consolidated to `main`, inversion verified vs anchors |
| 30 | ~~human~~ | — | dropped | — | ~~Set the Actions spending limit~~ **OBSOLETE** — repo is public, Actions free (CLAUDE.md §10). Nothing owed. |

**Unblocking is a normal part of the job.** When you finish an item, flip every row
whose `needs` are now all `done` from `blocked` to `ready` in the same commit. If
you don't, the next lane has nothing to pick up.

## Right now

**⚠ 2026-08-01: everything below marked "done, on `main`" is only on this
`claude/*` branch, not on the real `origin/main`.** Verified directly:
`git rev-parse main origin/main` are identical at `0ad0023`, and
`git show origin/main:status/BACKLOG.md` at that commit still lists #12/#13/#34
as `ready`, #17/#18 as `ready`/`blocked`, #10 as `human` — none of the work
this file and `status/*.md` describe as "consolidated onto main" has actually
reached the shared branch. Every session that wrote "branch main" below was
scheduler-assigned to a `claude/peaceful-mccarthy-*` branch and (understandably,
given the branch name never changes across a session's fires) believed pushing
there was equivalent to landing on `main`. It isn't — see full detail and the
verification commands in `status/data.md`'s correction note. **A human or an
integration step with push access to `origin/main` needs to merge this branch
in** before any of this is actually shared with the other lanes' branches
(`ios-staging` etc.) or reflected in the real repo. Until then, read every
"done" row below as "done, on `claude/peaceful-mccarthy-rwi2ql`".

**#14's lane tag corrected `backend` → `data`** (2026-07-31 Backend lane session).
The original GitHub issue #14 body says "Lane: backend" (it predates the lane
split), and this row still carried that tag. But `CLAUDE.md` §4, `status/README.md`
§Lanes, and `PLAN.md` §7 — all written after the issue and all more current —
agree `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` is a
single glob owned by **Data**, not Backend; `fx.js` (also originally in #14's
"backend" scope) already landed under Data's #34 for the same reason
(`status/data.md`). Backend's own claimed ownership this session explicitly
excludes `src/lib/vocab.js`. Leaving the row tagged `backend` would repeat the
exact stale-note failure mode `status/README.md` documents for #33: a lane
executing a note faithfully instead of the current ownership table. Corrected the
tag rather than writing the file out-of-lane. **This was the only `ready` row
tagged `backend` this cycle** — with it reassigned, the Backend lane found no
in-scope work and is stopping cleanly (no invented work). Next `ready` row for
Data is `#20` (already was), now also `#14`.

**Data lane #12/#13/#34 are DONE and consolidated onto `main`** (2026-07-31) — they
had been done three times over on separate fired-session branches that never merged,
so `main` never advanced and each new session redid them. Rebuilt cleanly and
Postgres-validated (59/59 tests). See `status/data.md` and the "un-integrated prior
work" rule in `status/README.md` — **check for stranded lane branches before starting
new work.**

**#14 is now DONE** (2026-08-01 data lane session) — `src/lib/vocab.js` + 24 tests,
86/86 green. See `status/data.md` for detail. Unblocked **#21** (backend, needs
11+14 — both done now), flipped `blocked`→`ready` in the same commit.

Ready rows now:
- **#20** (data) — `ops/` Mac exporter + uploader (unblocked by #19 already).
- **#21** (backend) — migrations 008–009 + snapshot + `routes/coffees.js`, newly
  unblocked by #14 above.

**iOS #17 + #18 are DONE, merged to `main`, and compile-green** (run #18 on `29c1def`,
2026-07-31). `ios-staging` was merged here after its first-ever compile check passed;
the compile lane fixed two first-build Swift errors (`ProcessTag` dot-shorthand,
`CoffeeDetailView` optional-chain `flatMap`) beforehand. Detail lives in
`status/ios-ux.md` / `status/ios-shell.md` (the one-line `ContentView.swift` swap; the
`Hashable` conformances on `Profile`/`SortOption` now declared at origin; the
`Id`/`Eur` acronym-casing convention that matches `.convertFromSnakeCase`). Remaining
iOS work (#22, #27, #28) stays blocked on backend #21/#24. **Publish to TestFlight is
still a separate explicit `publish=true` dispatch — the publish lane's call, not done
here.**

**#11, #15, #16, #19 are done** (backend). Migrations 003/004/006
landed (extensions, vocab tables incl. a fixed `profiles` seed + the `Blend`
pseudo-country, and the `fx_rates` table structure); `railway-deploy.yml` now
gates `deploy` on a `test` job; `GET /api/brief` moved to `requireAnyToken` and
`GET /api/config` shipped; migration 007 (`photos`/`photo_texts`/`assets`) plus
`src/media.js` + `routes/photos.js` + `routes/media.js` landed and were verified
end-to-end against a local Postgres + real JPEG (manifest upsert, dedupe on a
re-run, sha256-mismatch rejection, duplicate-content-hash handling, signed
`/media` URLs). That unblocks **#20**.

**Two P0 gaps found by live smoke test, now owned:**

- **#33 — DONE.** Cause was a newline captured into the env var *name*: the process
  received both `"GOOGLE_PRIVATE_KEY"` (empty) and `"GOOGLE_PRIVATE_KEY
"` (the real
  2,391-byte key). Railway's UI renders these identically **and collapses the rows** —
  it showed 8 variables while the container had 9 — so it was invisible from the
  console, and no redeploy could help. Fixed in code (`0b38388`): `config.js` resolves
  by exact name, falling back to a trimmed-name match. `/api/status` now reports
  `vertex:true`. The earlier `e238f10` lane fix is correct and stays; it addressed a
  different credential shape.
- **#34 — `fx_rates` has structure but no rows.** Now owned, sourced from
  Frankfurter (ECB, no API key). `#14` depends on it. Watch the direction:
  Frankfurter returns EUR→X but the column is `rate_to_eur`, so invert.

**Environment note:** `mycoffee-production-bd43.up.railway.app` is allowlisted, so
lanes can now verify live — `/health`, `/api/status`, `/api/config` and
`/api/brief` were all confirmed green from a session.

**The product brief lives in the OTHER repo.** `Climb-Again/mycoffee-private` is
attached to every lane routine as a second source; the brief is
`brief/MyCoffee app.docx` on its `main`. That is the **authoritative source for the
roaster and country vocabularies** (#12) — `PLAN.md` carries the analysis and the
alias pairs but *not* all ~105 roaster names verbatim, so seeding from `PLAN.md`
alone would produce a silently incomplete vocabulary. Extract it with
`unzip` + parse `word/document.xml` (`<w:p>` paragraphs, `<w:t>` runs); note that
many entries split the name and its `(count)` across **adjacent paragraphs**, so
pair them when parsing.

**Never copy the docx or any personally-identifying excerpt into this public repo.**
Extracted vocabulary *values* are the deliverable; the document is not. It was moved
out precisely because it holds ten years of personal purchase history and
screenshots containing a profile avatar.

**Frankfurter is reachable and verified (#34 unblocked).** Both
`api.frankfurter.app` and `api.frankfurter.dev` are allowlisted. `.app`
301-redirects to `.dev/v1/…`, so **follow redirects** (`curl -L` / `fetch` default)
or call `.dev` directly.

Working request shape, confirmed against a live response — do not guess the params:

```
GET https://api.frankfurter.dev/v1/2015-01-01..2015-01-31?base=EUR&symbols=RON
→ {"amount":1.0,"base":"EUR","start_date":…,"end_date":…,"rates":{"2015-01-02":{"RON":4.4761}, …}}
```

Note it is **`base` + `symbols`** (not `from`/`to`), the path is `/v1/`-prefixed, and
`rates` is keyed by date with a nested currency object. Only ECB business days are
present — expect ~21–22 observations per month, which is the correct set to average.

**Verified inversion anchors.** Frankfurter returns EUR→X; `fx_rates.rate_to_eur`
is "1 unit of quote = N EUR", so invert. Real values:

| Month | EUR→RON | `rate_to_eur` |
|---|---|---|
| 2015-01 | 4.4872 | **0.222856** |
| 2019-06 | 4.7259 | 0.211602 |
| 2024-06 | 4.9767 | **0.200935** |

If a 2015 RON row comes out near `4.49` instead of `0.22`, the direction is
backwards and every RON price will be ~24× too large. Use these three as the test
fixture. RON drifted 4.49 → 5.23 (~17%) across the corpus window, which is exactly
why the rate must be dated rather than flat.

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
