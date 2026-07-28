# MyCoffee — Build Status

Claims + queue + Done log. Claim a work item here before coding (lane rules in
`CLAUDE.md` §4).

## Claims (in progress)

_none_

## Queue (ready)

- [ ] Backend: wire `POST /api/ingest` payloads to real MyCoffee event types (once
      the product brief lands).
- [ ] Backend: implement real brief generation in `GET /api/brief` via `src/vertex.js`.
- [ ] iOS: replace placeholder `ContentView` with the real MyCoffee UI.
- [~] iOS AppIcon: **placeholder** coffee-cup 1024² added (`AppIcon-1024.png`,
      RGB no-alpha) so TestFlight uploads pass. Replace with real brand art later.

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

### Cron routines (per CLAUDE.md §10)
- [ ] iOS dev loop `0 3,9,15,21 * * *`
- [ ] iOS compile check `0 20 * * 3,6`
- [ ] iOS publish `0 20 * * 4,0`
- [ ] Backend loop `0 */3 * * *`
- [ ] Set the account's Actions spending limit (~$40–50/mo, shared with MyHealthOS).

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
