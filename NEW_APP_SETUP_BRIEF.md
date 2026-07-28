# Setup Brief — Building a second app on the "Health OS" stack

**Audience:** the autonomous agent that will scaffold and operate a brand-new
iOS app + backend, cloning the proven MyHealthOS infrastructure into fully
separate repos / projects / environments.

**How this brief was derived:** every recipe below is lifted from the live
MyHealthOS repo (`radu-arch/health-os`) — the exact workflow steps, fastlane
lanes, env-var names, Railway config, and loop cadence that are currently
shipping to Radu's phone. Where MyHealthOS hard-codes a value (`HealthOS`,
`ro.climbagain.healthos`, the Railway URL), this brief replaces it with a
`PLACEHOLDER` you fill in once, up front.

---

## 0. Fill these in first (the only decisions that block setup)

Replace every occurrence of these tokens throughout the new repo before you run
anything. Keep a filled copy of this table at the top of the new repo's
`CLAUDE.md`.

| Token | Meaning | MyHealthOS value (reference) | Your value |
|---|---|---|---|
| `APP_NAME` | Xcode project + scheme + product name | `HealthOS` | `__________` |
| `APP_DISPLAY` | Home-screen name (`CFBundleDisplayName`) | `MyHealthOS` | `__________` |
| `APP_SLUG` | lowercase, no spaces — used in repo/paths | `healthos` | `__________` |
| `BUNDLE_ID` | reverse-DNS App ID | `ro.climbagain.healthos` | `ro.climbagain.__________` |
| `BUNDLE_PREFIX` | org prefix | `ro.climbagain` | `ro.climbagain` (reuse) |
| `REPO` | new private GitHub repo | `radu-arch/health-os` | `radu-arch/__________` |
| `RAILWAY_PROJECT` | new Railway project name | `health-os` | `__________` |
| `RAILWAY_SERVICE` | Node service name | `health-api` | `__________-api` |
| `BACKEND_URL` | Railway public URL (known after 1st deploy) | `daring-enjoyment-production-63c5.up.railway.app` | `__________` |
| `APPLE_TEAM_ID` | **reused** — same Apple team | `TTR9KS5493` | `TTR9KS5493` (reuse) |
| `BG_REFRESH_ID` | BGTask identifier | `ro.climbagain.healthos.refresh` | `<BUNDLE_ID>.refresh` |

**Locked-in infra decisions (from Radu, do not re-litigate):**

1. **Apple:** *same* Apple Developer team, *new* App ID + *new* App Store Connect
   app record. Reuse the existing distribution certificate.
2. **GitHub:** *same* account (`radu-arch`), *new private* repo. ⚠️ This means
   both apps share ONE free macOS-minutes budget — see §7 for the cost math and
   the staggered schedule that keeps it manageable.
3. **Google Cloud:** *reuse* the existing GCP project + Vertex service account
   (same 6 `GOOGLE_*` values). Data is still isolated because the new backend
   gets its own Postgres. (Isolation caveat noted in §4-D.)
4. **Railway:** *new* project, *new* Postgres + volume, *new* tokens.

---

## 1. Architecture (identical to MyHealthOS)

```
 iPhone app (SwiftUI, HealthKit)
        │  HTTPS  Authorization: Bearer <INGEST_TOKEN>
        ▼
 Railway service  (Fastify 5, Node ≥20, ESM)
   ├── Postgres (Railway-managed)           ← per-app, isolated
   ├── volume mounted at /data              ← large/sensitive files
   └── Vertex AI  gemini-2.5-pro            ← reused GCP project/SA
        │
 GitHub  radu-arch/<REPO>
   ├── backend/**   → push to main auto-deploys Railway
   └── ios/**       → push to main runs Actions → TestFlight
```

Three moving parts, three deploy triggers:
- **Backend:** push to `main` touching `backend/**` → Railway rebuilds (~2–3 min).
- **iOS ship:** push to `main` touching `ios/**` → GitHub Actions macOS build →
  TestFlight upload (~15–20 min).
- **iOS compile check:** `workflow_dispatch` with `publish=false` → compile only,
  no upload (catches Swift errors cheaply-ish; still a macOS runner).

---

