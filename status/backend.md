# Lane: Backend

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- [2026-07-31 UTC] Session check: re-verified no `ready` backend row exists.
  `HEAD` even with `origin/main`; `origin/claude/determined-thompson-w06dlc` has
  zero commits beyond `origin/main` (fully merged, nothing stranded).
  `backend/src/lib/vocab.js` still doesn't exist, so #14 (data) isn't done and
  #21 (needs 11, 14) stays `blocked`; #23/#24 unchanged. No `ready` row tagged
  `backend` this cycle. No code changes — stopping cleanly per the work loop.
- [2026-07-31 UTC] Session check: re-verified no `ready` backend row exists.
  `HEAD` was already even with `origin/main` (no stranded `claude/*` work to
  integrate). `backend/src/lib/vocab.js` still doesn't exist, confirming data
  lane's #14 isn't done yet, so #21 (needs 11, 14) stays `blocked`; #23/#24
  remain `blocked` with no state change. No `ready` row is tagged `backend`
  this cycle. No code changes — stopping cleanly per the work loop (do not
  invent work).
- [2026-07-31 UTC] Session audit: only `ready` row tagged `backend` was #14
  (`src/lib/vocab.js`). That file is inside the
  `src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` glob that
  `CLAUDE.md` §4 / `status/README.md` / `PLAN.md` §7 assign to the **Data**
  lane — this session's own ownership boundaries explicitly exclude it, and
  `fx.js` (also originally scoped to #14) already landed under Data's #34 for
  the identical reason. Issue #14's body still says "Lane: backend" because it
  predates the lane split; that stale tag is the same failure mode as #33
  (`status/README.md`). Corrected `status/BACKLOG.md` #14 to lane `data`
  instead of writing the file out-of-lane. No other backend-owned row was
  `ready` (#21/#23/#24 remain `blocked`), so no code changes this session —
  branch `main` — SHA: `02fcac0`
- [2026-07-29 00:00 UTC] #11 Migrations 003, 004, 006 — extensions, vocab tables, FX table (structure only — no `fx_rates` seed, see `status/BACKLOG.md` "Right now") — branch `main` — SHA: `2f2c282`
- [2026-07-29 00:00 UTC] #15 Gate the Railway deploy on backend tests — branch `main` — SHA: `2f2c282`
- [2026-07-29 00:00 UTC] #16 Fix read auth (`requireAnyToken`) + `GET /api/config` — branch `main` — SHA: `2f2c282`
- [2026-07-29 13:45 UTC] #33 (partial) — reconciled `isConfigured()`/`loadCredentials()`
  so a full-SA-JSON credential can't silently report unconfigured, removed the
  temporary `vertexDiag` block (it already did its job: `privateKey` absent,
  the other two vars present), and pushed to exercise a real redeploy. Confirmed
  via the Actions API that `railway-deploy.yml`'s `deploy` job completed
  (`success`) — a guaranteed fresh container. `/api/status` **still** reports
  `vertex:false` afterward, which rules out "stale container" as the cause.
  **Issue is NOT resolved** — moved to `status/BACKLOG.md` #33 as `human`; Radu
  needs to check the literal `GOOGLE_PRIVATE_KEY` value in the Railway
  dashboard directly. — branch `main` — SHA: `e238f10`
  - **UPDATE 2026-07-31: #33 is RESOLVED.** Live `/api/status` now reports
    `vertex:true`. Root cause was a newline captured into the env var *name*
    (`"GOOGLE_PRIVATE_KEY\n"`); fixed in `0b38388` (`config.js` resolves by trimmed
    name). This "NOT resolved / needs Radu" note above is superseded — no human action
    is owed. `BACKLOG.md` #33 is correctly marked `done`.
- [2026-07-29 13:45 UTC] #19 Migration 007 (`photos`/`photo_texts`/`assets`) +
  `src/media.js` (HMAC-signed media URLs, content-addressed derivative paths) +
  `routes/photos.js` (manifest upsert, signed-URL image PUT, sharp derivatives)
  + `routes/media.js`. Verified end-to-end against a local Postgres + a real
  JPEG (not just the auth-gated smoke tests): manifest upsert, dedupe on a
  re-run, sha256-mismatch rejection, duplicate-content-hash re-import, signed
  `/media` fetch. Caught and fixed two real bugs in that process (see commit
  message). Unblocks #20 (data lane). — branch `main` — SHA: `3663b6f`

## Abandoned

_none_
