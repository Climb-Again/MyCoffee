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

### 2026-07-29 autopilot fire — still blocked, new PAT present but still 403

`GH_ACTIONS_PAT` is now set (it wasn't on the prior run), but the dispatch probe
still failed: `GH_ACTIONS_PAT -> 403`, `ACTIONS_PAT -> unset`, `GH_DISPATCH_PAT ->
unset`, `MYCOFFEE_PAT -> unset`, `GH_PAT -> 403`, `GH_TOKEN -> 403`. All three set
tokens (`GH_ACTIONS_PAT`, `GH_PAT`, `GH_TOKEN`) authenticate as the same GitHub
user (`ai414`) via `GET /user`, but `GET /repos/Climb-Again/MyCoffee` under
`GH_ACTIONS_PAT` returns `permissions: {admin: false, maintain: false, push:
false, triage: false, pull: false}` — i.e. this PAT currently has **no granted
access to the repo at all**, not even read. The dispatch call itself returns
`"Resource not accessible by integration"`.

This means the fine-grained PAT exists but has not actually been granted
`Actions: Read and write` on `Climb-Again/MyCoffee` — or it was requested but is
still sitting on the **organization's pending-approval** screen (fine-grained
PATs against org-owned repos need an org admin to approve them under
`Climb-Again` → Settings → Personal access tokens → Pending requests, separately
from creating the token). No dispatch was attempted; no workflow was started.

**Action needed from Radu:** open `Climb-Again` org settings → *Personal access
tokens* → *Pending requests*, approve the `GH_ACTIONS_PAT` token if it's sitting
there, and confirm its resource-permission grant includes `Actions: Read and
write` and `Contents: Read` on `MyCoffee` specifically (fine-grained PATs scope
per-repo, not org-wide by default). Re-fire the autopilot once approved.

## Claimed

_none_

## Done

_none_
