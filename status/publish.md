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
