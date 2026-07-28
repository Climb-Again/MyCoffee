# MyCoffee — Build Status

External checklist + Done log.

- **Work items** live in GitHub issues, labelled by lane and phase. The approved
  breakdown they come from is **`PLAN.md`**.
- **Claims** live in **`status/<lane>.md`** — one file per lane so six agents never
  conflict. Protocol in `status/README.md`. Do **not** add a Claims section here.

The product brief has landed (`MyCoffee app.docx`, extracted and analysed in
`PLAN.md`), so the four "once the product brief lands" queue items are superseded
by the phased breakdown in `PLAN.md` §8 and the GitHub issues.

## Blocking, do first

- [ ] **Real 1024² AppIcon** → `ios/MyCoffee/Resources/Assets.xcassets/AppIcon.appiconset`.
      The slot is currently empty (`Contents.json` has no `filename`). Compiles
      green; App Store Connect rejects it at *processing* time, ~20 min after CI
      reports success. **Blocks the first TestFlight upload.**
- [ ] **First `publish=true` dispatch** — `match` has never run, there is no
      distribution certificate under team `PH2NNQ47UB`, and `certs/`+`profiles/`
      are empty. Do this on the placeholder app, now, while a red ship is cheap to
      diagnose (`PLAN.md` §8).

## External setup checklist (owed by Radu — not doable from the agent)

Infra scaffold is committed. The following are manual / need credentials:

### Apple
- [x] Register App ID `ro.climbagain.mycoffee` (Explicit; no HealthKit). Team `PH2NNQ47UB`.
- [x] Create the App Store Connect app record (iOS, this bundle id). Listing name
      `MyCoffeeOS` ("MyCoffee" was taken); SKU `mycoffee`. Home-screen name stays
      `MyCoffee` via Info.plist — listing name has no code impact.
- [x] ASC API key `.p8` in hand, with Key ID (from filename) + Issuer ID noted.

### GitHub (repo → Settings → Secrets and variables → Actions)
- [x] `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (full `.p8` contents)
- [x] `MATCH_PASSWORD` (new passphrase — must stay constant for this repo's `match` storage)
- [x] `APPLE_TEAM_ID` = `PH2NNQ47UB`  (brief said TTR9KS5493 — wrong for this Apple ID)
- [x] Repo is **private** (verified 2026-07-28).

### Railway — DONE (live at `https://mycoffee-production-bd43.up.railway.app`)
- [x] New project `mycoffee` → service from `Climb-Again/MyCoffee`.
- [x] Service **Root Directory = `backend`**.
- [x] Postgres added and **linked** (`DATABASE_URL = ${{Postgres.DATABASE_URL}}`) + Volume at `/data`.
- [x] Env vars: `GOOGLE_*` (reused from MyHealthOS — full SA JSON in `GOOGLE_PRIVATE_KEY`,
      so `GOOGLE_CLIENT_ID` is not set separately), `VERTEX_AI_REGION=us-central1`,
      fresh `INGEST_TOKEN` + `APP_TOKEN`.
- [x] Auto-deploy on push to `main`; healthcheck green.
- [x] Public URL wired into `BACKEND_URL` (CLAUDE.md, AppConfig.swift `defaultBaseURL`,
      smoke-test blocks).

### Cron routines (per CLAUDE.md §10) — six lanes
- [x] Backend `0 */3 * * *`
- [x] Data extract + validate `30 1 * * *`
- [x] iOS shell `0 3,15 * * *`
- [x] iOS UX `0 9,21 * * *`
- [~] Compile check `0 20 * * 3,6` — **created but disabled** until the first ship
- [~] Publish `0 20 * * 4,0` (Thu + Sun) — **created but disabled** until the first ship
- [ ] **Enable the two macOS routines** once the AppIcon has landed and the first
      manual `publish=true` dispatch has proven `match` + signing under `PH2NNQ47UB`.
      That first run is the riskiest step in the project and must not fire unattended.
- [ ] **Set the account's Actions spending limit** (~$50–60/mo, shared with
      MyHealthOS). Only the two macOS lanes bill; ~$27/mo for MyCoffee.

### Env / secrets for the plan — nothing new required
Verified while planning: the extraction pipeline needs **no new Railway env vars**.
`MEDIA_SIGNING_KEY` defaults to `HMAC(APP_TOKEN,'media')`; `INGEST_RATE_LIMIT_MAX`,
the per-field confidence thresholds, prompt version, worker concurrency and the
spend cap all get defaults in `src/config.js`. Optional overrides only:
- [ ] `WORKER_ENABLED=true` — leave unset until the extraction lane reaches Phase 3.
- [ ] `EXTRACTION_MAX_SPEND_USD=80` — a hard stop for the ~$62 backfill.
- [ ] Disconnect the Railway service's native GitHub branch trigger (CI is the sole
      deployer now via `railway-deploy.yml`) so the "Needs approval" prompts stop.

### First build
- [x] Scaffold on `main` → Railway deployed backend (healthcheck green).
- [~] iOS compile check: runs automatically on push to `main` (merge #1 triggered
      run #1). Confirm it's green.
- [ ] Dispatch `ios-testflight.yml` with `publish=true` → first TestFlight upload
      (`match` populates `certs/`+`profiles/` under team `PH2NNQ47UB`).
- [ ] Accept the build on the phone; enter `BACKEND_URL` + `INGEST_TOKEN` on Connect.

## Done log

- Infra scaffold created (backend Fastify skeleton, iOS SwiftUI/XcodeGen scaffold,
  fastlane `:beta` lane, `ios-testflight.yml` CI, `CLAUDE.md`).
- Apple: App ID `ro.climbagain.mycoffee` + ASC record (listing `MyCoffeeOS`) under
  team `PH2NNQ47UB`; ASC API key in hand.
- GitHub: 5 Actions secrets set; repo confirmed private.
- Scaffold merged to `main` (PR #1). iOS CI set to compile-on-push, upload only on
  `publish=true` dispatch.
- Railway: backend live at `https://mycoffee-production-bd43.up.railway.app`;
  Postgres linked, migrations applied, healthcheck green. `BACKEND_URL` wired in.
- Backend auto-deploy: token-based CI (`railway-deploy.yml` + `RAILWAY_TOKEN`)
  because Railway gates the `ai414` committer on approval and the plan has no spare
  member seat. **Verified green** (run #3): `railway up --service MyCoffee` from the
  repo root (service is named `MyCoffee`; run from root so the service Root
  Directory `backend` selects the app — running from `backend/` hit `backend/backend`).
  Manual step still owed: disconnect the service's native GitHub branch trigger so
  it stops the "Needs approval" prompts (CI is the sole deployer now).