## 2. What's shared vs. separate

| Thing | Shared with MyHealthOS? | Notes |
|---|---|---|
| GitHub account | **Shared** | New private repo; shared macOS-minute quota (§7). |
| Apple Developer team | **Shared** | New App ID `BUNDLE_ID`, new ASC app record. |
| Distribution cert | **Reusable** | Same team ⇒ same cert works; store via `match` in the NEW repo. |
| ASC API key (`.p8`) | **Reusable** | One team-level key can serve both apps; you may reuse the same `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_P8` as GH secrets. |
| GCP project + Vertex SA | **Shared** | Same 6 `GOOGLE_*` values. |
| Railway project | **Separate** | New project, new Postgres, new volume. |
| Backend tokens | **Separate** | Generate fresh `INGEST_TOKEN` / `APP_TOKEN`. |
| `match` git storage | **Separate repo** | Point Matchfile at the NEW repo (`certs/`+`profiles/` live in it). |
| The autonomous agent | **Separate** | New repo's own `CLAUDE.md` + its own cron routines (§6–7). |

---

## 3. Prerequisites checklist (one-time, mostly Radu / account-holder)

- [ ] Apple Developer account access (team `APPLE_TEAM_ID`) — to register the App
      ID and create the ASC app record by hand.
- [ ] App Store Connect **API key** (`.p8`, Admin or App Manager). Reusable from
      MyHealthOS if you still have the `.p8` + key id + issuer id.
- [ ] GitHub `radu-arch` access to create a **private** repo.
- [ ] Railway account (same login is fine) — to create a new project.
- [ ] GCP: the existing service-account credentials (the 6 `GOOGLE_*` values).
- [ ] A GitHub PAT for the agent's CI dispatch/status reads (fine-grained,
      Actions: Read+Write, Contents: Read, scoped to the new repo).
- [ ] Xcode is **not** needed locally — all compiling happens on the macOS runner.

---

## 4. Step-by-step setup

### 4-A. GitHub repo

1. Create private repo `REPO` under `radu-arch`.
2. Seed the directory layout (mirror MyHealthOS):
   ```
   REPO/
   ├── .github/workflows/ios-testflight.yml
   ├── backend/           (Fastify service)
   ├── ios/               (SwiftUI app, XcodeGen)
   ├── certs/  profiles/  (created by `match`, committed here)
   ├── match_version.txt  (pin fastlane, e.g. 2.237.0)
   ├── CLAUDE.md          (the agent's operating guide — §6)
   └── BUILD_STATUS.md    (claims + queue + Done log)
   ```
3. Keep it **private**: committing `certs/`+`profiles/` (match-encrypted) is only
   acceptable in a private repo. Same rule as MyHealthOS — never make it public
   without first moving certs to a dedicated private certs repo.

### 4-B. Apple — App ID + App Store Connect record (by hand, once)

fastlane `produce` can't use API-key auth, so these two are manual:

1. **Certificates, Identifiers & Profiles → Identifiers → +** → App IDs → App →
   Bundle ID **Explicit** = `BUNDLE_ID`. Enable **HealthKit** capability (if the
   new app uses HealthKit; drop it otherwise). Register.
2. **App Store Connect → Apps → +** → New App → platform iOS, select the
   `BUNDLE_ID`, set name/SKU. This creates the app record TestFlight uploads land
   in.
3. **ASC API key** (reuse or create): Users and Access → Integrations → App Store
   Connect API → generate a key (Admin/App Manager). Download the `.p8` **once**.
   Note **Key ID** and **Issuer ID**. These become the three `ASC_*` GH secrets.

### 4-C. Signing / `match`

Reuse the existing distribution cert (same team). In the NEW repo:

1. `ios/fastlane/Matchfile`:
   ```ruby
   git_url(ENV["MATCH_GIT_URL"])      # set by CI to the NEW repo
   git_branch("main")
   storage_mode("git")
   type("appstore")
   app_identifier(["BUNDLE_ID"])
   ```
2. `ios/fastlane/Appfile`: `app_identifier("BUNDLE_ID")` (no apple_id / team id —
   resolved from the ASC API key).
