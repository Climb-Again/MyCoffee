# MyCoffee — Build Status

External checklist + Done log.

- **Work items** live in GitHub issues, labelled by lane and phase. The approved
  breakdown they come from is **`PLAN.md`**.
- **Claims** live in **`status/<lane>.md`** — one file per lane so six agents never
  conflict. Protocol in `status/README.md`. Do **not** add a Claims section here.

The product brief has landed and been extracted into `PLAN.md`. The source
document now lives in **`Climb-Again/mycoffee-private`** at `brief/MyCoffee app.docx`
— it holds ten years of personal purchase history and screenshots with a profile
avatar, so it must not sit in a public repo. So the four "once the product brief lands" queue items are superseded
by the phased breakdown in `PLAN.md` §8 and the GitHub issues.

## Blocking, do first

- [x] **1024² AppIcon** — placeholder coffee-cup added (`AppIcon-1024.png`,
      independently verified 1024×1024, RGB colour type 2, **no alpha**;
      `Contents.json` carries the `filename`). This was the blocker on the first
      TestFlight upload. Replace with real brand art later — tracked as issue #9.
- [x] **First `publish=true` dispatch** (issue #10) — done, `match` created the
      distribution cert under `PH2NNQ47UB` on an early run and TestFlight uploads
      have been routinely green since (most recently GH Actions run `31127443352`,
      2026-08-06, `main@2cbab7e` — see `status/publish.md`). The Compile and
      Publish routines are live on their normal cron cadence.

> The other three items that used to sit here (`POST /api/ingest` event types,
> real `GET /api/brief` generation, replacing the placeholder `ContentView`) all
> said "once the product brief lands". The brief has landed, so they are
> superseded by the phased breakdown in `PLAN.md` §8 and issues #11–#29 — the
> ingest work by #19, the brief work by the Insights section of #28, and
> `ContentView` by #17 and #18.

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
- [x] Repo is **public** (verified `visibility=public`, 0 forks). Signing material
      and the product brief live in `Climb-Again/mycoffee-private` (verified
      `private=true`); docx + the Apple ID email were purged from git history
      before the flip, confirmed 0 matches from a fresh clone; all 10 prior
      Actions runs deleted so no logs leak; `INGEST_TOKEN`/`APP_TOKEN` rotated.
- [x] `MATCH_PAT` — fine-grained PAT scoped to `mycoffee-private` only, set as an
      Actions secret. `MATCH_GIT_URL` and `Matchfile` (`git_branch("match")`) point
      at it; this repo's workflow permission is `contents: read`.

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
- [x] Compile check `0 20 * * 3,6` — **enabled**
- [~] Publish `0 20 * * 4,0` (Thu + Sun) — **deliberately still disabled.** Going
      public removed the *cost* barrier, not the *risk* one: `match` has never run
      and must mint a distribution cert under `PH2NNQ47UB` where none exists. Do
      that first run **by hand** (issue #10), then enable this routine.
- [x] ~~Set an Actions spending limit~~ — **not needed.** The repo is public, so
      Actions on standard runners (incl. macOS) are free and unlimited. This is
      what the public flip bought.

### Env / secrets for the plan — nothing new required
Verified while planning: the extraction pipeline needs **no new Railway env vars**.
`MEDIA_SIGNING_KEY` defaults to `HMAC(APP_TOKEN,'media')`; `INGEST_RATE_LIMIT_MAX`,
the per-field confidence thresholds, prompt version, worker concurrency and the
spend cap all get defaults in `src/config.js`. Optional overrides only:
- [ ] `WORKER_ENABLED=true` — leave unset until the extraction lane reaches Phase 3.
- [ ] `EXTRACTION_MAX_SPEND_USD=80` — a hard stop for the ~$62 backfill.
- [x] Railway's native GitHub branch trigger is **disconnected** (`5d8b10e`) —
      `railway-deploy.yml` + `RAILWAY_TOKEN` is the sole deployer, no more
      "Needs approval" prompts.

### First build
- [x] Scaffold on `main` → Railway deployed backend (healthcheck green).
- [~] iOS compile check: fires on push to `main` touching `ios/**`, and on a
      `publish=false` dispatch. All prior runs were deleted before the public flip,
      so there is no green run on record yet — the next `ios/**` change proves it.
- [x] **Signing chain PROVEN** (run #6, 2026-07-29). `match` decrypted the repo with
      `MATCH_PASSWORD`, created a distribution certificate under `PH2NNQ47UB`, generated
      the app-store profile, and pushed them encrypted to `mycoffee-private` branch
      `match`: `certs/distribution/DQ2D2T3MR9.{cer,p12}` +
      `profiles/appstore/AppStore_ro.climbagain.mycoffee.mobileprovision`.
      (It also rewrote that branch's `README.md`, as the gotcha predicted.)
- [ ] Dispatch `publish=true` again → first actual TestFlight upload. Run #6 then died
      at `xcodegen generate`: fastlane's `sh` runs in `ios/fastlane/`, so the spec at
      `ios/project.yml` wasn't found. Fixed by wrapping in `Dir.chdir("..")`.
- [x] **Build accepted on the phone and connected to the backend** (Radu, confirmed).
      End-to-end spine proven: signed TestFlight build → Connect screen → `/api/status`
      → Postgres, `db:true` `vertex:true`. NOTE: this build is the **placeholder shell**
      (cup icon + health dot) built from `main`; the real coffee UI is on `ios-staging`
      (12 files under `Sources/Features/`), unmerged, so it is not in this build yet.

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
  Native Railway GitHub branch trigger **disconnected** — CI is now the sole
  deployer, no more "Needs approval" prompts.
