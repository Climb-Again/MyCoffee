# Lane: Compile check

Branch: `dispatch only` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

_none_

## Done

- **2026-08-05: session check, no dispatch — `ios-staging` has nothing new to
  check.** `git diff origin/main origin/ios-staging -- . ':!status'` is empty:
  every actual source-code change on `ios-staging` (the `Country.isoCode`
  nullable + lenient-decode fix, commit `f43e4c4`) is byte-identical to what's
  already on `main` at `de55557` — the Publish lane already merged and
  dispatched it, and both the push-triggered compile-only run
  (`30986026682`) and the `publish=true` run (`30986306772`) came back green
  before this session started. The six commits `ios-staging` carries that
  `main` doesn't (`41afb69`, `34a0c38`, `e06308e`, `f43e4c4`, `10530b3`,
  `f4e2e22`) touch only `status/*.md` bookkeeping — no `ios/**` diff at all.
  Per this lane's job step 1 ("if there's nothing new, stop"), skipped the
  dispatch rather than burn a run confirming a build that's already confirmed
  green on `main`. Nothing to fix, nothing to hand back.

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
