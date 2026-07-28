# MyCoffee — Agent Operating Guide

Autonomous operating guide for this repo (`Climb-Again/MyCoffee`), modeled on
MyHealthOS. Built on the "Health OS" stack per `NEW_APP_SETUP_BRIEF.md`.

## 0. Filled-in tokens (the once-and-done decisions)

| Token | Meaning | Value |
|---|---|---|
| `APP_NAME` | Xcode project + scheme + product name | `MyCoffee` |
| `APP_DISPLAY` | Home-screen name (`CFBundleDisplayName`) | `MyCoffee` |
| `APP_SLUG` | lowercase, no spaces | `mycoffee` |
| `BUNDLE_ID` | reverse-DNS App ID | `ro.climbagain.mycoffee` |
| `BUNDLE_PREFIX` | org prefix | `ro.climbagain` (reused) |
| `REPO` | GitHub repo | `Climb-Again/MyCoffee` |
| `RAILWAY_PROJECT` | Railway project | `mycoffee` |
| `RAILWAY_SERVICE` | Node service | `MyCoffee` (Railway auto-named it after the repo, not `mycoffee-api`) |
| `BACKEND_URL` | Railway public URL | `mycoffee-production-bd43.up.railway.app` |
| `APPLE_TEAM_ID` | Apple team | `PH2NNQ47UB` (ASOCIATIA CLUB SPORTIV CLIMB AGAIN; Apple ID `an Apple ID not recorded here`) |
| `BG_REFRESH_ID` | BGTask identifier | `ro.climbagain.mycoffee.refresh` |
| HealthKit | Uses HealthKit? | **No** |

> ✅ `BACKEND_URL` is live and wired into `ios/MyCoffee/Sources/Store/AppConfig.swift`
> (`defaultBaseURL`) and the smoke-test blocks below. Bump it here + there if the
> Railway domain ever changes.
>
> ℹ️ **Apple team correction:** the setup brief said to reuse `TTR9KS5493`, but the
> only team on Apple ID `an Apple ID not recorded here` is `PH2NNQ47UB`. MyCoffee is registered
> under `PH2NNQ47UB`; the GH secret `APPLE_TEAM_ID` must be `PH2NNQ47UB`. There is
> **no cross-team cert reuse** — `match` creates/manages a distribution cert under
> this team on the first CI run.

## 1. What's live

- **Backend:** `mycoffee-api` on Railway (`mycoffee` project), live at
  `https://mycoffee-production-bd43.up.railway.app`.
- **iOS:** SwiftUI app, XcodeGen-generated, ships to TestFlight via GitHub Actions.
- **AI:** Vertex AI `gemini-2.5-pro` (reused GCP project/SA from MyHealthOS).

## 2. Architecture

```
iPhone app (SwiftUI) ──HTTPS Bearer──▶ Railway (Fastify 5, Node ≥20, ESM)
                                         ├── Postgres (per-app, isolated)
                                         ├── /data volume
                                         └── Vertex AI gemini-2.5-pro (reused SA)
```

- **Backend deploy:** push to `main` touching `backend/**` → `railway-deploy.yml`
  runs `railway up` with `RAILWAY_TOKEN` (~2–3 min). Token-based CI deploy, **not**
  Railway's native GitHub trigger — that trigger gates the automation identity's
  commits on "Needs approval", so it's disconnected on the service.
- **iOS compile check:** push to `main` touching `ios/**` **or** `workflow_dispatch`
  `publish=false` → compile only, no upload (~15–20 min).
- **iOS ship:** `workflow_dispatch` `publish=true` (manual or the publish cron) →
  full build + TestFlight upload (~15–20 min). A push to `main` never uploads —
  upload is always an explicit `publish=true` dispatch.

## 3. Deploy model & the end-of-session push rule

- Push **small** to `main`; Railway + Actions pick it up.
- **End every session with `git push -u origin HEAD`** so the Stop-hook's
  `origin/<branch>..HEAD` range is empty (avoids the unsigned-commit trap).
- **Never force-push / rewrite history.** Don't chase the "Unverified" badge.
- `git pull --rebase` before every push.

## 4. Lane rule (so loops never collide)

- **iOS loop** owns `ios/**`, `certs/`, `profiles/`, `match_version.txt`,
  `.github/workflows/`.
- **Backend loop** owns `backend/**` + `ops/`; owns any `whats_new.json`.
- **Shared:** root docs (`CLAUDE.md`, `BUILD_STATUS.md`) — claim first in
  `BUILD_STATUS.md`.

