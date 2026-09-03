# Lane: Publish (autopilot)

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## State — FIRST SHIP IS GREEN ✅

`publish=true` now builds, signs, and uploads to TestFlight end to end. Achieved on
run **#14** (`d601a2c`): `build_app` archived + exported the ipa and
`upload_to_testflight` succeeded (`fastlane.tools finished successfully 🎉`).

### Dispatch token (STEP 0)

No PAT in the environment can POST a `workflow_dispatch`: `GH_ACTIONS_PAT`, `GH_PAT`,
and `GH_TOKEN` all 403 with `X-Accepted-Github-Permissions: actions=write` — none
carry that permission. (A plain read succeeds only because the repo is public.) **The
GitHub MCP server's app installation does have `actions=write`**, so the autopilot
dispatches via `mcp__github__actions_run_trigger` (`run_workflow`), not curl+PAT.

### How the ship was unblocked (run history)

- **#5** → failed at `match` (git auth). Fixed earlier by the org-scoped `MATCH_PAT`.
- **#6** → `match` succeeded (cert `DQ2D2T3MR9` under `PH2NNQ47UB`). Failed at
  `xcodegen generate` cwd. Fixed earlier (`Dir.chdir`).
- **#8 / #10** → archive failed: `No profile for team '…' matching 'match AppStore
  ro.climbagain.mycoffee'`. Not location, not name — run-#12 diagnostics proved the
  profile was installed (both dirs), valid, correctly named, with the identity in
  the keychain. **Root cause: team mismatch.** `match` stamps the profile with the
  team from the ASC API key (`PH2NNQ47UB`), but the archive searched under
  `ENV["DEVELOPMENT_TEAM"]` (the `APPLE_TEAM_ID` secret); the two diverged. Fixed in
  `635a822` by deriving the archive team from `sigh_*_team-id`. (`2b165c4`'s explicit
  manual-signing xcargs/export_options and `526d34e`'s legacy-dir profile mirror are
  retained but were not the fix.)
- **#13** → team fix worked: archived + exported the ipa in 142 s. Upload then
  rejected by ASC: `Invalid Bundle … does not contain a bundle executable` (409).
  The hand-written `Info.plist` (`GENERATE_INFOPLIST_FILE=NO`) had no
  `CFBundleExecutable`, which modern Xcode does not auto-inject. Fixed in `d601a2c`
  (`CFBundleExecutable = $(EXECUTABLE_NAME)`).
- **#14** → green. First TestFlight ship. (Run-#12 diagnostics block removed
  afterward so the recurring publish stays clean.)

### ~20-minute processing caveat

CI is green, but `skip_waiting_for_build_processing: true` means the upload returns
before App Store Connect finishes *processing* the build (~20 min, async, notified by
email). The historical AppIcon footgun (empty icon slot → processing rejection) is
**already resolved**: `AppIcon-1024.png` is a real 1024×1024, 8-bit RGB, **no-alpha**
PNG, so this ship should process cleanly. A processing rejection, if it ever happens,
is invisible in the green CI run — check ASC / email.

## Claimed

_none_

## Done

### 2026-09-03 UTC (Thu cron): nothing to ship — no dispatch this session

Step 0: `origin/main..origin/ios-staging` = **0** commits (`ios-staging` tip
`ea8c3b3` is exactly the merge-base with `main` — no unmerged iOS work).
`status/publish.md`'s own last entry was stale (still showed run #86 BLOCKED
on `MATCH_PAT`), so before trusting the "nothing new" shortcut I checked the
Actions API directly: **run #88** (`workflow_dispatch`, `publish=true`,
`680ab2a`) completed **success** 2026-09-02T10:27–10:29 UTC — `680ab2a`'s
`Build & upload to TestFlight` step ran for real, not skipped. This matches
`status/BACKLOG.md` #108, which another session/human had already marked
"RESOLVED 2026-09-02" after Radu rotated `MATCH_PAT`, but no one had backfilled
this file — logging it now so the next session doesn't re-diagnose the same
gap.

Diffed `ios/**` and `.github/workflows/**` between the shipped SHA (`680ab2a`)
and current `origin/main` (`0bf798a`): the only change is a new
`.github/workflows/backlog-check.yml` (row-uniqueness CI, doesn't touch the
iOS pipeline). Everything else landed on `main` since #88 (#106, #107,
#109–#124) is backend-only (`backend/**`, migrations, `status/BACKLOG.md`) —
deployed continuously by Railway, not the iOS TestFlight pipeline. So the app
binary at the current `main` HEAD would be byte-identical to what #88 already
uploaded. No dispatch — a re-ship would just burn a build slot for zero user-
visible change. Next publish session: same check, but note the real signal is
"any `ios/**` / `.github/workflows/ios-testflight.yml` / `Fastfile` diff since
`680ab2a`", not just the `ios-staging` gap, since backend work keeps moving
`main`'s SHA without touching the app.

