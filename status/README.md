# Lane status files

One file per lane. **Never edit another lane's file.** This is the whole point:
six agents contending over a single `Claims` section in `BUILD_STATUS.md` is a
merge-conflict generator, whereas one file per lane merges cleanly by construction.

## Where the work list lives

**`status/BACKLOG.md`** — not the GitHub issue list. Routine-fired sessions run
without MCP connector tools and cannot query the GitHub API, so everything a lane
needs to pick its next task lives in the repo. Each backlog row mirrors a GitHub
issue of the same number: the issue holds the full spec, the backlog holds lane,
phase, status and dependencies.

## Step 0 — the cheap gate (added 2026-08-27; do this FIRST, every session)

A 2026-08-01→08-27 audit found **35 of 80 commits were "no ready row" no-ops**,
each of which had first read `BACKLOG.md` (153 KB), the lane file (up to 237 KB),
`PLAN.md` and `CLAUDE.md` — hundreds of KB of context to discover there was
nothing to do. So, before reading anything:

```bash
git pull --rebase -q
grep -nE '^\| *[0-9]+ *\| *<your-lane> *\|' status/BACKLOG.md | grep -E '\| *ready *\|'
```

- **No output → STOP.** Do not read `PLAN.md`, `CLAUDE.md`, or your lane file.
  Do not commit a "session check" note — those 35 commits were pure noise.
  End the turn with one line: `<lane>: nothing ready`.
- **Output → proceed**, and only now read what you need. Prefer
  `tail -80 status/<lane>.md` over reading the whole file; the Done log is long
  and almost never relevant to the row you just picked.

Check `needs` on the matched row are all `done` before claiming.

## Protocol

0. **Pick a task** from `status/BACKLOG.md`: status `ready`, lane matching yours,
   and all `needs` already `done`. Lowest phase first, then lowest number.
1. **Before coding**, append a claim to your own `status/<lane>.md` under
   `## Claimed`, commit it, and push. If the push rejects, `git pull --rebase` and
   retry — your file can only conflict with your own lane.
2. **When done**, move the line to `## Done` with the commit SHA.
3. **Unblock the next lane** — when you finish an item, flip every backlog row
   whose `needs` are now all `done` from `blocked` to `ready`, in the same commit.
4. **Stale claims** — a claim older than 24 h with no commits on its branch is
   reclaimable by any lane. Move it to `## Abandoned` with a one-line reason.

Claim line format:

```
- [YYYY-MM-DD HH:MM UTC] <issue #> <one-line description> — branch `<branch>`
```

## Integrate before you start — the rule that keeps loops from redoing work

**A fired CCR session commits to its own `claude/*` branch, not to your lane's shared
branch (`main` / `ios-staging`).** If that work never lands on the shared branch, the
next session reads the *same* backlog, sees the *same* rows still `ready`, and does the
*same* work again on a fresh branch. That is exactly how #12/#13/#34 got built **three
times** (branches `claude/peaceful-mccarthy-{n4nt4i,o8kxxo,toj6mv}`) while `main` never
moved — "firing runs with no output." Two hard rules follow:

1. **Before claiming anything, check for stranded prior work in your lane.** Run
   `git branch -r --list 'origin/claude/*'` and read your `status/<lane>.md`. If a
   recent branch already did the row you were about to pick, **adopt/rebase it — do not
   redo it.** A row is only truly `ready` if no un-integrated branch already closed it.
2. **End your session by getting the work onto the shared branch, not by leaving it on
   the `claude/*` branch.** If you can push to the shared branch, rebase and push there
   (`git pull --rebase` first). If a routine can only commit to its own `claude/*`
   branch, then **record that branch name in `status/<lane>.md` and flag it for
   integration** — the work is not "done" until it is on `main`/`ios-staging` and the
   backlog row + `status/<lane>.md` say so with the landed SHA. Update the backlog in
   the *same* push that lands the code, so the next session sees an accurate world.

Corollary: **`done` in the backlog means "on the shared branch."** A row whose work
only exists on a `claude/*` branch is still `blocked`/`claimed`, never `done`.

## Lanes

| File | Lane | Branch | Owns |
|---|---|---|---|
| `backend.md` | Backend | `main` | `backend/src/**`, `backend/migrations/**` (except `005_vocab_seed.sql`), `backend/test/**` |
| `data.md` | Data extract + validate | `main` | `ops/**`, `backend/migrations/005_vocab_seed.sql`, `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` |
| `ios-shell.md` | iOS shell | `ios-staging` | `ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities}/**` |
| `ios-ux.md` | iOS UX | `ios-staging` | `ios/MyCoffee/Sources/{Features,DesignSystem}/**`, `ios/MyCoffee/Resources/**` |
| `publish.md` | Publish | `main` | `match_version.txt`, `.github/workflows/**` (match storage is `Climb-Again/mycoffee-private`) |