## 5. dev/ship split

1. **iOS dev loop** — develop on `ios-staging`, merge `main` in, batch 2–4 ready
   items, push `ios-staging` only. Never pushes `ios/**` to `main`, never builds.
2. **iOS compile check** — dispatch `ios-testflight.yml` `publish=false` on
   `ios-staging`; fix reds there.
3. **iOS publish** — merge `ios-staging → main` (the push compile-checks `main`),
   then dispatch `ios-testflight.yml` `publish=true` to ship to TestFlight. Fix any
   red ship the same session.
4. **Backend loop** — every few hours: pick a ready item, ship to `main`, verify
   with a live curl.

## 6. Prioritization / claims

- USED score: `P = 3·U + 2·S + D − 2·E` (Urgency, Scope/value, Delight, Effort).
- Claim before coding in `BUILD_STATUS.md`.
- Batch-ship. `git pull --rebase` before every push.

## 7. Verification without connectors

```bash
BASE="https://mycoffee-production-bd43.up.railway.app"; TOK="${APP_TOKEN:-$INGEST_TOKEN}"
curl -s "$BASE/health"
curl -s "$BASE/api/status" -H "Authorization: Bearer $TOK"
```

> Note: the agent's own sandbox may block outbound to `*.railway.app` via egress
> policy — run these from a machine that can reach Railway.

Expect `/health` → `{"ok":true,"db":true,"service":"mycoffee-api"}`.

## 8. Backend layout

```
backend/
├── package.json  Procfile  railway.json  .env.example
├── migrations/00x_*.sql        forward-only, advisory-locked runner
└── src/
    ├── config.js  db.js  migrate.js  auth.js  vertex.js  server.js
    └── routes/  status.js  ingest.js  brief.js
```

- Start command is **`node src/server.js`** (not an npm wrapper — Railway
  mislabels stops as crashes otherwise). Port binds **before** migrations.
- Auth: `INGEST_TOKEN` for writes, `APP_TOKEN` for reads, either for `/api/status`.
- Vertex: `maxOutputTokens ≥ 8192` (gemini-2.5 is a thinking model).

## 9. iOS layout

```
ios/
├── project.yml         XcodeGen — .xcodeproj is generated in CI, never committed
├── Gemfile             fastlane pinned to match_version.txt (2.237.0)
├── MyCoffee/
│   ├── Info.plist      display name, bg modes, BGTask id
│   ├── Sources/        MyCoffeeApp, ContentView, ConnectView, Store/, API/
│   └── Resources/      Assets.xcassets (AppIcon art still needed — see §11)
└── fastlane/           Matchfile  Appfile  Fastfile (:beta lane)
```

- Backend URL in `UserDefaults` (`backend_base_url`); ingest token in the
  **Keychain** (`service MyCoffee.backend`, `account ingest_token`).

## 10. Cron schedule (staggered vs. MyHealthOS — shared GitHub account)

All UTC. New app fires at **20:00** on **Wed/Sat** (compile) and **Thu/Sun**
(publish) so two macOS runners never fire simultaneously.

| Loop | Cron | macOS cost |
|---|---|---|
| iOS dev loop | `0 3,9,15,21 * * *` | none |
| iOS compile check (Wed, Sat) | `0 20 * * 3,6` | ~15–20 min ea. |
| iOS publish (Thu, Sun) | `0 20 * * 4,0` | ~15–20 min ea. |
| Backend loop | `0 */3 * * *` | none |

> Shared account ⇒ shared 2000 Actions-min/month; macOS is 10×. See brief §7 for
> the cost math (~$40/mo combined) and set an Actions spending limit.

## 11. Manual steps still owed by Radu (not doable from the agent)

See `BUILD_STATUS.md` → "External setup checklist". In short: register the App ID
+ ASC app record, create the Railway project/Postgres/volume, set GH secrets +
Railway env vars, add a real 1024² AppIcon, then dispatch the first builds.

## 12. Gotchas

- App ID + ASC record are **manual** (`produce` has no API-key support).
- Start command must be `node src/server.js`; bind port before migrations.
- `MARKETING_VERSION` must move forward every release or TestFlight won't update.
- Build on `macos-15` / Xcode 26 (iOS 26 SDK required for uploads).
- `match` rewrites the repo-root `README.md` — keep real docs in other `.md` files.
- Keep the repo **private** (`certs/`+`profiles/` are committed match storage).