### 2026-08-30 UTC: BLOCKED — `MATCH_PAT` rejected by GitHub, filed as BACKLOG #106 (human)

Step 0: `origin/main..origin/ios-staging` was **10** commits — real UX work
(#100–#105: real dark palette, one-flag-per-origin-country, redesign v2 chrome/
bottom bar/pie charts, coffee-link navigation fix, quality-for-money value meter,
process oval + camera in Add Coffee). Not a no-op.

Step 1 (dispatch token): `GH_ACTIONS_PAT` is set in-env and unused directly —
went straight to the GitHub MCP connector (`mcp__github__actions_run_trigger`,
`run_workflow`) per the standing note above that it's the one credential proven
to carry `actions:write`; no need to burn a probe dispatch against the untested
env PATs given that note already established they lack the permission.

Step 2 (merge): `ios-staging` tip `ea8c3b3` was compile-green (run **#84**,
`33307620480`, success). Merged `origin/ios-staging` into `main` — one conflict,
`status/backend.md`: `main`'s copy still carried the full 2026-08-05→08-14
session-log block that ios-staging's #92 archival had already moved verbatim
into `status/archive/backend-history.md` (confirmed by grepping matching
section headers in the archive file before resolving) — took ios-staging's side
(the block, already duplicated in the archive) and kept `main`'s newer prose
above/below it. `status/BACKLOG.md` had **zero** diff between the two branches
pre-merge — already in sync, no reconciliation needed this cycle. Pushed as
`b49becc`. That push's own compile-check (run **#85**, `33332555714`) went
green.

Step 3 (dispatch): No `ios-testflight` run was in-progress; dispatched
`publish=true` on `main` (run **#86**, `33332564889`) — it correctly queued
behind #85 (serial concurrency) then ran. **Failed in 3 s** at the `match` step:

```
Cloning into '.../d20260830-2838-6rxohn'...
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/Climb-Again/mycoffee-private.git/'
[!] Error cloning certificates git repo, please make sure you have access to the repository
```

Root cause is the `MATCH_PAT` secret itself, not code: `ios-testflight.yml`
builds `MATCH_GIT_URL` as `https://x-access-token:${{ secrets.MATCH_PAT }}@github.com/...`
(the correct fine-grained-PAT format), and nothing in `Fastfile`/the workflow
changed since run #77's green ship — so the token GitHub is rejecting is the
same one that worked then. This is a repeat of run #5's exact failure (see
"How the ship was unblocked" above), which was fixed back then by installing an
org-scoped `MATCH_PAT`; the most likely explanation is the fine-grained PAT
expired (they carry a mandatory expiry) or was revoked/rotated outside this
session's visibility. **Not fixable by a lane** — no session has the access to
mint or rotate a PAT for `Climb-Again/mycoffee-private` on Radu's behalf.
Filed as `status/BACKLOG.md` **#106**, tagged `human`, with the exact secret
path Radu needs to update. Stopping here per the "6 iterations, full diagnosis"
rule — but this isn't a flake to retry; every retry would fail identically and
instantly until the secret is replaced.

