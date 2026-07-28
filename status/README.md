# Lane status files

One file per lane. **Never edit another lane's file.** This is the whole point:
six agents contending over a single `Claims` section in `BUILD_STATUS.md` is a
merge-conflict generator, whereas one file per lane merges cleanly by construction.

## Protocol

1. **Before coding**, append a claim to your own `status/<lane>.md` under
   `## Claimed`, commit it, and push. If the push rejects, `git pull --rebase` and
   retry — your file can only conflict with your own lane.
2. **When done**, move the line to `## Done` with the commit SHA.
3. **Stale claims** — a claim older than 24 h with no commits on its branch is
   reclaimable by any lane. Move it to `## Abandoned` with a one-line reason.

Claim line format:

```
- [YYYY-MM-DD HH:MM UTC] <issue #> <one-line description> — branch `<branch>`
```

## Lanes

| File | Lane | Branch | Owns |
|---|---|---|---|
| `backend.md` | Backend | `main` | `backend/src/**`, `backend/migrations/**` (except `005_vocab_seed.sql`), `backend/test/**` |
| `data.md` | Data extract + validate | `main` | `ops/**`, `backend/migrations/005_vocab_seed.sql`, `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` |
| `ios-shell.md` | iOS shell | `ios-staging` | `ios/MyCoffee/Sources/{App,Store,API,Models,Query,Utilities}/**` |
| `ios-ux.md` | iOS UX | `ios-staging` | `ios/MyCoffee/Sources/{Features,DesignSystem}/**`, `ios/MyCoffee/Resources/**` |
| `compile.md` | Compile check | dispatch only | nothing — dispatches `publish=false` |
| `publish.md` | Publish | `main` | `certs/`, `profiles/`, `match_version.txt`, `.github/workflows/**` |

Full rules in `CLAUDE.md` §4–§5; the work breakdown is in `PLAN.md`.

## Hard interlocks

- **Publish is the only lane that may dispatch `publish=true`.** Compile only ever
  dispatches `publish=false`. Both share one workflow with
  `concurrency: ios-testflight, cancel-in-progress: false`, so check for an
  in-flight run before dispatching.
- **Never push `backend/**` while an extraction job is `running`** — the push
  redeploys and SIGTERMs the worker. Check `GET /api/admin/jobs` first. The lease
  reaper makes it survivable, not free.
- **The two iOS lanes share `ios-staging`** but own disjoint directories. The seam
  is the `CoffeeStore` / `CoffeeIndex` API surface: shell publishes it, UX consumes
  it. Changing that surface needs a claim in *both* files.