3. First run of the `beta` lane (in CI) will create/import certs+profiles into
   `certs/`+`profiles/` in the new repo, encrypted with `MATCH_PASSWORD`.
   - You can reuse the **same** `MATCH_PASSWORD` value or pick a new one; it just
     has to match whatever's used to encrypt this repo's `match` storage.

### 4-D. Google Cloud / Vertex (reuse project)

Reuse the same 6 values MyHealthOS uses — copy them verbatim into the new
Railway project:

```
GOOGLE_PROJECT_ID
GOOGLE_SERVICE_ACCOUNT_EMAIL
GOOGLE_PRIVATE_KEY          # accepts full SA-JSON pasted in, or the raw key
GOOGLE_PRIVATE_KEY_ID
GOOGLE_CLIENT_ID
VERTEX_AI_REGION            # us-central1
# optional: VERTEX_MODEL   # default gemini-2.5-pro
```

The backend builds credentials in code (`loadCredentials()` in
`backend/src/vertex.js`) — it does **not** use `GOOGLE_APPLICATION_CREDENTIALS`.
`GOOGLE_PRIVATE_KEY` is tolerant: paste the whole service-account JSON (detected
by a leading `{`), or the raw PEM, or base64/escaped-newline forms.

> **Isolation caveat (Radu chose reuse):** sharing the SA means both apps' briefs
> draw on the same Vertex quota and the same credential. That's fine for now —
> DB/data are isolated per app. If you later want blast-radius isolation, create a
> second service account *within the same project* with only the Vertex User role
> and swap these 5 values; no code change needed.

### 4-E. Railway (new project)

1. New project `RAILWAY_PROJECT` → add a **service** from the GitHub repo `REPO`.
2. **Set the service root directory to `backend/`** (Settings → Root Directory).
3. Add a **Postgres** plugin (gives `DATABASE_URL` automatically).
4. Add a **Volume** mounted at `/data` (matches `DATA_DIR` default).
5. `backend/railway.json` (commit this) — same as MyHealthOS:
   ```json
   {
     "build":  { "builder": "NIXPACKS" },
     "deploy": {
       "startCommand": "node src/server.js",
       "healthcheckPath": "/health",
       "healthcheckTimeout": 100,
       "restartPolicyType": "ON_FAILURE",
       "restartPolicyMaxRetries": 10
     }
   }
   ```
   (Use `node src/server.js` directly, **not** an `npm start` wrapper — the wrapper
   made Railway mislabel stops as crashes. The server binds the port first, then
   runs migrations in the background with retry backoff.)
6. **Env vars to set in Railway** (`DATABASE_URL` + `PORT` are auto-provided):
   the 6 `GOOGLE_*` from §4-D, plus fresh app tokens:
   ```
   INGEST_TOKEN   # long random; the iOS app sends this (writes)
   APP_TOKEN      # long random; read endpoints
   ```
   Generate: `openssl rand -hex 32` for each. Store both somewhere safe — the
   agent's verification curls and the iOS Connect screen need them.
7. Deploy trigger: auto-deploy on push to `main`. Turn **"Wait for CI" off** (iOS
   CI is unrelated to backend). After first deploy, copy the public URL into
   `BACKEND_URL`.

### 4-F. Backend scaffold (Fastify)

Mirror `backend/` from MyHealthOS. Minimum viable shape:

- `package.json`: `"type": "module"`, `engines.node ">=20"`, scripts
  `start: node src/server.js`, `dev: node --watch src/server.js`,
  `migrate: node src/migrate.js`, `test: node --test`. Deps: `fastify ^5`,
  `pg ^8`, `google-auth-library ^10`, `@fastify/{compress,etag,helmet,multipart,rate-limit}`,
  `js-yaml`.
- `backend/Procfile`: `web: node src/server.js`.
- `src/config.js` — read env: `PORT`(3000), `HOST`(0.0.0.0),
  `DATABASE_URL`(required, hard-exit if missing), `INGEST_TOKEN`, `APP_TOKEN`,
  `DATA_DIR`(/data), `MAX_UPLOAD_BYTES`(100MB), `RATE_LIMIT_MAX`(300),
  `RATE_LIMIT_WINDOW_MS`(60000), `NODE_ENV`.