**State:** `main` is merged and compile-green (`b49becc`, includes #100–#105).
TestFlight upload is the only blocked step. Once Radu updates `MATCH_PAT`,
re-dispatching `publish=true` on `main` at this same SHA should go green with
no further code changes.

## Done (earlier)

- First `publish=true` TestFlight ship green (run #14). Fixes: MCP-app dispatch,
  team-from-profile (`635a822`), `CFBundleExecutable` (`d601a2c`); retained
  legacy-dir profile mirror (`526d34e`).

- **2026-08-06 (autopilot session) — routine ship, still green, no fixes needed.**
  Before dispatching, checked `ios-staging` for unmerged work per CLAUDE.md §5 and
  found one real commit not yet on `main`: `ef50a07` (`CoffeeStore.loadBrief()` +
  durable `resolveReview`/`dismissReview` via `MutationOutbox`, dropping 4xx
  responses instead of retrying them forever — a real bug fix, not just plumbing).
  The other two commits in `origin/main..origin/ios-staging` (`aa7997a`, `f43e4c4`)
  were byte-identical diffs to commits already on `main` under different hashes
  (verified via `git diff <rev>^ <rev> | git hash-object --stdin` on both sides) —
  an artifact of the "off-lane push to main" incident `status/ios-shell.md`
  documents, not new work. Cherry-picked `ef50a07` onto `main` (one conflict, in
  `status/ios-shell.md`'s own `## Done` log — a documentation-only concurrent
  append, resolved by keeping both sides' notes) → pushed as `2cbab7e`.
  Dispatched `publish=true` on `main@2cbab7e`: GH Actions run **`31127443352`**
  completed **success** in ~2 min (`match` 3s, `build_app` 40s,
  `upload_to_testflight` 40s) — log-verified real archive + sign + upload to ASC
  app `6795523219`, not a skipped step. First dispatch this session was green, so
  the loop's fix-and-retry path was never needed. Processing (~20 min, async,
  `skip_waiting_for_build_processing`) unconfirmed — check TestFlight/email.
  Also corrected `BUILD_STATUS.md`'s "Blocking, do first" section, which still
  described the first `publish=true` dispatch as pending — it had been green for
  several cycles (runs on 8/4, 8/5, confirmed real via job logs, and now 8/6).

- **2026-08-13 (autopilot session, Thu cron) — routine ship, still green, no fixes
  needed.** Checked for an in-flight run first (none) and for stranded `ios-staging`
  work per CLAUDE.md §5: the only unmerged commit (`f8e43be`) was a docs-only
  session-check note (no iOS code), so no merge was needed before shipping.
  Dispatched `publish=true` on `main@d1009d1` via
  `mcp__github__actions_run_trigger` (no PAT in the environment carries
  `actions:write` — same as every prior run; `GH_ACTIONS_PAT`/`GH_PAT`/`GH_TOKEN`/
  `GITHUB_TOKEN` all still 403 on the dispatch endpoint, confirmed again this
  session). Run **`31738925456`** completed **success** in ~2 min — job log
  confirms `Build & upload to TestFlight` actually ran (96 s, not skipped); the
  `Compile check (no upload)` step was skipped as expected for a `publish=true`
  ref. First dispatch this session was green, so the loop's fix-and-retry path
  was never needed. Also corrected a stale unchecked box in `BUILD_STATUS.md`'s
  "First build" section that still described the first `publish=true` dispatch as
  pending, several ships after run #14 proved it. Processing (~20 min, async,
  `skip_waiting_for_build_processing`) unconfirmed — check TestFlight/email.

- **2026-08-16 (autopilot session, Sun cron) — merged real unmerged `ios-staging`
  work into `main` before shipping (CLAUDE.md §5 step 3), not just a docs-only
  session check this time.** `git diff origin/main..origin/ios-staging --stat`
  showed substantial real code: `ZoomableImageView.swift` (new), `CoffeeDetailView`,
  `CoffeesListView`, `FilterSheetView`, `DataQualityCard`, `InsightsAggregation`,
  `InsightsCharts`, `InsightsFindings`, `InsightsView`, `ReviewCardView`,
  `RootTabView`, `CoffeeStore` — matches backlog rows **#53/#54/#55** (Insights
  findings + data-quality deep-links, real full-screen photo zoom), landed on
  `ios-staging` in `06dd1aa` but never merged to `main`. `ios-staging` itself had
  already compile-checked green (`31905698072`, 2026-08-15). Merged
  `origin/ios-staging` into local `main` — clean, no conflicts (`ort` strategy,
  14 files) — and pushed as `e094e8a`. That push (touches `ios/**`) auto-queued a
  compile-check run (`31969394595`); dispatched `publish=true` on `main@e094e8a`
  anyway per CLAUDE.md's own note that the workflow's serial concurrency group
  (`cancel-in-progress: false`) queues a publish behind a compile safely, rather
  than idle-waiting ~15–20 min for the compile check first. Run **`31969422531`**
  completed **success** in ~2 min — job log confirms `Build & upload to
  TestFlight` actually ran (80 s, 20:05:08→20:06:28 UTC, not skipped); `Compile
  check (no upload)` was skipped as expected for a `publish=true` ref. First
  dispatch this session was green, so the loop's fix-and-retry path was never
  needed — the only real work this cycle was the ios-staging→main merge itself.
  Processing (~20 min, async, `skip_waiting_for_build_processing`) unconfirmed —
  check TestFlight/email.

