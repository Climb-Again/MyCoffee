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
| `APPLE_TEAM_ID` | Apple team | `PH2NNQ47UB` (ASOCIATIA CLUB SPORTIV CLIMB AGAIN) |
| `MATCH_REPO` | Private match storage | `Climb-Again/mycoffee-private`, branch `match` |
| `BG_REFRESH_ID` | BGTask identifier | `ro.climbagain.mycoffee.refresh` |
| HealthKit | Uses HealthKit? | **No** |

> ✅ `BACKEND_URL` is live and wired into `ios/MyCoffee/Sources/Store/AppConfig.swift`
> (`defaultBaseURL`) and the smoke-test blocks below. Bump it here + there if the
> Railway domain ever changes.
>
> ℹ️ **Apple team correction:** the setup brief said to reuse `TTR9KS5493`, but the
> only team on the owning Apple ID is `PH2NNQ47UB`. MyCoffee is registered
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

**Six lanes.** The approved work breakdown is `PLAN.md`; the claim protocol and the
full ownership table are `status/README.md`. The repo is public, so Actions are
free — lane count has no cost implication.

| Lane | Branch | Owns |
|---|---|---|
| Backend | `main` | `backend/src/**`, `backend/migrations/**` (except `005_vocab_seed.sql`), `backend/test/**` |
| Data extract + validate | `main` | `ops/**`, `backend/migrations/005_vocab_seed.sql`, `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` |
| iOS shell | `ios-staging` | `ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities}/**` |
| iOS UX | `ios-staging` | `ios/MyCoffee/Sources/{Features,DesignSystem}/**`, `ios/MyCoffee/Resources/**` |
| Compile | dispatch only | nothing — dispatches `publish=false` |
| Publish | `main` | `match_version.txt`, `.github/workflows/**` (match storage is the private repo) |

- **Shared:** root docs (`CLAUDE.md`, `BUILD_STATUS.md`, `PLAN.md`) — claim first.
- The two iOS lanes share `ios-staging` but own **disjoint directories**, so git
  merges them cleanly. Their only seam is the `CoffeeStore` / `CoffeeIndex` API
  surface — shell publishes it, UX consumes it; changing it needs a claim in both.

## 5. dev/ship split

1. **iOS dev lanes** (shell + UX) — develop on `ios-staging`, merge `main` in, batch
   2–4 ready items, push `ios-staging` only. Never push `ios/**` to `main`, never
   build.
2. **Compile lane** — dispatch `ios-testflight.yml` `publish=false` with
   `ref: ios-staging`; fix reds there. Never dispatches `publish=true`.
3. **Publish lane** — merge `ios-staging → main` (the push compile-checks `main`),
   then dispatch `ios-testflight.yml` `publish=true`. **Only this lane may publish.**
   Check for an in-flight `ios-testflight` run first — the concurrency group is
   serial with `cancel-in-progress: false`, so a publish queues behind a compile.
   Fix any red ship the same session.
4. **Backend lane** — every few hours: pick a ready item, ship to `main`, verify
   with a live curl. `railway-deploy.yml` deploys it.
5. **Data lane** — owns the extraction batch. It writes production Postgres, so it
   coordinates with Backend on migrations (see §12).

## 6. Prioritization / claims

- USED score: `P = 3·U + 2·S + D − 2·E` (Urgency, Scope/value, Delight, Effort).
- **Claim before coding in your own `status/<lane>.md`** — one file per lane, so
  claims never conflict. `BUILD_STATUS.md` keeps the external checklist + Done log.
- Batch-ship. `git pull --rebase` before every push.

## 7. Verification without connectors

```bash
BASE="https://mycoffee-production-bd43.up.railway.app"; TOK="${APP_TOKEN:-$INGEST_TOKEN}"
curl -s "$BASE/health"
curl -s "$BASE/api/status" -H "Authorization: Bearer $TOK"
```

