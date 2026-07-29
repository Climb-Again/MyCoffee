# Lane: Backend

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

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