Full rules in `CLAUDE.md` §4–§5; the work breakdown is in `PLAN.md`.

## Correcting a task means correcting THIS file

Lane sessions have no GitHub API access, so **they never see issue bodies.** If a
diagnosis changes, updating the GitHub issue is not enough — the row and notes in
`BACKLOG.md` are the only thing a lane reads. A stale note here will be executed
faithfully.

This has already happened once: issue #33's diagnosis was corrected on GitHub but
not here, and the backend lane implemented the superseded fix (`e238f10`) exactly as
this file still described it. The code it wrote was fine; it just wasn't the fix.
When a task turns out to need a human, set its status to `human` so no lane claims it.

## Numbering a new row — never reuse a number

`BACKLOG.md` is what every lane **greps** to claim work, so a duplicate row
number is an operational hazard, not untidiness: a lane matching `^| 109 |`
gets two unrelated rows and can claim the wrong one.

This happened on **2026-09-02**: two sessions filed rows the same day, both took
"the next number" from a read that was already stale, and **#108, #109 and #110
each ended up defined twice** — iPad vs a publish incident, Indonesia/Thailand vs
a value-meter redefinition, honey vs the v3 redesign. The later row of each pair
was renumbered to #114/#115/#116; the first-filed one keeps its number, so
existing references stay valid.

**Before writing a row:**

```bash
git pull --rebase                     # a stale read is how this went wrong
grep -oE '^\| *[0-9]{1,3} *\|' status/BACKLOG.md | tr -d '| ' | sort -n | tail -1
```

Use that number **+ 1**. Then, before pushing:

```bash
bash status/check-backlog.sh          # fails on duplicates and dangling `needs`
```

CI runs the same script on every push touching `status/BACKLOG.md`
(`.github/workflows/backlog-check.yml`), so a collision fails the check rather
than sitting there waiting for a lane to trip over it. Renumber the **newer**
row when fixing one, and grep the prose for `#<old>` references first — they
may point at either row.

## `status/BACKLOG.md` has ONE source of truth: `main`

The iOS lanes work on `ios-staging` and used to flip rows only there, while the
Backend and Data lanes read `main`. On 2026-08-27 the two copies disagreed on
**11 of 11 open rows** — `main` said 4 `ready` + 7 `blocked` for work
`ios-staging` had already marked `done`. Each lane was reading a different world.

A lane that flips a row on `ios-staging` **must land the same `BACKLOG.md` change
on `main` in the same session**:

```bash
git checkout main && git pull --rebase
git checkout ios-staging -- status/BACKLOG.md
git commit -m "Backlog: sync row statuses from ios-staging" && git push origin main
git checkout ios-staging
```

Safe by construction: `status/**` matches no workflow path filter, so this
deploys nothing and builds nothing.

> ⚠️ **This wholesale checkout is only safe when `main` has no `BACKLOG.md`
> rows of its own that `ios-staging` doesn't have.** It is a full-file
> overwrite, not a merge. On 2026-08-29 an ios-ux sync ran this recipe while
> `main` had rows **#92 (done) / #102 / #103 / #104** that `ios-staging`'s
> copy predated — the checkout silently deleted #102–#104 and reverted #92
> to `ready`, undoing a backend session's work in the same commit that
> synced #93/#94/#99. **Before running this recipe, diff row numbers on both
> sides first:**
> ```bash
> diff <(grep -oE '^\| [0-9]+' origin/main:status/BACKLOG.md 2>/dev/null || git show origin/main:status/BACKLOG.md | grep -oE '^\| [0-9]+') \
>      <(git show origin/ios-staging:status/BACKLOG.md | grep -oE '^\| [0-9]+')
> ```
> If `main` has rows `ios-staging` lacks (or vice versa), do a row-level
> merge — copy just the rows that changed on `ios-staging` into `main`'s
> copy — instead of the blind `git checkout ios-staging -- status/BACKLOG.md`.

## Hard interlocks

- **Publish is the only lane that may dispatch `publish=true`.** The compile-check
  lane was deleted on 2026-08-27 — `ios-staging` is now compile-checked by a push
  trigger on the workflow itself (a `push` event can only come from someone with
  write access, so this stays safe on a public repo). The workflow still uses
  `concurrency: ios-testflight, cancel-in-progress: false`, so Publish should
  check for an in-flight run before dispatching.
- **Never push `backend/**` while an extraction job is `running`** — the push
  redeploys and SIGTERMs the worker. Check `GET /api/admin/jobs` first. The lease
  reaper makes it survivable, not free.
- **The two iOS lanes share `ios-staging`** but own disjoint directories. The seam
  is the `CoffeeStore` / `CoffeeIndex` API surface: shell publishes it, UX consumes
  it. Changing that surface needs a claim in *both* files.