> `mycoffee-production-bd43.up.railway.app` **is** on the cloud environment's
> allowed-domains list, so these run from inside a session. `APP_TOKEN` and
> `INGEST_TOKEN` are in the environment too. If a curl returns
> `CONNECT tunnel failed, response 403`, the host isn't allowlisted — **say so
> plainly rather than reporting a pass.** Allowlisted today: the Railway host,
> `api.frankfurter.app` + `api.frankfurter.dev` (#34), and
> `*.blob.core.windows.net` (where GitHub serves Actions log downloads).

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

All UTC. MyHealthOS fires at 09:00, so all macOS work here stays at **20:00** on
non-colliding days — two macOS runners never fire simultaneously.

| Lane | Cron | macOS cost |
|---|---|---|
| Backend | `0 */3 * * *` | none |
| Data extract + validate | `30 1 * * *` | none |
| iOS shell | `0 3,15 * * *` | none |
| iOS UX | `0 9,21 * * *` | none |
| Compile check (Wed, Sat) | `0 20 * * 3,6` | ~15–20 min ea. |
| Publish (Thu, Sun) | `0 20 * * 4,0` | ~15–20 min ea. |

> **The repo is public, so Actions on standard runners — including macOS — are free
> and unlimited.** That is the main reason it's public. The earlier arithmetic
> (10× macOS multiplier, ~200 billed minutes per run, ~$27/mo, a spending limit)
> **no longer applies**. There is no Actions bill and no shared-budget contention
> with MyHealthOS.
>
> Still batch 2–4 ready items per ship. That was never really about cost — it's
> what makes a red ship cheap to diagnose.
>
> Publish days (Thu/Sun) and the 20:00 hour are kept so two macOS runners never
> fire simultaneously with MyHealthOS's, and so compile runs the day before each
> publish.

## 11. Manual steps still owed by Radu (not doable from the agent)

See `BUILD_STATUS.md` → "External setup checklist". In short: register the App ID
+ ASC app record, create the Railway project/Postgres/volume, set GH secrets +
Railway env vars, add a real 1024² AppIcon, then dispatch the first builds.

## 12. Gotchas

- **HARD SIZE BUDGET — app + on-device data stays under 50 MB, always (Radu, 2026-08-10).**
  This is a standing product constraint, not a target. The app binary and the
  persisted snapshot are small and fixed; the thing that grows is the on-device
  **image cache** (`Store/ImageStore.swift`), capped at **30 MB** and evicted at
  launch (`RootView`) to hold the line. Any change that would push app+data over
  50 MB — a bigger cache, bundling large assets, a fatter snapshot payload,
  caching full-res images — **is not a call a lane makes on its own: ask Radu
  whether it's worth exceeding the cap first.** When in doubt, stay under and ask.
- App ID + ASC record are **manual** (`produce` has no API-key support).
- Start command must be `node src/server.js`; bind port before migrations.
- `MARKETING_VERSION` must move forward every release or TestFlight won't update.
- Build on `macos-15` / Xcode 26 (iOS 26 SDK required for uploads).
- `match` rewrites the repo-root `README.md` — keep real docs in other `.md` files.
  (It now does that on `mycoffee-private`'s `match` branch, not here.)

### This repo is PUBLIC — three rules that follow from it

Public so GitHub Actions (including macOS runners) are free. Actions secrets are
**not** exposed by public visibility — they are encrypted at rest and only decrypted
into a runner. But three things change, and two of them are footguns:

1. **Never add a `pull_request` or `pull_request_target` trigger to a workflow that
   references secrets.** Today both workflows trigger only on `push: [main]` and
   `workflow_dispatch`, both of which require write access — so a stranger's fork PR
   cannot run a job that touches a secret. Adding a PR trigger is the single change
   that turns this public repo into a credential leak. Don't.
2. **Actions logs are world-readable.** Never `echo` a secret, never `set -x` around
   one, and remember GitHub's auto-masking fails if a value is transformed (base64'd,
   split across lines). Assume anything printed is published.
3. **No signing material, personal data, or credentials in this repo — ever.** The
   distribution certificate lives in `Climb-Again/mycoffee-private` (branch `match`);
   the product brief lives on that repo's `main`. `MATCH_PAT` reaches it and is
   scoped to that repo alone. `contents:` permission here is `read` — CI has no
   reason to write to this repo.
- **Never push `backend/**` while an extraction job is `running`** — the push
  redeploys and SIGTERMs the worker. Check `GET /api/admin/jobs` first. The lease
  reaper makes it recoverable, not free.
- **Only the Publish lane may dispatch `publish=true`.** Compile and Publish share
  one workflow with a serial concurrency group, so a publish queues behind a compile.
- **The AppIcon is an empty slot** (`Contents.json` has no `filename`). It compiles
  green but App Store Connect rejects it at *processing* time, and the Fastfile sets
  `skip_waiting_for_build_processing: true` — so CI goes green and the rejection
  arrives by email ~20 min later. Fix it before the first `publish=true`.
- **`PHAsset` cannot read Photos titles/captions/descriptions** — they live in the
  Photos database, not the asset. Ingestion is `osxphotos` on the Mac; nothing in
  the plan depends on PhotoKit.
- **An env var that is "definitely set" but reads as empty: enumerate `process.env`
  keys with JSON escaping before touching anything else.** Whitespace can be captured
  into a variable *name* (`"GOOGLE_PRIVATE_KEY\n"`), and Railway's UI renders that
  identically to the clean name — it even collapses the two rows, reporting 8
  variables while the container receives 9. No amount of looking at the UI reveals it.
  `config.js` now resolves by trimmed name so this specific class can't recur, but the
  debugging lesson generalises: when a value looks impossible, measure the key space,
  not the value. Length **0** rather than a truncated length is the tell that the
  lookup missed entirely.
- **A CCR routine/fired session commits to its OWN branch, not `main`.** The first
  publish autopilot did all its winning work on `claude/mycoffee-publish-autopilot-*`
  and dispatched against that branch; `main` did not move until a human merged it. If
  a routine's output must land on `main`, merge its branch afterward — don't assume it
  pushed there. **This bit the data lane hard:** #12/#13/#34 were each built *three
  times* on separate `claude/*` branches because none merged to `main`, so every new
  session saw them still `ready` and redid them — "firing runs with no output." The
  fix is the **"Integrate before you start" rule in `status/README.md`**: a lane must
  check `git branch -r --list 'origin/claude/*'` for stranded prior work before
  claiming, adopt it instead of redoing it, and treat a row as `done` only once it's on
  the shared branch. If lanes keep producing orphan branches, add a small integration
  routine (or a human step) that merges completed `claude/*` lane branches to
  `main`/`ios-staging` on a schedule.
- **`match` archive signing: derive the team from the installed profile, not the
  `DEVELOPMENT_TEAM` secret.** Root cause of publish runs #8–#12: the profile was
  installed, valid and correctly named, yet `xcodebuild archive` failed with "No
  profile for team '<TEAM>' matching 'match AppStore …' found". `match` stamps the
  profile with the team from the ASC API key (`PH2NNQ47UB`), but the archive searched
  under `ENV["DEVELOPMENT_TEAM"]`; the two diverged. Use `sigh_<bundleid>_appstore_team-id`.
  Also mirror the profile into the legacy `~/Library/MobileDevice/Provisioning Profiles/`
  dir — CLI `xcodebuild` scans there even though match 2.237 installs to the Xcode-16 path.
- Gemini 2.5 output tokens are dominated by *thinking* tokens — budget extraction
  cost from output, not input (see `PLAN.md` §2).

### Railway deploy (token-based CI, not Railway's native trigger)

Railway gates deploys from commit authors who aren't members of the Railway team
("Needs approval" on every push), and adding the automation identity costs a paid
seat. So `railway-deploy.yml` deploys with a **Railway project token** instead
(`RAILWAY_TOKEN`, Project → Settings → Tokens, scoped to production) — this
bypasses the committer gate and needs no seat. Three traps, all fast <30 s
failures, all already worked around in the committed workflow — don't reintroduce:

| Symptom | Cause |
|---|---|
| `Service not found` | Wrong `--service`. Railway auto-named the service **`MyCoffee`** after the repo, *not* `mycoffee-api` as planned. Use the canvas name. |
| `Deploy failed` <1 s after "scheduling build" | Root-directory double-up. Run `railway up` from the **repo root**, not `backend/` — it honours the service's Root Directory (`backend`) itself, so running from inside `backend/` makes it look for `backend/backend`. |
| Immediate "no linked project" | An *account* token was used without project context. Prefer a **project** token scoped to the environment. |
