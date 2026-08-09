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

- First `publish=true` TestFlight ship green (run #14). Fixes: MCP-app dispatch,
  team-from-profile (`635a822`), `CFBundleExecutable` (`d601a2c`); retained
  legacy-dir profile mirror (`526d34e`).

- **2026-08-09 (autopilot session, Sun cron) — routine ship, still green, no fixes
  needed.** Checked for an in-flight `ios-testflight` run first (none). Dispatched
  `publish=true` on `main@b466788` via `mcp__github__actions_run_trigger` (the
  MCP app's `actions=write` install remains the only working dispatch path — did
  not re-probe the PAT env vars this session since publish.md already documents
  none of them carry that permission). GH Actions run **`31333259849`** completed
  **success** in ~95 s total job time (`match` 3s, `xcodegen generate` 0s,
  `build_app` 39s, `upload_to_testflight` 29s). Log-verified, not just
  green-badge: `Archive Succeeded` under team `PH2NNQ47UB` with profile
  `match AppStore ro.climbagain.mycoffee`, then `Successfully uploaded package to
  App Store Connect` (app `6795523219`) and `fastlane.tools finished successfully
  🎉`. First dispatch this session was green, so the fix-and-retry loop was never
  needed. This ship carries the 2026-08-08 UI/review batch (`9bb27d6..2b3b0e1`:
  real review feed wiring, full-text collapsible section, blend origins, process-tag
  wrap fix, listing thumbnails) plus the #35/#36 accept-by-default backend work —
  all iOS-visible changes noted in `BACKLOG.md`'s "Right now" section as awaiting
  this lane. Processing (~20 min, async, `skip_waiting_for_build_processing`)
  unconfirmed — check TestFlight/email. Note: this session's harness restricts
  pushes to its own branch (`claude/modest-newton-wiyziu`), not `main` — this
  status update lands there and needs a merge to `main` by an authorized session,
  per the "CCR routine commits to its own branch" gotcha in `CLAUDE.md` §12. No
  code changes were needed (no red to fix), so nothing else is stranded.

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
