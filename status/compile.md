# Lane: Compile check

Branch: `dispatch only` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- **2026-08-22: run #71 (`ios-testflight.yml`, `publish=false`, `ref: ios-staging`,
  sha `6aac5f0`) went GREEN** — `** BUILD SUCCEEDED **`, 0 `error:` lines in the
  job log. Compile step ran ~44s (module cache warm on the runner), confirmed real
  by grepping the log for Swift module compilation + `AppIntentsSSUTraining` +
  `Validate`/`Touch` steps rather than trusting the short duration alone.
  - Warranted: `ios-staging` was 53 commits ahead of `main` since the last
    ios-staging check (run #67, 2026-08-19, sha `6e4d65a`), including real
    feature commits never before compile-checked on this branch — the in-app
    "Add Coffee" wizard (`f8e227b`/`1acc492`, confirmed NOT on `main`) and the
    persisted-photo-rotation UX half (`a19db60`/`f7e0a98`, #57/#74).
  - **Dispatch note:** the session's default REST tokens (`GH_ACTIONS_PAT`,
    `GH_TOKEN`, `GH_PAT`, `GITHUB_TOKEN`) all read Actions fine (200 on
    `GET .../runs`) but every one 403'd (`Resource not accessible by
    integration`) on `POST .../dispatches` — the write endpoint needs a scope
    the plain PATs don't carry. The GitHub MCP tool
    (`mcp__github__actions_run_trigger`, method `run_workflow`) dispatched
    successfully where the raw curl calls couldn't. If MCP tools are ever
    unavailable to this lane, dispatch will need to fall back to something
    with `workflow` scope, not just `repo`/`actions:write` PATs.
  - No in-flight `ios-testflight` run was queued/in_progress at dispatch time
    (checked via `list_workflow_runs`); nothing was queued behind a publish.

- **2026-08-01: run #20 (`ios-testflight.yml`, `publish=false`, `ref: ios-staging`,
  sha `c3f7c272` — closes #22 ios-shell) went RED**, then fixed and reran GREEN.
  `ios-staging` had 13 unmerged commits over `main` (last: #22 remote repo +
  SyncEngine + ImageStore), so the check was warranted.
  - **Cause:** `Sources/API/Wire/FlexibleDecoding.swift:14` —
    `decodeFlexibleDouble` did `string.flatMap(Double.init)` where `string` is
    a plain `String` (Swift 5 flattens `try? decodeIfPresent(...)`'s double
    optional at the `if let`, same as the run #17 `CoffeeDetailView` bug).
    `String` is a `Sequence` of `Character`, so `.flatMap(Double.init)`
    resolved to `Sequence.flatMap` (returning `[Double]`) instead of
    `Optional.flatMap` (returning `Double?`) — same footgun class as the
    run #17 `ProcessTag`/`CoffeeDetailView` fixes, just the reverse direction
    (there the receiver was accidentally optional; here it's accidentally
    non-optional). Fixed directly: `return Double(string)`.
  - Scanned `Sources/` for sibling `.flatMap(...Init)` calls — only one other
    hit, `CoffeeDetailView.swift:51`'s `(coffee.images?.display).flatMap(URL.init(string:))`,
    already correctly parenthesized to force `Optional.flatMap` from the #17
    fix. No other instances.
  - **Rerun (run #21, sha `e34c0b1`) went GREEN** — compile check confirmed
    fixed, no upload (this lane never dispatches `publish=true`).

## Abandoned

_none_