- `src/db.js` — single `pg.Pool` on `DATABASE_URL`, TLS `rejectUnauthorized:false`
  unless localhost or `PGSSL=disable`; helpers `query`, `withTransaction`,
  `healthcheck`.
- `src/migrate.js` + `backend/migrations/00x_*.sql` — forward-only runner: apply
  every `*.sql` not in `schema_migrations`, filename order, each in its own
  transaction, guarded by a pg **advisory lock** so overlapping deploys serialize.
  Runs on every boot and via `npm run migrate`.
- `src/auth.js` — Bearer token, constant-time compare. Guards:
  `requireIngestToken` (→ `INGEST_TOKEN`, all writes), `requireAppToken`
  (→ `APP_TOKEN`, reads), `requireAnyToken` (either; e.g. `/api/status`).
- `src/server.js` — `build()` registers helmet (CSP off), rate-limit, multipart,
  compress (threshold 1024), etag; unauthenticated `GET /health` →
  `{ok, db, service}`; then your route plugins. `start()` binds the port
  **before** migrations (background, retry `[1,2,4,8,16]s`); graceful
  SIGTERM/SIGINT.
- `src/vertex.js` — copy from MyHealthOS verbatim; it's app-agnostic.
- `backend/.env.example` — document every env var (no secrets).

Trim the domain routes to what the new app needs (MyHealthOS has ~20 route
plugins: ingest, brief, metrics, biomarkers, genetics, scores, workouts,
flights, insights, status, whats-new). Keep the skeleton (`/health`,
`/api/status`, one ingest route, one brief route) and grow from there.

### 4-G. iOS app scaffold (XcodeGen — no committed `.xcodeproj`)

- `ios/project.yml` (XcodeGen generates the project in CI):
  ```yaml
  name: APP_NAME
  options:
    bundleIdPrefix: BUNDLE_PREFIX
    deploymentTarget: { iOS: "17.0" }
  settings:
    base:
      MARKETING_VERSION: "1.0.0"          # bump forward every release or TestFlight won't auto-update
      CURRENT_PROJECT_VERSION: "1"        # overridden per build by fastlane timestamp
      SWIFT_VERSION: "5.9"
      DEVELOPMENT_TEAM: ${DEVELOPMENT_TEAM}
      CODE_SIGN_STYLE: Manual
  targets:
    APP_NAME:
      type: application
      platform: iOS
      sources: [APP_NAME/Sources, APP_NAME/Resources]
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: BUNDLE_ID
          GENERATE_INFOPLIST_FILE: NO
          TARGETED_DEVICE_FAMILY: "1"     # iPhone only
      # info + entitlements as below
  ```
- Info.plist keys: `CFBundleDisplayName: APP_DISPLAY`,
  `CFBundleShortVersionString: $(MARKETING_VERSION)`,
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`,
  `ITSAppUsesNonExemptEncryption: false`, HealthKit usage strings (if used),
  `UIBackgroundModes: [fetch, processing]`,
  `BGTaskSchedulerPermittedIdentifiers: [BG_REFRESH_ID]`.
- Entitlements (if HealthKit): `com.apple.developer.healthkit: true`,
  `com.apple.developer.healthkit.background-delivery: true`.
- **Backend connection** (mirror `Store/AppConfig.swift` + `API/APIClient.swift`):
  - Base URL in `UserDefaults` key `backend_base_url`, default `https://BACKEND_URL`,
    overridable on a **Connect** screen.
  - Token entered once on Connect, stored in **Keychain** (generic password,
    service `APP_NAME.backend`, account `ingest_token`,
    `kSecAttrAccessibleAfterFirstUnlock`) — never in the repo/binary.
  - Every request: `Authorization: Bearer <ingestToken>`,
    `Content-Type: application/json`, 60s timeout.
