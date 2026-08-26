# Lane: Compile check

Branch: `dispatch only` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- **2026-08-26: run #74** (`ios-testflight.yml`, `publish=false`, `ref: ios-staging`,
  sha `100135c` — "iOS shell: session check 2026-08-26, no ready row") went **GREEN**
  on the first try. `ios-staging` had 33 unmerged commits over `main` (last synced
  at run #71/#73, sha `6aac5f0`/merged to `main` at `e5f72ed` on 2026-08-23), so the
  check was warranted — covers #75–#89 range work (Add Coffee wizard, flavour
  notes extraction + display, Coffees/Coffee-page/Insights redesign tokens,
  CoffeeRowView + CoffeesListView redesign). No in-flight run blocked the
  dispatch. Nothing to fix or diagnose this cycle.

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