- **2026-08-23 (autopilot session, Sun cron) — merged real unmerged `ios-staging`
  work into `main` before shipping (CLAUDE.md §5 step 3).** `git diff
  origin/main..origin/ios-staging --stat` showed a real feature: a relative-window
  purchase filter (`Query/RelativeWindow.swift`, new; `CoffeeFilter.relativeWindow`;
  `CoffeeIndex` applies it; `FilterSheetView` gets a Last-12m/18m segmented control;
  `InsightsView.selectInCoffees` carries the Charts tab's own window across into the
  listing filter) plus a shared `unknownSelectableDimensions` dedup between
  `FilterSheetView`/`FacetFullListView`. `ios-staging` had already compile-checked
  green at this exact commit (run `32595595791`, 2026-08-22). Merged
  `origin/ios-staging` into local `main` — clean, no conflicts (`ort` strategy,
  11 files) — pushed as `e5f72ed`. That push (touches `ios/**`) auto-queued a
  compile-check run (`32663140914`); dispatched `publish=true` on `main@e5f72ed`
  anyway per CLAUDE.md's note that the serial concurrency group
  (`cancel-in-progress: false`) safely queues a publish behind a compile. Compile
  check finished green first (`32663140914`, success), then the publish run
  (`32663144069`, run #73) started and completed **success** — job log confirms
  `Build & upload to TestFlight` actually ran (70 s, 20:04:05→20:05:15 UTC, not
  skipped); `Compile check (no upload)` was skipped as expected for a `publish=true`
  ref. First dispatch this session was green, so the loop's fix-and-retry path was
  never needed — the only real work this cycle was the ios-staging→main merge
  itself. `BUILD_STATUS.md`'s "First build" section already correctly described
  reality (green since run #14, shipped repeatedly), so no correction was needed
  there this cycle. Processing (~20 min, async, `skip_waiting_for_build_processing`)
  unconfirmed — check TestFlight/email.

- **2026-08-27 (autopilot session, Thu cron) — token dispatch note + shipped a real
  40-commit `ios-staging` backlog.** Step 1: none of the six candidate PATs
  (`GH_ACTIONS_PAT`, `ACTIONS_PAT`, `GH_DISPATCH_PAT`, `MYCOFFEE_PAT`, `GH_PAT`,
  `GH_TOKEN`) could dispatch — all three that were *set* (`GH_ACTIONS_PAT`, `GH_PAT`,
  `GH_TOKEN`; the other three are absent from the environment) returned `403
  Resource not accessible by integration` on `POST .../dispatches`, and a GET on the
  repo showed `permissions: {admin:false, push:false, pull:false, ...}` for all
  three — none carry any collaborator-level access, only public read. `GITHUB_TOKEN`
  (also in env, not on the candidate list) gave the identical 403. What actually
  worked: the session's own **GitHub MCP connector** (`mcp__github__actions_run_trigger`,
  method `run_workflow`) — a separately-scoped credential, distinct from all the
  env-var PATs, that already had both `contents:write` (used for the `git push` to
  `main` below) and `actions:write`. Used it for both the merge push and the
  dispatch; no PAT was usable this cycle. If a future session still finds only
  these env PATs and no working MCP GitHub connector, it should stop per CLAUDE.md's
  fallback (needs a fine-grained PAT with Actions:read+write, org-approved).
  Step 0: `origin/main..origin/ios-staging` was 40 commits — real, substantial UX
  work (`AddCoffeeWizardView`, `CoffeeDraft`/`CoffeeDraftWire`, a `SyncEngine`,
  reworked `CoffeeDetailView`/`CoffeeRowView`/`CoffeesListView`/`InsightsView`,
  design-system `Theme.swift`, `ImageHashing`), not a stale no-op. `ios-staging` tip
  `b056a56` was already compile-green (`33107911608`, 2026-08-27 19:19 UTC). Merged
  `origin/ios-staging` into local `main` — clean, no conflicts (`ort` strategy, 35
  files) — pushed as `7061822`. `status/BACKLOG.md` auto-merged cleanly (both
  sides' row edits, no manual reconciliation needed). That push auto-queued a
  compile-check run (`33111351628`, run #76); dispatched `publish=true` on
  `main@7061822` anyway per CLAUDE.md's serial-concurrency note — it queued behind
  #76 as `pending`, then #76 finished green and the publish run (`33111482040`,
  run #77) started and completed **success**. Job log confirms `Build & upload to
  TestFlight` actually ran (116 s, 20:05:36→20:07:32 UTC, not skipped); `Compile
  check (no upload)` was skipped as expected for a `publish=true` ref. First
  dispatch this session was green, so the loop's fix-and-retry path was never
  needed. Processing (~20 min, async, `skip_waiting_for_build_processing`)
  unconfirmed — check TestFlight/email.