- `ios/Gemfile`: `gem "fastlane"`, `gem "xcodeproj"`.
- `ios/fastlane/Fastfile` — the `:beta` lane (copy MyHealthOS, swap `APP_ID` and
  the `HealthOS.xcodeproj`/scheme names):
  1. `create_keychain` (ephemeral, `default_keychain:true`, `unlock:true`,
     `timeout: 21_600`)
  2. `app_store_connect_api_key(key_id:, issuer_id:, key_content: ASC_KEY_P8,
     is_key_content_base64:false, in_house:false)`
  3. `match(type:"appstore", readonly:false, api_key:, team_id:, keychain_name:,
     keychain_password:)`
  4. `xcodegen generate`
  5. `update_code_signing_settings(use_automatic_signing:false,
     path:"APP_NAME.xcodeproj", code_sign_identity:"Apple Distribution",
     profile_name:, bundle_identifier: APP_ID, targets:["APP_NAME"])`
  6. `build_number = Time.now.strftime("%Y%m%d%H%M")`
  7. `build_app(project:"APP_NAME.xcodeproj", scheme:"APP_NAME",
     configuration:"Release", export_method:"app-store",
     xcargs:"CURRENT_PROJECT_VERSION=#{build_number}", signingStyle:"manual")`
  8. `upload_to_testflight(api_key:, skip_waiting_for_build_processing:true,
     distribute_external:false)`

### 4-H. CI workflow

`.github/workflows/ios-testflight.yml` — copy MyHealthOS's verbatim, changing
only `working-directory`/scheme names if `APP_NAME` differs. Key facts to
preserve:

- **Triggers:** `push` to `main` on `ios/**` + the workflow file; plus
  `workflow_dispatch` with a boolean input `publish` (default `true`).
- **Concurrency:** group `ios-testflight`, `cancel-in-progress: false`.
- **Permissions:** `contents: write` (match writes certs back into the repo).
- **Runner:** `macos-15`, `timeout-minutes: 45`, default working-dir `ios`.
- **Xcode:** "Select newest Xcode" step
  (`ls -d /Applications/Xcode_*.app | sort -V | tail -1` → `xcode-select -s`) —
  needs Xcode 26 / iOS 26 SDK for uploads.
- **Steps:** checkout → select Xcode → `brew install xcodegen` →
  `ruby/setup-ruby@v1` (3.3, `bundler-cache:true`) → set git identity (for match)
  → then one of:
  - `publish==false`: `xcodegen generate` +
    `xcodebuild build ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
    (compile check, no upload).
  - otherwise: `bundle exec fastlane beta` (full build + upload).
- **Env / secrets** consumed: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
  `MATCH_PASSWORD`, `DEVELOPMENT_TEAM ← secrets.APPLE_TEAM_ID`,
  `MATCH_GIT_URL = https://x-access-token:${{ secrets.GITHUB_TOKEN }}@github.com/${{ github.repository }}.git`.

### 4-I. First build

1. Push the scaffold to `main`. Backend deploys on Railway; copy the URL into
   `BACKEND_URL` everywhere.
2. Manually dispatch `ios-testflight.yml` with `publish=false` once to confirm it
   compiles.
3. Then dispatch with `publish=true` (or push an `ios/**` change) for the first
   TestFlight upload. `match` populates `certs/`+`profiles/` on this run.
4. Accept the TestFlight build on the phone; enter `BACKEND_URL` + `INGEST_TOKEN`
   on the Connect screen.

---

## 5. Secrets & variables — the complete reference

**GitHub repo secrets** (Settings → Secrets and variables → Actions):

| Secret | Source | Reuse from MyHealthOS? |
|---|---|---|
| `ASC_KEY_ID` | ASC API key id | Yes (same team key) |
| `ASC_ISSUER_ID` | ASC API issuer id | Yes |
| `ASC_KEY_P8` | full `.p8` contents | Yes |
| `MATCH_PASSWORD` | match encryption pw | Reuse or new |
| `APPLE_TEAM_ID` | `TTR9KS5493` | Yes |
| `GITHUB_TOKEN` | auto (Actions) | n/a — provided by Actions |

**Railway env vars** (service settings):

