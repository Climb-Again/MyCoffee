# Lane: Backend

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

- [2026-07-29 13:00 UTC] #33 — live `/api/config` diagnostic (before removing it)
  showed `projectId`/`serviceAccountEmail` present, `privateKey` **absent**
  (length 0) — the opposite pairing from the issue's first guess, but consistent
  with its real theory: a stale container that hasn't restarted since Railway env
  vars changed. No `backend/**` commit has landed since `787f2d5`, so nothing has
  redeployed. Reconciling `isConfigured()`/`loadCredentials()` (the "worth doing
  regardless" robustness item) plus this claim gives a real `backend/**` diff to
  push, which triggers `railway-deploy.yml` and redeploys the stale container.
  Removing the temporary `vertexDiag` block in the same push — it already did its
  job. Verifying `vertex:true` post-deploy before marking done. — branch `main`
- [2026-07-29 13:00 UTC] #19 Migration 007 + images/media libs + `routes/photos.js`
  — ingestion (manifest, signed-URL image upload, sharp derivatives) — branch `main`

## Done

- [2026-07-29 00:00 UTC] #11 Migrations 003, 004, 006 — extensions, vocab tables, FX table (structure only — no `fx_rates` seed, see `status/BACKLOG.md` "Right now") — branch `main` — SHA: `2f2c282`
- [2026-07-29 00:00 UTC] #15 Gate the Railway deploy on backend tests — branch `main` — SHA: `2f2c282`
- [2026-07-29 00:00 UTC] #16 Fix read auth (`requireAnyToken`) + `GET /api/config` — branch `main` — SHA: `2f2c282`

## Abandoned

_none_
