# Lane: Publish (autopilot)

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## State — first ship not yet green, blocked on a dispatch token

The signing chain is **proven**. Remaining failures are ordinary build-config
iterations, but no token in the environment can dispatch a workflow, so the loop
cannot run. See "How to run the autopilot" below.

Run history (each dispatch advanced further):
- #5 → failed at `match` (git auth). Fixed by the org-scoped `MATCH_PAT`.
- #6 → `match` SUCCEEDED: cert `DQ2D2T3MR9` created under `PH2NNQ47UB`, pushed to
  `mycoffee-private@match`. Failed at `xcodegen generate` (cwd). Fixed (`Dir.chdir`).
- #8 → reached `build_app`, failed at archive: no profile matching
  `match AppStore ro.climbagain.mycoffee`. Fixed in `2b165c4` (explicit manual
  signing via xcargs + export_options). **Untested — the next dispatch tests it.**

## How to run the autopilot
1. Add a fine-grained PAT to the cloud environment as `GH_ACTIONS_PAT`:
   owner `Climb-Again`, repo `MyCoffee`, **Actions: Read and write**, org-approved.
   (`GH_TOKEN` and `GH_PAT` both 403 on Actions — neither works.)
2. The env var only reaches a **fresh** session, so run the loop via the Publish
   autopilot routine (fire it) or a new session — not a session started earlier.
3. The autopilot dispatches `publish=true`, watches, fixes reds in the Fastfile /
   workflow, re-dispatches, and stops on green (reporting the ~20-min processing
   caveat) or after 6 iterations.

## Claimed

_none_

## Done

_none_