| Var | Value | Reuse? |
|---|---|---|
| `DATABASE_URL` | auto (Postgres plugin) | No — new DB |
| `PORT` | auto | n/a |
| `INGEST_TOKEN` | `openssl rand -hex 32` | **No — new** |
| `APP_TOKEN` | `openssl rand -hex 32` | **No — new** |
| `GOOGLE_PROJECT_ID` | GCP project | Yes |
| `GOOGLE_SERVICE_ACCOUNT_EMAIL` | SA email | Yes |
| `GOOGLE_PRIVATE_KEY` | SA key / full JSON | Yes |
| `GOOGLE_PRIVATE_KEY_ID` | SA key id | Yes |
| `GOOGLE_CLIENT_ID` | SA client id | Yes |
| `VERTEX_AI_REGION` | `us-central1` | Yes |
| `DATA_DIR` | `/data` (default) | — |

**Agent env vars** (the new repo's cron routines, for curl verification):

| Var | Purpose |
|---|---|
| `APP_TOKEN` / `INGEST_TOKEN` | backend read/write verification curls |
| `GH_TOKEN` | fine-grained PAT (Actions R+W, Contents R) for CI dispatch/status |

**iOS runtime (not secrets — user-entered):** `backend_base_url` in UserDefaults;
ingest token in Keychain (`service APP_NAME.backend`, `account ingest_token`).

---

## 6. The autonomous agent — operating guide for the new repo

Give the new repo its own `CLAUDE.md` modeled on MyHealthOS's. The essential
sections:

- **What's live** — the new `BACKEND_URL`, Railway service, TestFlight status.
- **Deploy model** — push small to `main`; Railway + Actions pick it up. Include
  the **end-of-session push rule**: after pushing work to `main`, also
  `git push -u origin HEAD` so the Stop-hook's `origin/<branch>..HEAD` range is
  empty (prevents the unsigned-commit trap). Never force-push / rewrite history.
- **Lane rule** — same two-lane split so loops never collide:
  - **iOS loop** owns `ios/**`, `certs/`, `profiles/`, `match_version.txt`,
    `.github/workflows/`.
  - **Backend loop** owns `backend/**` + `ops/`; owns `whats_new.json`.
  - Shared: root docs (claim first).
- **dev/ship split** (same as MyHealthOS §9.22):
  1. **iOS dev loop** — develops on an `ios-staging` branch, merges `main` in,
     batches 2–4 ready items, pushes `ios-staging` only. **Never pushes `ios/**`
     to `main`, never builds.**
  2. **iOS compile check** — dispatch `ios-testflight.yml` `publish=false` on
     `ios-staging`; fix reds there.
  3. **iOS publish** — merge `ios-staging → main`; that push ships to TestFlight.
     Fix any red ship the same session.
- **Backend loop** — every few hours: pick a ready item, ship to `main`, verify
  with a live curl; flush any pending "What's New" drafts into
  `backend/config/whats_new.json`.
- **Throughput / prioritization / claims** — reuse MyHealthOS's rules verbatim
  (USED score `P = 3·U + 2·S + D − 2·E`, claim-before-coding in `BUILD_STATUS.md`,
  batch-ship, `git pull --rebase` before every push).
- **Verification without connectors** — the same curl block, pointed at the new
  `BACKEND_URL`:
  ```bash
  BASE="https://BACKEND_URL"; TOK="${APP_TOKEN:-$INGEST_TOKEN}"
  curl -s "$BASE/health"
  curl -s "$BASE/api/status" -H "Authorization: Bearer $TOK"
  ```

---

## 7. Cron schedule + cost (⚠️ shared GitHub account)

### Staggered schedule (all UTC) — never overlaps MyHealthOS

MyHealthOS runs everything at **09:00** on its days. The new app runs its CI at a
**different hour (20:00)** and on **different publish days**, so two macOS runners
never fire at the same time.

| Loop | MyHealthOS | **New app** | Cron (new app) | macOS cost |
|---|---|---|---|---|
| iOS dev loop | 00/06/12/18:00 | 03/09/15/21:00 | `0 3,9,15,21 * * *` | none (no build) |
| iOS compile check | Mon, Thu 09:00 | **Wed, Sat 20:00** | `0 20 * * 3,6` | ~15–20 min ea. |
| iOS publish (ship) | Tue, Fri 09:00 | **Thu, Sun 20:00** | `0 20 * * 4,0` | ~15–20 min ea. |
| Backend loop | :30 every 3h | :00 every 3h | `0 */3 * * *` | none (Railway) |

Rationale: publish days (Thu/Sun) don't collide with MyHealthOS publish days
(Tue/Fri); the 20:00 hour guarantees no simultaneous macOS runners even on the
one shared weekday (compile Wed vs. nothing; publish Thu vs. MyHealthOS compile
Thu 09:00 — 11h apart). Compile check runs the day *before* each publish, same
pattern as MyHealthOS.

### Cost math (both apps, one GitHub Free account)

- GitHub Free includes **2000 Actions minutes/month** for the account. Private-repo
  **macOS multiplier is 10×**, so a ~20-min macOS job deducts **~200** minutes →
  the free tier covers **~10 macOS jobs/month total**, *shared across both apps*.
- MyHealthOS alone ≈ **17 macOS jobs/mo** (2 compile + 2 publish per week ≈ 4/wk).
  Adding a second app of the same cadence ≈ **~34 macOS jobs/mo combined**.
- ~10 are free; the remaining ~24 are billed at the macOS overage rate
  (~$0.08/actual-min → ~$1.60 per 20-min job) ≈ **~$40/mo combined**. Set the
  account's Actions **spending limit to ~$40–50/mo**, or builds pause ~2 weeks in.
  (Numbers are approximate — confirm the current per-minute rate in GitHub
  billing.)

### Cheaper alternatives (flag to Radu; not chosen here)

1. **Separate GitHub org/account for the new app** → its own fresh 2000-min budget;
   would likely keep *both* apps at/near free. Cleanest cost fix; costs an extra
   account to manage. (Radu chose "same account" — revisit if the bill bites.)
2. **Fewer ships:** 1 publish/week + 1 compile/week per app roughly halves macOS
   usage.
3. **Skip the compile check** on quiet weeks — publish only when `ios-staging` has
   ready visible work.

Set these as cron routines for the new app's autonomous agent (each pointed at
the new repo/env), mirroring how MyHealthOS's triggers are configured.

