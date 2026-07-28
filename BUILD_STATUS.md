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
- [ ] iOS: add a real 1024² AppIcon to `ios/MyCoffee/Resources/Assets.xcassets/AppIcon.appiconset`.

## External setup checklist (owed by Radu — not doable from the agent)

Infra scaffold is committed. The following are manual / need credentials:

### Apple
- [ ] Register App ID `ro.climbagain.mycoffee` (Explicit; no HealthKit). Team `PH2NNQ47UB`.
- [ ] Create the App Store Connect app record (iOS, this bundle id, name/SKU).
- [ ] ASC API key `.p8` (reuse MyHealthOS's team key or create a new one). Note Key ID + Issuer ID.

### GitHub (repo → Settings → Secrets and variables → Actions)
- [ ] `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (full `.p8` contents)
- [ ] `MATCH_PASSWORD` (reuse or new — must match this repo's `match` storage)
- [ ] `APPLE_TEAM_ID` = `PH2NNQ47UB`  (brief said TTR9KS5493 — wrong for this Apple ID)
- [ ] Keep the repo **private**.

### Railway
- [ ] New project `mycoffee` → add service from `Climb-Again/MyCoffee`.
- [ ] Set service **Root Directory = `backend/`**.
- [ ] Add Postgres plugin (auto `DATABASE_URL`) + a Volume mounted at `/data`.
- [ ] Env vars: 6× `GOOGLE_*` (reused from MyHealthOS), plus fresh
      `INGEST_TOKEN` + `APP_TOKEN` (`openssl rand -hex 32` each).
- [ ] Auto-deploy on push to `main`; **turn "Wait for CI" off**.
- [ ] After first deploy, copy the public URL into `BACKEND_URL` (CLAUDE.md,
      AppConfig.swift `defaultBaseURL`, smoke-test blocks).

### Cron routines (per CLAUDE.md §10)
- [ ] iOS dev loop `0 3,9,15,21 * * *`
- [ ] iOS compile check `0 20 * * 3,6`
- [ ] iOS publish `0 20 * * 4,0`
- [ ] Backend loop `0 */3 * * *`
- [ ] Set the account's Actions spending limit (~$40–50/mo, shared with MyHealthOS).

### First build (after the above)
- [ ] Push scaffold to `main` → Railway deploys backend.
- [ ] Dispatch `ios-testflight.yml` with `publish=false` → confirm it compiles.
- [ ] Dispatch with `publish=true` → first TestFlight upload (`match` populates
      `certs/`+`profiles/`).
- [ ] Accept the build on the phone; enter `BACKEND_URL` + `INGEST_TOKEN` on Connect.

## Done log

- Infra scaffold created (backend Fastify skeleton, iOS SwiftUI/XcodeGen scaffold,
  fastlane `:beta` lane, `ios-testflight.yml` CI, `CLAUDE.md`).
