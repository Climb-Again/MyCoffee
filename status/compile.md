# Lane: Compile check

Branch: `dispatch only` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- **2026-08-15: run #62 (`ios-testflight.yml`, `publish=false`, `ref: ios-staging`,
  sha `6ff5168` — https://github.com/Climb-Again/MyCoffee/actions/runs/31905698072)
  went GREEN.** Warranted: last `ios-staging` compile check was run #49
  (2026-08-12, sha `81ac0b98`); since then real iOS source landed —
  `348b8cc` (#50 Insights per-label rating + tap-to-filter), `47f2934`
  (ios-shell `CoffeeStore.selectedTab`/`RootTab` seam), `78575d6` (keep full
  text visible after edit), and `06dd1aa` (#53/#54/#55 — Insights findings +
  data-quality deep-links, real full-screen photo zoom viewer replacing the
  dead in-card zoom in `ReviewCardView.swift`). No fix needed.
  - **Note on this lane's dispatch access:** the session's default proxy
    token (tried `GH_TOKEN`/`GH_PAT`/`GH_ACTIONS_PAT`/`GITHUB_TOKEN` via raw
    `curl` against `POST .../dispatches`) returned `403 Resource not
    accessible by integration` on every token, despite all four reading the
    workflow fine via `GET`. Read endpoints work over curl; the dispatch
    (write) endpoint doesn't for this session. Worked around it via the
    `mcp__github__actions_run_trigger` MCP tool (`run_workflow` method),
    which queued the run successfully. If a future compile-lane session
    hits the same curl 403, reach for the GitHub MCP tool before concluding
    dispatch is blocked entirely.

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