---

## 8. Smoke tests (definition of "it works")

```bash
BASE="https://BACKEND_URL"; TOK="<INGEST_TOKEN or APP_TOKEN>"
curl -s "$BASE/health"                       # {"ok":true,"db":true,...}
curl -s "$BASE/api/status" -H "Authorization: Bearer $TOK"
# CI status:
curl -s -H "Authorization: Bearer $GH_TOKEN" \
  "https://api.github.com/repos/REPO/actions/workflows/ios-testflight.yml/runs?per_page=1"
```

- Backend: `/health` green, migrations applied, `/api/status` authorizes.
- iOS: a `publish=false` dispatch compiles green; a `publish=true` run lands a
  build in TestFlight; the phone app connects with `BACKEND_URL` + token.

---

## 9. Gotchas (hard-won from MyHealthOS — don't rediscover these)

- **App ID + ASC app record are manual** — `produce` has no API-key support.
- **Start command must be `node src/server.js`**, not an `npm` wrapper (Railway
  mislabels stops as crashes otherwise). Bind port before migrations.
- **Vertex/Gemini** is a *thinking* model → set `maxOutputTokens ≥ 8192` or JSON
  comes back empty. `loadCredentials()` accepts full SA-JSON pasted into
  `GOOGLE_PRIVATE_KEY`.
- **`MARKETING_VERSION` must move forward** (≥ current) every release or TestFlight
  won't auto-update. Build number = minute timestamp via
  `gym xcargs CURRENT_PROJECT_VERSION=…`.
- **Build on `macos-15` / Xcode 26** — Apple requires the iOS 26 SDK for uploads.
- **`match` rewrites the repo-root `README.md`** when it stores certs — keep real
  docs in other `.md` files. `certs/`+`profiles/` are machine-managed; keep the
  repo **private**.
- **HealthKit read-auth status is unknowable** → persist an `hk_auth_requested`
  flag rather than querying it (if the new app uses HealthKit).
- **End every agent session with `git push -u origin HEAD`** so the Stop-hook
  passes; never force-push to chase the "Unverified" badge.

---

*Derived from the live MyHealthOS repo (`radu-arch/health-os`) on 2026-07-28.
Every command, env-var name, and cadence above is what is currently shipping.*
