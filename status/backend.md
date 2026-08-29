# Lane: Backend

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/backend-history.md`](archive/backend-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Claimed

(none)

## 2026-08-27 UTC: #90 — optimise `runFlavorNotes` latency (~90s/call on long OCR text)

Only `ready` backend row this cycle (phase 6, no `needs`). Started at
`origin/main`'s tip (`9598759`, the prior session's own #80 completion note) —
no fast-forward needed. `git branch -r --list 'origin/claude/*'` — only this
session's own branch (already at `origin/main`'s tip) — nothing stranded to
adopt.

**Root cause** (already diagnosed by the row itself, filed while backfilling
#80): `extractFlavorNotesForCoffee` (`src/lib/worker.js`) built its prompt text
as the raw concatenation `[raw_title, raw_caption, raw_description]` — and
`raw_description` carries the appended "OCR text" block (#67/#69/#80's
`includeCaptioned:true` sweep put one on nearly every coffee), sometimes
~7K chars. `flash-lite`'s default *thinking* over that much input took ~90s;
`thinkingBudget:0` is rejected by the model (confirmed by the row itself), so
disabling thinking outright isn't an option — the only lever left is bounding
the input.

**Fix** (`src/lib/worker.js`), matching the row's own recommended shape
exactly ("caption-head + OCR-block-head … rather than blind truncation"): new
pure `buildFlavorNotesText({title, caption, description})` splits
`raw_description` at the `"OCR text\n"` marker (the same constant
`appendOcrTextToCoffee` writes) into the pre-OCR text and the OCR block, caps
*each* independently to 1500 chars, then joins. A blind truncation of the
plain concatenation risks losing the OCR block entirely once a caption alone
exceeds the cap; splitting first guarantees some of the OCR block always
survives, since that's where a bag's printed notes usually live.
`extractFlavorNotesForCoffee` now builds its text through this helper instead
of the raw join — no other call site, no schema change.

**Accepted tradeoff, stated plainly**: this caps to the *head* of each
segment, not the whole thing — sanity-checked with a synthetic worst case (a
14K-char OCR body with notes appended at the very end): the capped text does
NOT include those tail notes. The row explicitly chose "head" over
truncation-avoidance-at-all-costs, trading a small loss of recall on a
pathological long+notes-at-the-end bag for bounding every call's latency;
flagging here in case a future session finds this causing real misses on
production data — the fix would be to keep the OCR-block cap but bias it to
include a fixed-size window in the block. Common case (notes near the top of
the OCR block, right after "Note de degustare"/"Tasting notes" headings)
still works, and the second `#90` sanity script (below) confirms the
realistic-size caption+notes-near-front case survives intact.

**6 new `worker.test.js` cases, 278/278 `npm test` green**: short text passes
through unchanged (byte-identical to the old join, so no regression on the
common case); missing fields skipped; empty input → `''`; a long caption gets
capped while the OCR block still survives; a long OCR block gets capped to
its own head independent of the caption's cap; prior `raw_description` text
ahead of an appended OCR block is preserved verbatim.

**Before/after size check** (`node -e`, not committed — ad hoc, matching this
file's own convention for a quick sanity number): a synthetic 20-line caption
+ ~7K-char OCR body → **7472 chars before, 2129 after** — roughly a 3.5×
reduction in what's sent to the model.

**Live-verified in production** after Railway deploy run `33045693182`
(`1beb710`, `completed`/`success`): `GET /health` →
`{"ok":true,"db":true,"service":"mycoffee-api"}`; `GET /api/status` →
`vertex:true`, `db:true`. `GET /api/admin/jobs` — no job `running` before
touching `backend/**`, confirmed both before the push and again before the
timing runs below.

Timed `POST /api/admin/backfill-flavor-notes {force:true}` batches (note:
`force:true` bypasses the `flavor_notes IS NULL` filter, so with `ORDER BY id`
unchanged every call re-scans from the *same* lowest ids rather than
resuming forward — these three calls overlap, they aren't three fresh
batches; not a bug this row needs to fix, just why the averages below aren't
directly comparable):

- `limit:10` → `{"scanned":10,"updated":9,"spentUsd":$0.0009}` in **7.2s**
  (~0.7s/coffee)
- `limit:30` → `{"scanned":30,"updated":27,"spentUsd":$0.0027}` in **182s**
  (~6.1s/coffee)
- `limit:60` → cut off by my own `curl -m 175` before the server responded
  (this sandbox's outbound proxy has a documented history of dropping
  long-held POSTs on big batches — see the 2026-08-17 session note in this
  same file — so a client-side timeout here isn't itself evidence of a
  regression; the completed 30-item run above is the real data point)

Both completed runs land nowhere near the pre-fix ~90s/call baseline (#80's
own commit: "a few slow ~90s calls … cut off by the driver's own --max-time
32"). Couldn't pin down and re-target the *exact* coffee that motivated this
row specifically — `backfill-flavor-notes` has no per-id targeting, only
`ORDER BY id LIMIT`, and hunting for the single longest `raw_description`
among 410 coffees via 410 individual `GET`s wasn't worth the API calls for a
row this bounded. The synthetic worst-case script above plus the aggregate
production timing is the evidence on record.

**Backlog updated in the same push**: `#90` → `done`. Nothing depends on it
(`grep`-checked for `90` in every row's `needs` column) — no row to unblock.

## 2026-08-24 UTC: #75 — Add Coffee wizard, backend half

Only `ready` backend row this cycle (phase 6, `needs` 19/21/24 all `done`).
Started at `origin/main`'s tip `1bac829` (the prior session's own check
commit) — no fast-forward needed. `git branch -r --list 'origin/claude/*'` —
130 branches; no session note since the last check mentions a `#75`-shaped
diff landing anywhere, so this was genuinely unbuilt (confirmed too by a
repo-wide grep for `coffees/extract` — empty outside `PLAN.md`/`BACKLOG.md`
prose).

**Design decision, since the row specced behavior, not a wire shape**: rather
than inventing a second photo-intake path, the wizard's "paste full text"
step (PLAN.md §6.8 step 2) reuses `POST /api/photos/manifest`'s existing
`caption`/`description` fields — the client uploads each bag photo via the
same manifest+image endpoints #19 already ships, with the pasted text going
into the primary/front photo's manifest entry. That means `POST
/api/coffees/extract` takes only `{photoIds: string[]}`, not a redundant
`fullText` parameter that could drift from what's actually stored. This also
resolves the "PhotosPicker allows multiple images but `coffees.photo_id` is
one FK" mismatch cleanly: `photoIds[0]` becomes the coffee's photo, every
other id only contributes an extra image to the vision voters (`images:
[...]` already accepts a list in `agents.js`).

**`src/lib/worker.js`** — three new pure/network-only exports (no new DB
writes), extraction-ensemble-owned (#24) territory:
- `lightVoters()` — rules (P3, free) + `extract_b` (flash) + `reconciler`,
  skipping `extract_a` and the critic. PLAN.md §6.8 says "det + flash + pro
  reconciler"; a human confirms every field seconds later on the confirm
  screen, so the extra vision-vs-text cross-check the critic buys the
  unattended batch worker isn't worth its own network round trip here.
- `pickRawExtractedValue(field, candidatesByField)` — pure, picks the
  reconciler's own raw (pre-canonicalize) candidate string as the field's
  pre-filled draft value, falling back to whichever voter answered first if
  the reconciler didn't. Every voter's raw output is a plain string (only
  `desc_*` prose fields are span objects, and those are deliberately excluded
  from this response — see below) — `canonicalize()` is what turns a string
  into a structured id/amount/range, and the review-queue convention (`GET
  /api/review`'s `candidates`) is to hand the human a string to confirm/edit,
  not a resolved id, so this mirrors that.
- `runLightExtraction({rawText, images, vocabShortlist, voters, vocab,
  photoDate})` — runs the given (or `lightVoters()`'s) ensemble sequentially
  exactly like `processPhoto` does for the batch worker, but writes nothing
  to `extractions`/`field_candidates`: a draft the human hasn't confirmed yet
  has no `input_sha` worth caching, and it's never re-run with the same
  input. Adjudicates via the same `adjudicateRecord` (`adjudicate.js`)
  everything else uses, with `locked` empty (a brand-new coffee has no prior
  human decisions) and `criticVerdicts` empty (no critic in this ensemble).
- Also exported `fetchLatestText`/`fetchImageBuffer` (previously private) so
  `routes/coffees.js` can reuse them instead of re-querying `photo_texts`/
  `assets` itself.

**`src/routes/coffees.js`** — two new routes, both `requireIngestToken`
(this triggers LLM calls / writes, same tier as every other write path):
- `POST /api/coffees/extract` `{photoIds}` — loads every named photo (404
  `photo_not_found` on a miss), fetches each one's stored `ocr` asset as an
  image (422 `no_images_uploaded` if none have one yet), builds `rawText`
  from the primary photo's latest `photo_texts` row via the existing
  `buildRawText`, runs `runLightExtraction`, and shapes the response over the
  same `EDIT_FIELD_TO_CLIENT` set #40's edit endpoint accepts (roaster,
  originCountry, farm, profile, altitude, weight, price, roasterCountry
  — never proposed by voters so naturally absent, rating, roastedOn) —
  `{value, confidence, decision, candidates, evidence}` per field, skipping
  any field the adjudicator decided `absent` (nothing extracted). Reused
  `review.js`'s own `cleanCandidates` (now exported) to shape the raw
  candidate list identically to `GET /api/review`'s.
- `POST /api/coffees` `{photoIds, fields: [{field, value}]}` — 404/400 on the
  same bad-input shapes as `/edit`, 422 `photo_missing_image` if the primary
  photo has no image yet. `upsertCoffeeBase(primaryPhoto, photoText)` (already
  idempotent — returns the existing row if a coffee for that photo_id already
  exists, so a retried SAVE after a dropped connection just re-applies), then
  loops `resolveField(primaryPhoto.id, dbField, value, ctx)` per field
  (identical machinery to `/edit` and `POST /api/review/:id` — `locked=true`,
  `decided_by='human'`) and batches them into one `applyResolutionsToCoffee`
  call. **Then marks every given photoId's row `state='processed'`** — not
  just the primary. Without this, a back-of-bag photo uploaded with no
  caption of its own sits `awaiting_text`, and once its 10-day deadline
  passes the daily worker would claim it and `upsertCoffeeBase` would create
  a SECOND, spurious coffee keyed off that photo_id. This isn't something the
  row's own text called out — found it while working through the multi-photo
  case and fixed it as part of the same design, not filed as a follow-up.

**12 new tests, 268/268 `npm test` green**:
- `worker.test.js`: `lightVoters` returns exactly `extract_b`+`reconciler`
  (+rules), never `extract_a`/`critic`; `pickRawExtractedValue` prefers the
  reconciler, falls back to the first voter, returns `null` for an
  unproposed field; `runLightExtraction` with two injected fake voters (pure,
  no network) — asserts `candidatesByField` aggregation, `spentUsd` summing,
  an agreeing pair adjudicating to `accepted`, and a genuine 2-way split
  still resolving with `decision:'split'` (applied provisionally, per the
  accept-by-default policy every other adjudication path already follows).
- `coffees.test.js`: auth-gate smoke tests for both new routes, matching the
  file's own established no-DB pattern (a bad/missing bearer never reaches
  the query layer).
- New `coffees-extract.test.js` (own file, `INGEST_TOKEN` configured before
  `config.js` imports — same split as `rotation.test.js`, since
  `coffees.test.js` asserts the *unconfigured*-token behaviour): the
  `missing_photo_ids` 400 validation runs before any DB query, so it's
  covered without `DATABASE_URL`; a non-empty `photoIds` list passes
  validation and fails only at the (absent) DB layer.

**Live-verified end-to-end against a real local Postgres 16** (fresh DB,
migrations 001→025 applied clean via `node src/migrate.js`; Gemini mocked at
the `src/vertex.js` module boundary via `node --experimental-test-module-mocks`
so $0 spend and no dependence on live network/API keys; ad-hoc script, not
committed, per this file's own established convention for worker.js-adjacent
DB-touching paths):

1. Uploaded a front photo (manifest `description` = a full bag-text blob
   naming a roaster, origin, weight, price, and rating) + a back photo (no
   text) via the real `POST /api/photos/manifest` + `PUT
   /api/photos/:sourceId/image` endpoints, each with genuinely distinct image
   bytes (dedup-by-content-hash is real and unrelated existing behavior —
   first attempt reused identical bytes for both and correctly 500'd on the
   `idx_photos_content_sha256` unique constraint, which is `PUT`'s own
   pre-existing dedup path, nothing to do with this row).
2. `POST /api/coffees/extract {photoIds:[front,back]}` → `200`, both images
   reached the mocked voters (confirmed via a system-prompt-keyed mock that
   answers differently per agent), every field
   (originCountry/roaster/weight/price/rating) came back with a sensible raw
   `value`, `confidence`, `decision:'accepted'`, `candidates`, and `evidence`.
3. `POST /api/coffees {photoIds:[front,back], fields:<echoed from step 2>}` →
   `201`, `roaster` resolved to an existing seeded vocab row (id 13) and
   correctly cascaded `roaster_country_id` (38) as a side effect — the exact
   same `extractRoasterCountryOverride`/`roaster.country_id` derivation
   `buildCoffeeColumnUpdates`'s `roaster_id` case already does for the batch
   worker, confirming this new path shares it rather than reimplementing it.
4. `GET /api/coffees/:id` showed every field applied correctly
   (`priceEur`/`pricePer100gEur` FX-converted, `rawDescription` set to the
   pasted text, `reviewState:'clean'`).
5. Retried the identical `POST /api/coffees` call — `201` with the same
   coffee id, confirming idempotency (no duplicate row, no error).
6. `SELECT state FROM photos` — both front AND back rows `processed`,
   confirming the multi-photo fix above actually took effect, not just
   compiled.
7. `field_resolutions` for the primary photo: every field `locked:true`,
   `decided_by:'human'` — confirmed the monthly re-extraction can never
   silently overwrite this coffee's confirmed values.
8. Error paths: an unknown `photoId` → `404 photo_not_found` (both routes); a
   manifested-but-not-yet-imaged photo → `422 photo_missing_image` (save) /
   `422 no_images_uploaded` (extract); an unknown client field name → `400
   unknown_field`.

**Unblocked `#76`** (ios-shell) in the same push, with the live wire shape
spelled out in `BACKLOG.md` so it doesn't have to guess. `#77` (ios-ux) stays
`blocked` — its `needs` (76, 27) aren't both `done` yet.

## 2026-08-20 UTC (third session): #73 — persisted photo rotation (backend half of #57)

Started at `origin/main` = `9d9b6cf` (nothing to fast-forward).
`git branch -r --list 'origin/claude/*'` showed only this session's own
branch, so no stranded prior work to adopt — and a repo-wide grep confirmed
`rotation_quarter_turns`/`rotationQuarterTurns` existed nowhere outside
backlog prose, matching what `#73`'s own filing note claimed.

`GET /api/admin/jobs` before pushing: newest job 27 is `done`
(`photosDone` 23, `spentUsd` $0.0403), nothing `running` — safe to push
`backend/**` per CLAUDE.md §12. (Jobs 23/24 remain `paused` from the
known free-tier-quota sessions; not this session's to clear.)

**Shipped in `7e47c68`** — three pieces, following the `is_favorite`
precedent, NOT `resolveField`: rotation is a human display correction, not an
extracted field, so it touches no `field_candidates`, no `EDIT_FIELD_TO_CLIENT`,
no review items, no `decided_by`.

1. `backend/migrations/025_add_photo_rotation.sql` —
   `coffees.rotation_quarter_turns SMALLINT NOT NULL DEFAULT 0` plus a
   `0..3` CHECK. The constraint is added as
   `DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT` so the file itself is
   re-appliable, not just skipped by the migration ledger. On `coffees`
   rather than `photos` per the row's reasoning (every app read path is
   already a `coffees`-row projection; `photos` would mean a join plus a
   second `updated_at` for the delta sync to track).
2. `POST /api/coffees/:publicId/rotation` `{quarterTurns}` in
   `src/routes/coffees.js`, `requireIngestToken`, a straight mirror of
   `/favorite`: one `UPDATE … SET rotation_quarter_turns = $1,
   updated_at = now() … RETURNING`, `{id, rotationQuarterTurns}` on success,
   `404 coffee_not_found` on no row, and `400 invalid_quarter_turns` on a
   non-integer or out-of-range value (rejected, not clamped — the client only
   ever sends `(current + 1) % 4`, so anything else is a client bug worth
   surfacing). The `updated_at` bump is what carries the correction to every
   device via the delta sync.
3. `rotationQuarterTurns: row.rotation_quarter_turns` in `toCompactCoffee`, so
   the *listing* thumbnail can be upright too; the detail route spreads
   `toCompactCoffee` and inherits it. Both the snapshot and detail queries
   already `SELECT co.*`, so no SELECT list needed changing. The `/api/coffees`
   paged debug route enumerates its own columns and was deliberately left
   alone — it isn't an app read path, and widening it would only grow the diff.

**Tests: 258/258 green** (`cd backend && npm ci && npm test`). Two new: an
auth-gate case in `test/coffees.test.js` matching the `/favorite` and `/edit`
ones, and a new `test/rotation.test.js` for the range validation — its own
file because it needs `INGEST_TOKEN` present before `src/config.js` is
imported, which would break `coffees.test.js`'s unconfigured-token
assertions (`node --test` gives each file its own process).

**Verified end-to-end against a real local Postgres 16** (fresh DB, full
migration chain 001→025 applied clean, then the 025 file re-run by hand to
prove idempotency):

- column defaults to `0` on an existing coffee
- `POST … /rotation {quarterTurns: 3}` → `200 {"id":"coffee-rot-1","rotationQuarterTurns":3}`, column written
- `updated_at` bumped, and `GET /api/snapshot?since=<pre-rotate ts>` re-ships that coffee (the delta-sync path the whole design hangs on)
- `GET /api/snapshot` compact row → `rotationQuarterTurns: 3`; `GET /api/coffees/:id` → `3`
- `{quarterTurns: 4}` → `400 {"error":"invalid_quarter_turns","value":4}` and the column stays `3`
- unknown public id → `404 coffee_not_found`
- no token → 401; the **read** token → 401 (write is ingest-only)
- a direct `UPDATE … = 7` is rejected by `coffees_rotation_quarter_turns_check`

Display-only: the stored `display`/`thumb`/`ocr` assets are not re-encoded —
that's the heavier alternative `#57` explicitly rejected (useless where the
retained `ocr` source is itself baked sideways).

**Backlog updated in the same push:** `#73` → `done`; `#74` (ios-shell)
`blocked` → `ready` with the live wire contract spelled out; `#57` (ios-ux)
stays `blocked` (its `needs` are 59/73/74, and `#74` isn't `done` yet).

**Post-deploy production verification — PASSED.** Railway deploy run
`32404953056` (run #58, `7e47c68`) → `completed`/`success`. Against the live
service:

- `GET /health` → `{"ok":true,"db":true,"service":"mycoffee-api"}`
- `GET /api/snapshot` → **410 coffees, every one carrying
  `"rotationQuarterTurns":0`** — so migration 025 applied on production and the
  compact row shape is live for `#74` to decode.
- `POST /api/coffees/ykUXaOsxIrLTmWMDp1yoYA/rotation {"quarterTurns":0}` →
  `200 {"id":"ykUXaOsxIrLTmWMDp1yoYA","rotationQuarterTurns":0}`. Deliberately
  wrote `0` (the value already stored) so the live check couldn't leave a real
  photo rotated — it proves the write path end-to-end while being a value no-op.
- `{"quarterTurns":5}` → `400 {"error":"invalid_quarter_turns","value":5}`
- the same POST with the **read** token → `401`

## 2026-08-17 UTC (seventh session): #72 — refresh the stale What's New content

Only `ready` backend row this cycle (`#72`, phase 6, no `needs`). Started at
`origin/main`'s tip `2c189c9` — fast-forwarded to it cleanly, no stranded
`claude/*` branch carried this row (`git branch -r --list 'origin/claude/*'`,
105 branches, none newer than this session's own touching
`backend/src/data/whatsnew.json`).

**Read the actual current state before writing prose** — walked the full
`BACKLOG.md` table rather than trusting the row's own summary of what shipped,
since the row itself turned out to have a wrong premise (see below). Confirmed
via `routes/whatsnew.js`: it serves the *same* static `whatsnew.json` for both
`live` and `plan` — there is no backlog-to-JSON generation anywhere in the
codebase. **The row's parenthetical "the Plan tab is generated from the
backlog via the API and should already be current" is false** — `plan.byLane`
is exactly as hand-curated as `live`, and was just as stale (the `ios` list
still had 5 items already shipped: field-edit API, edit sheet, What's New API
surface, What's New screen itself). Corrected the row's own premise when
closing it out, per `status/README.md`'s "correcting a task means correcting
this file" rule — flagging here too since a future curation session reading
only the row would otherwise skip re-checking `plan`.

**Rebuilt `live`** (11 items, up from 6): kept the four still-accurate entries
(bag-photo extraction, farm auto-vocab, smaller cached photos, per-field
edit — the last one's stale "an edit sheet is next" clause dropped since #42
shipped it), and added: the Gemini free-tier migration (#61, superseded to
Gemini Developer API — $0 extraction, no more spend caps); nonsense-value
rejection folded into the "picks applied by default" line (#39/#49); the
roaster-country line updated to name Hong Kong/Japan/Greece (#60/#63/024) and
fold in the caption-beats-guess override (#48/#51); full-text search actually
working (#56/#67 — the search blobs were never populated before #56, a real
regression the row itself called out as needing to land in the same commit as
the fix, which is exactly what #56's own close-out did); the OCR-transcription
fallback for image-only photos + its daily drain routine (#65/#67); the
Insights redesign (#52 — three sub-tabs, time windows, average rating
everywhere); and the What's New screen itself (#45–#47), closing the loop
since this very refresh is proof the screen reads live backend data.
**Deliberately did NOT claim Insights tap-to-filter is live** — #50(b)/#53/#54
(tapping a chart/finding to deep-link into the filtered list) are still
`ready`, not `done`, so that stayed in `plan` instead, matching the row's own
implicit request not to overclaim.

**Rebuilt `plan.byLane`**: `backend`/`data` now correctly empty — every
`ready`/`blocked` row in the current table tagged either lane is `done` (or
`human`, already resolved). `ios` now lists the 8 real open ios-ux rows
(chart/finding tap-to-filter #50b/#53/#54 merged into one item since they're
the same seam; #55 review-photo zoom; #57 persisted rotate; #58 bottom search;
#66 per-item review save; #68 Unknown-everywhere filter; #70 single-value
altitude edit) instead of the 5 stale already-shipped ones.

**Trimmed `needsApproval`** from 3 to 1: dropped "publish the accumulated iOS
batch" (multiple publishes have happened since, e.g. #52's own close-out notes
"published to TestFlight same session") and "launch the ~$62 backfill"
(superseded — extraction is now $0 on the Gemini free tier and the daily
routine has already ground through most of the backlog per #65/#67). Kept the
standing 50 MB app+data cap rule (CLAUDE.md §12) — that's a durable product
constraint, not a one-off decision.

No code change beyond the JSON — `whatsnew.test.js`'s existing shape assertion
(`live[].{title,detail,area}`, `plan.byLane.{backend,data,ios}[].{title,detail}`,
`needsApproval[].{title,detail}`) covers structural regressions, and the
content itself is prose, not logic, so no new test was warranted.
`cd backend && npm test` — **252/252 green**, unchanged (no test count drift
expected or seen).

**Pre-push safety check**: `GET /api/admin/jobs` — job 24 is `paused`
(`spentUsd $0.0318`, `photosDone 20`, last error a Gemini 429 free-tier daily
quota exhaustion), **no job `running`** — safe to push `backend/**` per
CLAUDE.md §12's hard rule.

## 2026-08-17 UTC (sixth session): #67 finished (found + fixed a real bug in its own code) + #69 shipped

Started at `origin/main`'s tip `011d8e5` (the fifth session's #67 code +
job-24 correction notes, already on `main` per that session's own detailed
write-up below). This session's job: actually finish #67 (run the production
backfill through to completion) and pick up the next `ready` backend row.

**Job 24.** The prior session left it `running` and suspected — but did not
confirm — that it was orphaned after the mistimed `b2a2861` redeploy SIGTERM'd
its in-process worker. Re-polled `GET /api/admin/jobs` at session start:
`photosDone:20`, `spentUsd:$0.0318` — identical to the prior session's last
reading, many hours later (job `startedAt` `05:17:14Z`, this check well past
that). A 20-second re-poll immediately after showed no movement either.
Six-plus hours frozen at the exact same numbers is conclusive, not
ambiguous like the earlier 429-retry-after confusion this row's own history
documents — paused it (`POST /api/admin/jobs/24/pause`, a reversible
ingest-token admin action, not a `backend/**` push) and confirmed via
`GET /api/admin/jobs` that no job was left `running` before touching
`backend/**`.

**Ran the bounded production backfill** (`POST /api/admin/backfill-ocr-text`)
in small batches. `{"limit":50}` reliably hit `curl: (56) Failure when
receiving data from the peer` — a transport-level connection drop, most
likely this sandbox's outbound proxy timing out a long-held POST, not a
backend error (each row commits its own UPDATE inside the loop, so a
client-side disconnect doesn't roll back rows already processed). Backing off
to `{"limit":15}` (and smaller) was reliable. Ran roughly a dozen batches;
`scanned`/`updated` matched at 5, 10, 15×8, 6 — real progress each time.

**Then it stopped decreasing**: six consecutive calls (`{"limit":15}` then
`{"limit":1}`) all returned `{"scanned":1,"updated":1}` for the *same*
apparent row, with no change in behavior between calls. That shape — an
idempotent, exclusion-based SELECT that keeps re-selecting the same one row
after it was supposedly "resolved" — is a straight sign the write never
happened. Read `appendOcrTextToCoffee` (`src/lib/worker.js`): it takes
`ocrText`, trims it, and `return`s (a no-op) if the trimmed string is empty —
by design, so a blank transcription never stamps an empty `"OCR text\n"`
heading. `agents.js`'s own `runOcrTranscribe` prompt explicitly tells Gemini
*"If no text is legible, output nothing"* — so a genuinely illegible bag
photo legitimately produces `text: ''`. But `backfillOcrText`'s loop called
`appendOcrTextToCoffee` and then unconditionally did `updated += 1`,
regardless of whether anything was actually written. Net effect: a
permanently-illegible photo is claimed forever, reports fake success forever,
and quietly re-burns a (tiny) flash-lite call on every future run — exactly
the kind of "looks like progress, isn't" bug this repo's CLAUDE.md gotchas
section already warns about in other contexts.

**Fix** (`src/lib/worker.js`): `appendOcrTextToCoffee` now returns `true`/
`false` for whether it actually wrote (distinguishing "wrote the block" from
"already had it" / "nothing legible to write" — both are `false`, both are
correctly not-a-fresh-success). `backfillOcrText` only increments `updated`
when the write happened; otherwise it pushes
`{coffeeId, error: 'OCR returned no legible text'}` into `errors` — the same
"broken row stays retryable, doesn't abort the sweep" shape the missing-asset
error case already documents, just for a different root cause. `processPhoto`
(the live extraction path, which also calls `appendOcrTextToCoffee`) ignores
the return value, so this is purely additive there — no behavior change to
the main extraction pipeline.

**Live-verified against a real local Postgres 16** (fresh `mycoffee_test69`
DB, migrations 001→024 applied clean, Gemini mocked at the `src/vertex.js`
module boundary via `node --experimental-test-module-mocks node:test`
`mock.module`, $0 spend, ad-hoc scripts not committed — DB-touching functions
in this file carry no unit coverage per its own established convention):
1. Seeded one image-only, `processed` coffee with no `OCR text` block, mocked
   `generateContent` to return empty text. `backfillOcrText({limit:10})` →
   `{scanned:1, updated:0, errors:[{..., error: 'OCR returned no legible
   text'}]}` — `raw_description` confirmed still `NULL` (untouched, not
   stamped with an empty heading). A second identical run returned the exact
   same result — no drift, no silent "eventually gives up" behavior, but also
   no false-positive `updated`.
2. Seeded a second coffee, mocked a real transcription (`'REAL BAG TEXT'`).
   `backfillOcrText({limit:5})` picked up **both** the still-pending row from
   (1) (now succeeding, since the mock returns real text) and the new row —
   `{scanned:2, updated:2, errors:[]}` — both `raw_description`s confirmed to
   contain the `OCR text` heading. A follow-up run returned `{scanned:0}` —
   both correctly excluded going forward.
3. Separately verified the population-selection mechanism itself still works
   post-fix: seeded overdue/normal/already-appended/not-processed rows via
   `claimBatch`-adjacent fixtures (see #69's own verification below, same
   session) — no regression to the SELECT's existing exclusion logic.

`cd backend && npm test` — **252/252 green** (up from 250 at the prior
session's own count; +2 from `shouldUseImage`'s tests below, landed in the
same commit).

**Drained the production backlog**: pushed `3c78982`, watched
`railway-deploy.yml` run `32035181677` to completion via the GitHub Actions
API — **`completed success`**. Post-deploy `GET /health`/`GET /api/status`
both green. Re-ran `POST /api/admin/backfill-ocr-text {"limit":10}` against
production twice: both calls returned the identical
`{"scanned":1,"updated":0,"errors":[{"coffeeId":"7","error":"OCR returned no
legible text"}]}` — coffee 7 (the same stuck row from before the fix) now
correctly reports as an honest error instead of a false `updated:1`, and the
result is stable across repeat calls (no more looping). Everything else in
the original ~95-photo population that could be resolved, was — dozens of
coffees across roughly a dozen small batches this session, on top of
whatever the prior session's own `{"limit":5}`/`{"limit":10}` calls had
already done. Coffee 7's bag photo is genuinely illegible to Gemini; nothing
further to do for it programmatically.

Flipped `#67` → `done` in `BACKLOG.md`.

**Picked `#69`** next (lowest-numbered remaining `ready` backend row, phase
6, no `needs` — filed by the data lane while closing out #29 the same day).
The daily text-only OCR job could never reach an overdue `awaiting_text`
photo at all: `claimBatch`'s `stateClause` only included the `awaiting_text`
branch when the job's own `includeImages` was `true` (that gate was #64's own
fix, to stop a *text-only* job from claiming a photo it could only 400 on).
That meant the *ongoing* deadline sweep (PLAN.md §3 step 3) had no home once
the one-time backlog-drain routine (`trig_017RR9aMaL8fpvqPZNAv8mn4`,
`includeImages:true`) self-deletes per #65's own design.

**Fix** (`src/lib/worker.js`): `claimBatch`'s `stateClause` now always
includes both `text_received` and overdue `awaiting_text` — the
`includeImages` parameter was dropped from `claimBatch`'s signature entirely
(it no longer affects the SQL). A photo's *own* state is authoritative for
whether it needs its image, not the job's. New pure exported helper
`shouldUseImage(photo, includeImages)` — `true` if the job asked for images,
or unconditionally `true` for an `awaiting_text` photo (it has no text and
never will) — used in `runWorker`'s per-photo loop:
`processPhoto(photo, ..., { includeImages: shouldUseImage(photo,
includeImages) })`, replacing the old job-wide `includeImages` pass-through.
`isDueForExtraction` (the pure predicate `claimBatch`'s SQL is documented to
mirror) already had this exact shape (`text_received` due immediately,
`awaiting_text` due once its deadline passes, independent of any
`includeImages` concept) — this fix just brings `claimBatch`'s real SQL and
`runWorker`'s per-photo image decision into line with what that predicate
already specified.

**2 new `worker.test.js` cases**: `shouldUseImage` respects the job flag for
`text_received`, always returns `true` for `awaiting_text` regardless of the
job flag.

**Live-verified against a real local Postgres 16** (same `mycoffee_test69`
DB, truncated between runs): seeded three photos — an overdue `awaiting_text`
(`text_wait_until` an hour in the past), a not-yet-due `awaiting_text`
(`text_wait_until` an hour in the future), and a normal `text_received`.
Called `claimBatch(10, {workerId:'test'})` with no `includeImages` passed at
all (the daily routine's own default, text-only) — claimed exactly the
overdue + normal pair, correctly excluded the not-yet-due one. Confirmed
`shouldUseImage(overdueClaimed, false)` → `true` and
`shouldUseImage(normalClaimed, false)` → `false` on the actual claimed rows,
not synthetic fixtures — the mechanism the row asked for (one standing
text-only job draining both cases) works end-to-end against a real claim.

`cd backend && npm test` — **252/252 green** (same run as #67's fix above,
one commit).

Flipped `#69` → `done` in `BACKLOG.md`. No row's `needs` references `67` or
`69`, so nothing else unblocks.

**Did not pick up a third row** (`#72`, refresh the stale `whatsnew.json`
Live content) this session — two related `worker.js` fixes is a reasonable
batch, and #72 deserves a session that can actually read through everything
that's shipped since it was last curated rather than rushing a curation task
at the tail of an already-long session. Left `#72` `ready` for the next
session.

## 2026-08-17 UTC (later session, fifth check): #67 — code complete + live-verified, but HELD OFF `main` (job 24 `running`, pause denied)

**⚠️ Next session: the work is done and verified. Do not rebuild it.** It is
committed on `origin/claude/confident-cerf-86fp01`. All that remains is landing
it on `main` once no extraction job is `running` (see "What's left" below).

Picked `#67` per lowest-phase-then-lowest-number among the three `ready`
backend rows (`#67`, `#69`, `#72` — all phase 6, no `needs`). This session
started already at `origin/main`'s tip (`c1e63f8`), no fast-forward needed.
`git fetch origin --prune` — 103 `origin/claude/*` branches; nothing stranded
carrying this row (no session note since the last check mentions pushing
backend code anywhere but `main`), so this was genuinely unbuilt.

**What the row asked for**: the ~95 image-only photos OCR'd by jobs 22/23 on
2026-08-16 were processed *before* `189eab6` added the OCR-text-append, so
those coffees carry no "OCR text" block — and since they have no caption
(`raw_caption IS NULL`, image-only), that block would be their *only* readable
full text. They're `state='processed'`, so the daily OCR routine will never
re-touch them. Needed: a targeted re-OCR path that re-runs `runOcrTranscribe`
on the stored `ocr` asset and appends via the existing
`appendOcrTextToCoffee`, *without* a full re-extraction.

**`src/lib/worker.js`** — `backfillOcrText({ limit, spendCapUsd })` (new,
exported). Selects exactly the affected population with one join:

```sql
FROM coffees c JOIN photos p ON p.id = c.photo_id
               JOIN assets a ON a.photo_id = p.id AND a.variant = 'ocr'
WHERE c.deleted_at IS NULL AND c.raw_caption IS NULL AND p.state = 'processed'
  AND (c.raw_description IS NULL OR c.raw_description NOT LIKE '%' || $1 || '%')
```

i.e. image-only (`raw_caption IS NULL`), already processed, has a retained
`ocr` asset to read, and does not already carry the `OCR text` heading. Per
row it calls only `runOcrTranscribe` (the single flash-lite call) against the
stored `ocr` asset — the same source `POST /api/admin/rederive-photos` reads,
since the raw upload isn't retained past the original PUT — then reuses
`appendOcrTextToCoffee`'s own idempotent write. Deliberately NOT a
re-extraction: no voters run, no `field_candidates`, no re-adjudication, so it
cannot disturb any already-extracted structured field (the row's own
"structured fields for these are already extracted; this only adds the
readable transcription"). A per-row `try/catch` collects into `errors` so one
bad row can't abort the sweep, and `spendCapUsd` breaks the loop so a run can
be bounded against the flash-lite daily quota — the row's own "may need to run
over a few days". Because the SELECT excludes anything already carrying the
heading, a later run *resumes* rather than restarting, and can never stack a
second transcription onto the same coffee.

**`src/routes/admin.js`** — `POST /api/admin/backfill-ocr-text`
(ingest-token-gated, same tier as every other admin mutation), body
`{limit?, spendCapUsd?}`, returns `{scanned, updated, spentUsd, errors}`.

**Tests**: 1 new `admin.test.js` auth smoke test in the established
`node:test` + `app.inject()` no-DB pattern — `cd backend && npm ci && npm test`
**250/250 green** (up from 249). `backfillOcrText` is DB- and
network-touching, so per this repo's convention (same as `claimBatch`,
`refreshSearchBlobs`, `rebuildAllSearchBlobs`) it carries no unit coverage;
the mechanism was instead verified against a real Postgres, three separate
ways, rather than asserted from the diff:

**Live-verified against a real local Postgres 16** (fresh DBs, full migration
chain 001→024 applied clean each time; `runOcrTranscribe`'s network call
mocked at the `src/vertex.js` boundary via `node --experimental-test-module-mocks`,
so zero live Gemini spend and no dependence on the exhausted daily quota):

1. **Population selection** — seeded four coffees: (a) image-only, processed,
   no OCR block; (b) image-only, processed, *already* carrying an `OCR text`
   block; (c) processed but *with* a caption (not image-only); (d) image-only
   but still `awaiting_text` (not processed). `backfillOcrText()` returned
   `{scanned:1, updated:1}` — picked up **only (a)**, correctly excluding all
   three others. (a)'s `raw_description` came back as
   `"OCR text\nMOCKED TRANSCRIPTION FROM BAG"`; (b)/(c)/(d) were byte-identical
   to before. A second run returned `{scanned:0, updated:0}` — idempotent.
2. **Spend cap + resume** — seeded 5 image-only coffees and mocked a usage
   payload with the *real* Gemini field names (`promptTokenCount`/
   `candidatesTokenCount`, so `estimateCostUsd` yields a genuinely nonzero
   per-call cost — worth noting, my first mock used made-up field names and
   silently produced `$0`, which would have made this a vacuous test).
   `spendCapUsd: 0.05` stopped the run after **1 of 5** at `$0.12`; the 4
   untouched rows were still pending, and a subsequent uncapped run processed
   **exactly those 4**. Asserted every row ends with exactly **one**
   `OCR text` occurrence — no stacking — and that a third run finds nothing.
3. **Error isolation** — seeded a coffee whose `assets` row points at a file
   missing from the volume, deliberately ordered *first* (lowest id) so an
   aborting loop would visibly skip the two good rows after it. Result:
   `{scanned:3, updated:2, errors:[{coffeeId:1, error:"ENOENT..."}]}` — the
   two good rows were still backfilled, the broken one was left wholly
   untouched (not half-written) and stays selectable so a later run retries it
   once the volume is fixed.

**Production live-check**: `GET /health` →
`{"ok":true,"db":true,"service":"mycoffee-api"}`; `GET /api/status` →
`vertex:true`, `db:true`.

**⛔ Why this did NOT land on `main` — and what's left.** `GET
/api/admin/jobs` shows **job 24 `running`** (started 05:17 UTC, still
`running` at 06:58). It is definitively stuck, not slow: polled it **five
times over ~4 minutes** and it never advanced — `photosDone` **0**,
`spentUsd` **0**, `lastError` pinned to the same `photo 269` every poll, a
Gemini **429** `RESOURCE_EXHAUSTED` (`generate_content_free_tier_requests`,
`limit: 500`, `gemini-3.5-flash-lite`). The free-tier *daily* request quota is
spent, so it cannot progress today no matter how long it runs — the same shape
as jobs 14/15 in the #61/#62 close-out above, and jobs 20/21.

Per CLAUDE.md §12's hard rule (**never push `backend/**` while a job is
`running`** — the push redeploys and SIGTERMs the worker), the correct
sequence was to pause job 24 first, exactly as the #61/#62 session did for
jobs 14/15. **`POST /api/admin/jobs/24/pause` was denied by this session's own
permission classifier**, so — following the same judgment the #51 close-out
recorded for its denied `POST /api/admin/adjudicate` — I stopped rather than
working around it. Notably I did **not** substitute the *larger* action the
pause was meant to make safe (pushing `backend/**`, which would auto-deploy
and SIGTERM the worker); taking the bigger blast-radius action right after
being denied the smaller, reversible one would defeat the point of the denial.

So the code sits on **`origin/claude/confident-cerf-86fp01`**, and this row
stays **`claimed`, not `done`** — per `status/README.md`, `done` means "on the
shared branch". Only `status/**` was pushed to `main` (docs don't match
`railway-deploy.yml`'s `backend/**` path filter, so they trigger no deploy and
are safe regardless of job state).

**🔴 CORRECTION to my own diagnosis above — job 24 was NOT stuck, and holding
the push was right for a better reason than I thought.** On a final re-check at
07:02 UTC (~4 min after the last poll above) job 24 read **`photosDone` 12,
`spentUsd` $0.0175** — up from 0 and $0. It had been making real progress all
along; the 429 was Gemini's **per-minute** rate limit throttling it hard
(hence the `"Please retry in 59.367s"` in the error body), not the *daily*
request cap being spent as I concluded from five flat polls. A 4-minute
observation window simply wasn't long enough to see a job whose throughput is
throttled to roughly one photo per 20 seconds *behind* a minute-long backoff,
and `photosDone` only increments on a *completed* photo, so a partially-retried
batch reads as 0 for a long time.

Two things follow, and the second matters more than the first:
- **Pushing `backend/**` would have SIGTERM'd a worker doing real, paid OCR
  work** — exactly the harm CLAUDE.md §12's rule exists to prevent. The hold
  was correct.
- **Pausing job 24 would also have been wrong** — I had judged it a
  zero-cost, reversible stop of a pointless loop, and that judgment was simply
  mistaken. The permission denial prevented a real (if modest) harm, not just
  a procedural one. Worth remembering next time this shape appears: **`photosDone
  0` + `spentUsd 0` + a repeated `lastError` photo id is NOT sufficient
  evidence of a wedged job when the error is a 429 with a retry-after.**
  Distinguish "throttled" from "wedged" by watching over a window several times
  the retry-after (tens of minutes, not 4), or by comparing `spentUsd` — a
  throttled job's creeps up, a wedged one's stays exactly 0. Jobs 14/15 in the
  #61/#62 close-out were genuinely wedged (a non-retryable 403 spend-cap
  breach, `spentUsd` pinned at 0 across a real 32-minute gap); a 429
  retry-after is a different animal and should not be treated the same way.

## 🔴🔴 2026-08-17 UTC — MY OWN PROCESS ERROR: the #67 code DID land on `main`, and it DID redeploy while job 24 was running

**Everything above about "held off `main`" is wrong as of `b2a2861`. Read this
section, not that one, for where the code actually is.** Leaving the earlier
text in place deliberately — it's the reasoning that led to the mistake, and
overwriting it would hide the lesson.

**What I did wrong.** I correctly decided to keep `backend/**` off `main` while
job 24 ran, and correctly structured the first two pushes to carry only
`status/**` (`d6a74e1`, `ba3ee18`). Then I committed the code as `e99cdc2` on
the session branch, and afterwards committed the job-24 *correction docs* as
`b2a2861` **on top of it** and pushed `HEAD:main`. **Git pushes commits, not
files** — `b2a2861`'s ancestry includes `e99cdc2`, so the backend code went to
`main` with it. The entire point of the stash-and-split dance earlier was to
avoid exactly this, and I undid it one commit later by not re-checking ancestry
before a push I'd mentally filed as "docs only".

**The rule that would have caught it**: before any push to `main`, diff what
the push actually carries against the remote — `git diff --name-only
origin/main..HEAD` — and gate on *that*, never on "what I just edited". I'd
even run that check for `ba3ee18` and then skipped it for `b2a2861`.

**Consequence**: `railway-deploy.yml` run **`32004154142`** triggered at
07:03:37Z on `b2a2861` and redeployed while job 24 was `running` — the precise
thing CLAUDE.md §12 forbids. Job 24 was at `photosDone` 18 / `spentUsd`
$0.0283 and progressing when the push landed.

**Why I did NOT revert.** A revert commit touching `backend/**` would trigger a
**second** deploy and therefore a **second** SIGTERM — strictly worse than the
one already in flight — and force-push/history-rewrite is forbidden outright
(CLAUDE.md §3). The code itself is the verified-good #67 implementation that
was going to land anyway, and `npm test` gates the deploy job, so the deploy
content is not in question; only its *timing* was wrong. The cheapest correct
move is to let the one deploy finish and then verify recovery, which is what I
did.

**Why the damage is bounded** (design, not luck): the worker is explicitly
built for this — `extractions.input_sha` makes every voter call idempotent, so
the $0.0283 already spent is stored and a resumed run gets **cache hits rather
than re-spends**; claim-with-lease means the photos job 24 held are released by
the lease reaper (10-min-old leases are reaped on the next claim); and #64's
`extraction_failures` counter prevents a re-claim loop. So the loss is the
in-flight photo(s) at SIGTERM, not the paid work.

**Post-deploy verification (all done this session):**
- `railway-deploy.yml` run **`32004154142`** → **`completed success`** (both
  `test` and `deploy` jobs; the 250/250 suite gated it).
- Observed the expected redeploy window directly: `GET /health` returned
  Railway's `502 "Application failed to respond"` at 07:05:31Z (old container
  SIGTERM'd — this *is* the documented cost of the mistimed push), then
  recovered by 07:06:33Z.
- Post-deploy: `GET /health` → `{"ok":true,"db":true,"service":"mycoffee-api"}`;
  `GET /api/status` → `vertex:true`, `db:true`.
- **New route is live and correctly gated**: unauthenticated `POST
  /api/admin/backfill-ocr-text` → **401** (route exists, ingest-token-gated —
  not a 404).
- **The paid extraction work survived, as designed**: job 24 read `photosDone`
  **18** / `spentUsd` **$0.0283** just before the push and `photosDone` **20** /
  `spentUsd` **$0.0318** just after the new container came up — it *advanced
  across* the redeploy rather than losing ground. `extractions.input_sha`
  idempotency + claim-with-lease did exactly what the module header promises.

**⚠️ Residual state for the next session / Radu — job 24's row is very likely
ORPHANED.** It still reads `status: running`, but `photosDone`/`spentUsd` have
been frozen at **20 / $0.0318** across three polls over ~2.5 minutes since the
new container booted. `runWorker` is fire-and-forget *in-process* and nothing
re-invokes it on boot, so the SIGTERM almost certainly killed the worker while
leaving the `extraction_jobs` row at `running`. Consequences: (a) it will keep
tripping the "no job `running`" push gate for every future `backend/**` push
until it's cleared, and (b) the remainder of #65's image-only OCR backlog isn't
being drained right now. **I deliberately did not touch it** — `POST
/api/admin/jobs/24/pause` was already denied for this session, and taking the
mirror-image action (`/resume`) unilaterally after that denial would be the same
overreach in the opposite direction. Clearing it is a one-liner for whoever
holds the call: `POST /api/admin/jobs/24/pause` (then `/resume`, or simply let
the next daily OCR routine fire a fresh job — the lease reaper has already
released job 24's photos, so a new job picks them up cleanly). Caveat per the
correction above: **2.5 minutes is not a long window**, so re-check
`spentUsd` before concluding it's dead — if it has moved, a worker is alive and
should be left alone.

**Not run this session: the actual production backfill.** `POST
/api/admin/backfill-ocr-text` is live but I did not fire it. Unlike every other
backfill this lane has shipped, **this one costs real flash-lite calls** (~1 per
coffee × ~95 coffees), and the Gemini free-tier quota is currently under enough
pressure to 429 job 24 continuously — so a run now would mostly land in
`errors` while consuming quota that #65's backlog drain needs. It's the one
remaining step, and it's explicitly designed to be run bounded across several
days (`{"limit":50}` / `spendCapUsd`).

**To finish #67** (a few minutes, no rebuild — the code is written and
verified; note per the section above the CODE IS ALREADY ON `main` and
deployed, so steps 1–2 are done, and only the production backfill run and the
bookkeeping remain):
1. ~~Confirm no job is `running`~~ — **moot, the code is already deployed.** But
   see the orphaned-job-24 note above: clear that row so it stops tripping the
   push gate for the *next* `backend/**` change.
2. ~~Land it~~ — **done**, `e99cdc2` on `main`, deploy run `32004154142` green.
3. Run the backfill against production, bounded, since it's quota-limited:
   `curl -X POST $BASE/api/admin/backfill-ocr-text -H "Authorization: Bearer
   $INGEST_TOKEN" -H 'Content-Type: application/json' -d '{"limit":50}'`.
   Expect `updated` > 0 and `errors` empty; re-run on later days until
   `scanned` reaches 0. **Unlike every other backfill this lane has shipped
   this one costs real Gemini calls** (one flash-lite OCR per coffee, ~95
   coffees), so it is quota-bound, not $0 — bound each run with `limit` and/or
   `spendCapUsd` rather than firing it unbounded.
4. Flip `#67` → `done` in `BACKLOG.md` and move this claim to `## Done` with
   the landed SHA. No row's `needs` references `67`, so nothing else unblocks.

## 2026-08-16 UTC (later session): #64 — close out (code already live from a prior session)

Only `ready` backend row this cycle. `git branch -r --list 'origin/claude/*'`
showed nothing of this row stranded on a scratch branch — but `origin/main`'s
own history had `52eab3f` ("backend #64: stop the worker looping forever on an
always-failing photo") already on it, authored by the same stranded session
that did #61 (`session_01JLFd9wZxpbWRZ959RrcSM3`, co-authored "Claude Opus
4.8"): it had written, tested, and pushed the fix straight to `main`, but
never flipped the `BACKLOG.md` row or logged an entry here — identical to the
exact pattern the #61 close-out (just above) already documented for the same
session. Confirmed via `mcp__github__actions_list`/`actions_get`: the
`railway-deploy.yml` run for `52eab3f` (run `31943189056`) completed
`success` at `2026-08-16T11:04:23Z`.

**What's actually live** (`backend/src/lib/worker.js`,
`backend/migrations/022_add_extraction_failures.sql`): `photos` gained
`extraction_failures INT NOT NULL DEFAULT 0`. `claimBatch(limit, {
includeImages, maxFailures })` now excludes any photo with
`extraction_failures >= maxFailures` (config `EXTRACTION_MAX_FAILURES`,
default 3), and — in text-only mode (`includeImages:false`, the daily
routine's own mode) — no longer claims `awaiting_text` photos at all (no text
ever arrived, so parsing them is a guaranteed Gemini 400 every time); image
mode still claims them since an OCR run can read the bag from the photo
pixels. On a per-photo failure, `runWorker` now increments
`extraction_failures` in the same write that releases the lease; on success
it resets the counter to 0. Either half of the fix eventually makes
`claimBatch` return empty for a batch that's all permanently-failing photos,
so `runWorker` reaches `no_work` and releases the advisory lock instead of
spinning forever holding it (today's root cause: an image-only `awaiting_text`
photo past its `text_wait_until` got re-claimed every round in text-only mode,
400'd every time, never counted toward `photosDone`, and `claimBatch` never
went empty).

**Verification this session**: `cd backend && npm ci && npm test` —
**249/249 green** (matching the fix commit's own count exactly, no drift).
`claimBatch` is DB-touching and carries no unit coverage (same
node:test-no-DB convention the rest of `worker.js`'s DB-touching helpers
follow), so rather than trust the commit message's test count alone, ran a
live-Postgres reproduction of the actual mechanism: started the sandbox's
local Postgres 16, fresh `mycoffee_test64` DB, `node src/migrate.js` — the
full chain (001→023) applied clean. Seeded three photos directly: (a)
`awaiting_text`, `text_wait_until` an hour in the past (the exact #64
trigger — image-only, no text, ready to be mis-claimed); (b) `text_received`
with `extraction_failures = 3` (simulating a photo that's already exhausted
its retries); (c) `text_received` with `extraction_failures = 0` (the normal
claimable control). Called `claimBatch(10, { includeImages: false })` (the
daily routine's own mode) — claimed **only (c)**; both (a) and (b) were
correctly excluded. Called `claimBatch(10, { includeImages: true })` — claimed
**(a) and (c)**, still excluding (b) — confirms image mode can still reach an
`awaiting_text` photo for OCR while the failure-count exclusion applies
regardless of mode. Both halves of the row's own fix (a) and (b) options are
confirmed live against a real Postgres, not just asserted by the diff.

**Production live-check**: `GET /health` →
`{"ok":true,"db":true,"service":"mycoffee-api"}`; `GET /api/status` →
`vertex:true`, `db:true`. `GET /api/admin/jobs` → 24 jobs; the two
prior-session incidents this row itself was filed from (jobs 20/21, both
`text_received`-mode 400 loops) now pause within ~4–5 minutes instead of
spinning for 30+ minutes at `photosDone:0` the way jobs 14/15 did pre-fix
(documented in the #61/#62 close-out above) — consistent with, though not
conclusive proof of, the fix (something/someone paused them manually rather
than the worker reaching `no_work` on its own within that window; the direct
Postgres reproduction above is the load-bearing evidence, this is
corroborating). Job 23's `paused` state (`Gemini 429`, `RESOURCE_EXHAUSTED`,
free-tier quota) is an unrelated rate-limit issue, not this bug — noting so
it isn't mistaken for a regression.

**Could not re-enable the daily extraction routine
(`trig_01JWhQADZK8RqfP8r9ugXen1`)** that the row said was disabled as
mitigation — it's an external scheduled-prompt trigger, not a `backend/**`
code path, and this session's own `CronList` returns nothing (it only manages
this session's in-memory jobs, unrelated to that trigger). Flagged in
`BACKLOG.md`'s `#64` row for whoever manages it (Radu) to flip back on now
that the fix is verified both by direct Postgres reproduction and by
production behavior.

No `backend/**` code change this session (the fix was already on `main`) — so
nothing new to push there or gate on the "no job running" rule; only
`status/BACKLOG.md` and this file changed. Flipped `#64` → `done` in
`BACKLOG.md`; added an informational note to `#65`'s own row (data-owned,
stays `human` — not this lane's call to change) that its `#64` blocker is
cleared. No row's `needs` references `64`, so nothing else formally unblocks.

## 2026-08-16 UTC: #61 — close out (code already live from a prior session); #62 filed (human) — GCP project spend cap blocks all Vertex calls

`git branch -r --list 'origin/claude/*'` showed nothing of this row stranded;
`origin/main` was already at `5ac265a` when this session's fetch ran (a prior
session — `session_01JLFd9wZxpbWRZ959RrcSM3`, co-authored "Claude Opus 4.8" —
had written and pushed the #61 code straight to `main` but never flipped the
`BACKLOG.md` row or logged a claim/close-out entry here, so the row still read
`ready` even though the fix was live). No re-coding needed; this session's job
was to verify and close the loop properly.

**What's actually live** (`backend/src/config.js`, `backend/src/lib/agents.js`,
`backend/src/vertex.js`, per `5ac265a`'s own commit message): `runExtractA` and
`runReconciler` moved off `gemini-2.5-pro` to `gemini-2.5-flash` with
`thinkingBudget:0` — matching `extract_b`/`critic`, which were already flash —
so no voter can land on pro any more; `config.vertex.model`'s default is now
`gemini-2.5-flash` too. Every `generateContent` call now also carries a
`labels` object (`VERTEX_LABEL_APP` → `app=mycoffee`, plus `agent=<voter
name>` per call site), so Vertex's billing export can group/filter spend by
label going forward.

**Verification this session**: `cd backend && npm ci && npm test` —
**253/253 green** (up from 252 at #60's close — the 1 new case is `5ac265a`'s
own `vertex.test.js` label attach/omit coverage). `GET /health` →
`{"ok":true,"db":true,"service":"mycoffee-api"}`; `GET /api/status` →
`vertex:true`, `db:true` — the deploy is live and the auth/db/vertex wiring
still works post-migration.

**Could not do the row's own "validate before committing the corpus" ask**
(diff a live 5-photo flash-model batch against the old pro-model output) —
see the GCP spend-cap block below, which makes *any* live Vertex call fail
right now, not just a fresh validation batch. Flagged inside #61's own closed
row rather than silently skipping it.

**Found while checking `GET /api/admin/jobs` for the "no job running" push
gate**: two jobs stuck in a failure loop —

```
job 15: status running, spendCapUsd $8, spentUsd 0, photosDone 0,
        startedAt 06:11:13Z, lastError "photo 172: Spend cap breached for
        project: projects/663615238938 for service: aiplatform.googleapis.com"
job 14: status paused (already paused by something/someone before this
        session), spendCapUsd $1, spentUsd 0, photosDone 0,
        startedAt 05:59:44Z, lastError "photo 171: Spend cap breached ..."
```

Re-polled job 15 after a real 32-minute gap (06:11 → 06:43): `lastError`'s
photo id had only advanced from 171 to 172 — one photo in half an hour,
`photosDone` still 0, `spentUsd` still 0. Every attempt is failing at the same
point, slowly, forever (`claimBatch`/`processPhoto`'s per-photo `catch` in
`worker.js` treats this like any other single-photo error: log it, release
the lease, move to the next photo — there's no circuit breaker for "every
photo is failing on the identical non-retryable error", so the job just grinds
through the whole remaining queue for nothing).

Ran the diagnostic built for exactly this ambiguity — `GET
/api/admin/vertex-check` (the "reply with pong", no-image, minimal live
call) — to rule out "the app's own spend accounting is wrong" vs "Vertex
itself is refusing us": it failed too, immediately (117ms), with the identical
403:

```json
{"ok":false,"code":403,"httpStatus":403,
 "error":"Spend cap breached for project: projects/663615238938 for service: aiplatform.googleapis.com",
 "detail":"{\"error\":{\"code\":403,...,\"status\":\"PERMISSION_DENIED\"}}"}
```

**This is a GCP Cloud Billing budget hard cap on the GCP project itself**
(`projects/663615238938` — the project this app's Vertex AI reuses from
MyHealthOS, per `CLAUDE.md` §1), not our app's own `spendCapUsd` — two jobs
with different app-level caps (`$1` and `$8`) hit the *identical* error on
their very first photo, before a single token could be billed. No code change
in this repo can lift a GCP-account-level billing cap; it needs Radu (or
whoever holds the GCP billing console) to raise it, or to confirm it's an
intentional monthly cap and say when it clears.

**Paused both stuck jobs** (`POST /api/admin/jobs/15/pause` — 14 was already
paused) to stop the pointless retry loop; this is a reversible, ingest-token
admin action, not a `backend/**` code push, so it needed no "job running" gate
of its own. `GET /api/admin/jobs` immediately after confirms both `paused`,
`spentUsd` still `0` — no money was spent by any of this. Filed **#62** in
`BACKLOG.md` as `human` (per `status/README.md`'s "set status to human so no
lane claims it" rule) with the full repro, since no backend lane can act on a
GCP billing setting. Once Radu lifts it, resuming is a single `POST
/api/admin/jobs/{14,15}/resume` (or just let the next 06:00 UTC cron fire a
fresh job) — no code involved.

**No `backend/**` push this session** — no code changed (the code fix was
already on `main`), so nothing to push there; only `status/BACKLOG.md` and
this file changed, which don't touch `backend/**` and don't trigger a Railway
redeploy, so they're safe to push regardless of job state. Flipped `#61` →
`done` in `BACKLOG.md`; no row's `needs` references `61`, so nothing else
unblocks. Added `#62` as `human`.

## 2026-08-15 UTC (later session still, second follow-up): #60 — add Hong Kong to roaster countries

Only `ready` backend row this cycle (filed by Radu the same day, phase 6, no
`needs`). `git branch -r --list 'origin/claude/*'` showed only this session's
own branch — nothing stranded to adopt.

**`backend/migrations/021_add_hong_kong_roaster_country.sql`** (new) — same
shape as `017_add_switzerland_roaster_country.sql`: `INSERT INTO countries
(name, iso2, is_origin, is_roaster, kind) VALUES ('Hong Kong','HK',false,true,
'country') ON CONFLICT (name) DO NOTHING;`. Roaster-only (Hong Kong roasts,
doesn't grow coffee) — `is_origin` false, `is_roaster` true.

`cd backend && npm ci && npm test` — **252/252 green**, matching #56's
landing count exactly, no drift (this row needed no test changes — it's a
pure data migration, no code path to unit-test).

**Verified end-to-end against a real local Postgres 16** (started the
sandbox's local cluster, fresh `mycoffee_test60` DB, ran `node src/migrate.js`
against the full chain): all 21 migrations (001→021) applied clean.
`SELECT id, name, iso2, is_origin, is_roaster, kind FROM countries WHERE
name='Hong Kong'` → `id 51, iso2 HK, is_origin f, is_roaster t, kind
country` — exactly as specified. Re-ran `node src/migrate.js` a second time
against the same DB to confirm idempotency: `up to date, 0 applied`, country
count for `'Hong Kong'` still `1` (the `ON CONFLICT (name) DO NOTHING` holds).

Live-verified pre-push: `GET /health` → `{"ok":true,"db":true,"service":
"mycoffee-api"}`; `GET /api/admin/jobs` → 13 jobs, all `done`/`paused`,
**none `running`** — safe to push `backend/**` per the hard rule.

Pushed straight to `origin/main` (fast-forward `d84804e..aaec93e`; this
session's own `claude/confident-cerf-tumacs` branch carries the same commit,
so it isn't orphaned). Watched `railway-deploy.yml` run `31901891985` to
completion via the GitHub Actions API — **`completed success`**.

**Live-verified in production** — the row's own "verify Hong Kong appears in
the roaster-country picker" ask: the iOS roaster-country picker's vocab comes
from `GET /api/snapshot`'s `vocab.countries` (not `/api/config`, which is only
a small self-diagnostic with no vocab — checked `routes/config.js` directly
to confirm this before guessing at the wrong endpoint). `GET /api/snapshot`
against production now returns `{"id":51,"name":"Hong Kong","iso2":"HK",
"is_origin":false,"is_roaster":true,"kind":"country"}` in `vocab.countries` —
confirms the row's ask end-to-end, not just via the local-Postgres
reproduction above.

Flipped `#60` → `done` in `BACKLOG.md`. No row's `needs` references `60`, so
nothing else unblocks — this is a standalone vocab addition, no schema/API
shape change (the client already consumes `vocab.countries`, unchanged).

## 2026-08-15 UTC (later session still): #56 — populate `search_labels_blob`/`search_prose_blob`

Only `ready` backend row this cycle (filed by Radu himself the same day, phase
6, no `needs`). Live-checked the row's own claim before touching code:
`GET /api/snapshot/text` on production returned 120 coffees, **0 non-empty
blobs** — confirmed, not assumed.

**Root cause exactly as diagnosed**: `009_search.sql` declared
`search_labels_blob`/`search_prose_blob` (+ the generated `search_tsv`), and
`GET /api/snapshot/text` (`routes/coffees.js`) has always read them — but no
code anywhere ever wrote them, so every row sat at its `''` default forever.

**`src/lib/worker.js`**:
- `buildSearchBlobs(coffee, ctx)` (new, pure) — takes the coffee's resolved
  column values (`roaster_id`, `roaster_country_id`, `origin_country_ids`,
  `origin_farm_id`, `profile_id`, `profile_detail`, `raw_title`/`raw_caption`/
  `raw_description`) and `ctx.vocab` (already-loaded countries/roasters/farms
  candidates, same shape `buildCoffeeColumnUpdates` already consumes) plus a
  new `ctx.profileNameById` map, and returns `{labelsBlob, proseBlob}`, both
  run through `normalize.js`'s `foldDiacritics` (data-owned, imported not
  edited) per the migration's own "blobs are pre-folded" comment. Labels =
  roaster name + roaster country name + every origin country name + farm name
  + profile name + `profile_detail` (all `.filter(Boolean)`'d, so an
  unresolved id is skipped rather than stringifying to `"undefined"`). Prose =
  `raw_title`+`raw_caption`+`raw_description` (no separate OCR text field
  exists beyond what already lands in `raw_caption`/`raw_description` via
  `photo_texts`).
- `refreshSearchBlobs(coffeeId, ctx)` (new, DB-touching) — re-SELECTs the
  coffee row **after** `buildCoffeeColumnUpdates`'s UPDATE has landed (so a
  save that only touches e.g. `weight_g` still reflects whatever
  roaster/origin/farm was already on the row, not just this call's own
  resolutions), builds the blobs, writes them in one more UPDATE.
- `applyResolutionsToCoffee` now calls `refreshSearchBlobs` right after its
  existing column UPDATE and before `finalizeCoffeeStatus`. This is the single
  call site both of the row's two asks route through: the adjudication path
  (`adjudicateAndApply`) **and** `routes/coffees.js`'s generic per-field edit
  endpoint (#40) both already call `applyResolutionsToCoffee` — no separate
  wiring needed in `routes/coffees.js` itself, one shared fix covers both.
- `loadSharedContext()` now also selects `name` from `profiles` (previously
  only `id, slug`) and exposes `profileNameById` alongside the existing
  `profileIdBySlug`, so `buildSearchBlobs` can turn a `profile_id` back into a
  display name like "Washed"/"Experimental".
- `rebuildAllSearchBlobs()` (new, exported) — the row's own "add a one-time
  backfill" ask: loads shared vocab once, then calls `refreshSearchBlobs` for
  every non-deleted coffee. Deliberately scoped to just the two blob columns
  rather than reusing `readjudicateAll()` (which would also re-run full
  adjudication and could touch unrelated fields) — narrower, faster, and
  can't have any side effect beyond the two columns this row is about.

**`src/routes/admin.js`**: `POST /api/admin/rebuild-search-blobs`
(ingest-token-gated, same tier as every other admin mutation) calls
`rebuildAllSearchBlobs()` and returns `{updated}`.

**8 new `worker.test.js` cases** (252/252 green, up from 245): `buildSearchBlobs`
folding every label source + `profile_detail` together, prose joining with
diacritic-folding (a real Romanian caption fixture — "Prăjitorie"/"Panamá" →
"Prajitorie"/"Panama"), an unresolved id or missing vocab entry producing an
empty string rather than a stringified `undefined`, and a completely-empty
coffee/ctx producing empty blobs rather than throwing.

**Live-reproduced against a real local Postgres 16** (fresh `mycoffee_test56`
DB, migrations 001→020 applied clean, all clean — no migration errors):
- Inserted a coffee via `upsertCoffeeBase` with a Romanian raw caption/
  description, then ran `applyResolutionsToCoffee` resolving `roaster_id` +
  `origin_country_ids`. Blobs were empty beforehand (confirms the bug
  reproduces locally, not just in production) and came back non-empty and
  correctly folded afterward: `search_labels_blob` = `"Roastlab coffee
  roasters Ethiopia"`, `search_prose_blob` = `"Test title Cafea din Panama,
  prajitorie deosebita Prajitorie: Test"` (diacritics folded). The generated
  `search_tsv` computed correctly too — labels-derived lexemes carry weight
  `A` (`'roastlab':1A 'coffee':2A 'roasters':3A 'ethiopia':4A`), prose-derived
  ones the default weight, confirming `009_search.sql`'s `setweight` ranking
  actually engages now that the blobs are non-empty.
- Seeded a **second** coffee directly via SQL (bypassing the worker path
  entirely) with real `roaster_id`/`origin_country_ids` but empty blobs —
  simulating one of the 120 already-extracted production rows. Confirmed its
  blobs were empty pre-backfill, then ran `rebuildAllSearchBlobs()` and
  confirmed both populated correctly (`"Roastlab coffee roasters Ethiopia"` /
  `"Old title Cafea veche"`) — proves the backfill path independently of the
  live-write path.

`cd backend && npm ci && npm test` — **252/252 green**.

Live-verified pre-push: `GET /health` → `{"ok":true,"db":true,"service":
"mycoffee-api"}`; `GET /api/admin/jobs` → 12 jobs, all `done`/`paused`, **none
`running`** — safe to push `backend/**` per the hard rule. Also confirmed the
bug live on production before pushing the fix: `GET /api/snapshot/text` → 120
coffees, 0 non-empty blobs, exactly matching the row's own claim.

Pushed straight to `origin/main` (fast-forward `002c7b5..3a95d3e`). Watched
`railway-deploy.yml` run `31885457608` to completion via the GitHub Actions
API — **`completed success`**. Post-deploy: `GET /health`/`GET /api/status`
both still green, `GET /api/admin/jobs` still shows none `running`.

Ran the new backfill against **production**: `POST
/api/admin/rebuild-search-blobs` → `{"updated":120}`. Re-checked `GET
/api/snapshot/text` immediately after: **120 coffees, 120 non-empty
blobs** (up from 0), e.g. `"Public Coffee Roasters Germany Panama Elida
Estate Farm Washed"` for one real coffee — roaster, roaster country, origin
country, farm, and profile name all present and correctly space-joined. This
closes the row's "add a one-time backfill" ask against the real 120-coffee
corpus, not just the local-Postgres reproduction above.

Flipped `#56` → `done` in `BACKLOG.md`. No row's `needs` references `56`, so
nothing else unblocks — this is a search-quality fix, not a schema/API-shape
change (the client already consumes `GET /api/snapshot/text`, unchanged).

## 2026-08-15 UTC (later session): #51 — wire the caption-city roaster-country override into `worker.js`

Only `ready` backend row this cycle — filed by the data lane at 01:47 UTC,
*after* this lane's own last "no ready row" check (00:40 UTC) closed the
loop, so it wasn't a row a prior session missed.

`extractRoasterCountryOverride(rawText, countryVocab)` (`src/lib/deterministic.js`,
data-owned, #48b) was already written, tested, and live-Postgres-verified as
a pure function — it just wasn't called from anywhere. Two changes, exactly
as the row scoped them:

1. **`adjudicateAndApply()`** now threads `rawText` (already in scope — it's
   how the adjudicator itself resolves fields) into the `ctx` object passed
   to `applyResolutionsToCoffee`, alongside the existing `photoDate`.
2. **`buildCoffeeColumnUpdates`'s `roaster_id` case** now calls
   `extractRoasterCountryOverride(ctx.rawText, ctx.vocab?.countries)` and
   prefers its result over the vocab-derived `roaster?.country_id`, falling
   back to the vocab value when the override returns `null` (caption says
   nothing, or is ambiguous between two roaster-countries). Gated on
   `ctx.rawText` being present at all, so every existing caller that doesn't
   pass it (`routes/review.js`'s human-accept path, `routes/coffees.js`'s
   generic edit endpoint — neither builds a `rawText` ctx today) is
   completely unaffected: the override call is skipped outright and behavior
   is identical to before this row. Only the extraction/re-adjudication path
   (`adjudicateAndApply`) gains the new behavior, which is exactly where
   #48(b) was scoped to take effect ("takes effect the next time `POST
   /api/admin/adjudicate` re-runs").

**3 new `worker.test.js` cases** (248/248 green, up from 245): the
caption-stated country beating a differing vocab-derived one (the Uncommon
UK/NL shape, using a synthetic UK/NL fixture so it doesn't depend on #48a's
migration having already fixed the real Uncommon row); falling back to the
vocab-derived country when the caption names nothing; falling back again
when the caption names two distinct roaster-countries (ambiguous, per
`extractRoasterCountryOverride`'s own "never guesses" contract). None of the
existing roaster_id tests needed updating — they don't set `ctx.rawText`, so
`ctx.rawText ? ... : null` short-circuits to the same vocab-derived path as
before.

**Live-reproduced against a real local Postgres 16** (fresh
`mycoffee_test51` DB, migrations 001→020 applied clean) — deliberately used
a roaster/country pair the migrations haven't already touched, so the
before/after is a real change, not one where the vocab already agrees:
roaster id 2 ("The naughty dog", vocab `country_id` 28 = Czech Republic).
Ran `applyResolutionsToCoffee` directly against two synthetic coffees:
- Caption `"Prajitorie: The naughty dog (Paris, Franța)"` → `roaster_country_id`
  came back **30 (France)**, not the vocab-derived 28 — the override won.
- Caption `"Just a plain caption, no country mentioned at all."` →
  `roaster_country_id` came back **28 (Czech Republic)**, the vocab-derived
  value — confirms the fallback path is intact.

`cd backend && npm ci && npm test` — **248/248 green**.

Live-verified pre-push: `GET /health` → `{"ok":true,"db":true,"service":
"mycoffee-api"}`; `GET /api/status` → `vertex:true`, `db:true`; `GET
/api/admin/jobs` → 12 jobs, all `done`/`paused`, **none `running`** — safe to
push `backend/**` per the hard rule.

Pushed straight to `origin/main` (fast-forward `eb9fc8e..dfa6d3f`; this
session's own `claude/confident-cerf-9y3vqr` branch carries the same commit,
so it isn't orphaned). Watched `railway-deploy.yml` run `31870242046` to
completion via the GitHub Actions API — **`completed success`**. Post-deploy
`GET /health`/`GET /api/status` both still green.

**Did NOT run the actual `POST /api/admin/adjudicate` re-run against
production this session** — the session's own permission classifier denied
that specific call (a production-mutating POST), and per this repo's
"measure twice" rule I stopped rather than working around it. So the fix is
live in the deployed code, but every already-materialized `coffees.
roaster_country_id` value that a caption-stated override would correct is
still whatever the vocab-derived value was as of the last adjudication pass
— nothing wrong, just not yet re-applied. It's a $0, no-LLM-spend,
idempotent operation (`readjudicateAll()`, same one #35/#36/#44/#48a/#49 all
ran live without incident) — a future session (or Radu, directly) can run
`curl -X POST $BASE/api/admin/adjudicate -H "Authorization: Bearer
$INGEST_TOKEN"` with no body to apply it retroactively across the whole
corpus, or `{"photoId": "<publicId>"}` for just one photo. It will also
apply automatically the next time any photo goes through a fresh extraction
pass, with no action needed.

Flipped `#51` → `done` in `BACKLOG.md`. No row's `needs` references `51`, so
nothing else unblocks. This is a live-pipeline behavior change (affects the
next `POST /api/admin/adjudicate` re-run and future extraction passes), not
a schema change — no migration needed.

## 2026-08-14 UTC: #49 — retract a stale `coffees` column when re-adjudication flips a field to `absent`

The only `ready` backend row this cycle (found while validating #39's own
production rollout, same session cycle). Confirmed live before touching code:
`GET /api/coffees/ZqjVWBODPm-oKNqoCTmQWg` and `.../zh8V1tWHHFmq0vyTox1sKQ`
still returned the bogus `altitudeMinM/MaxM` `2`/`30` and `1`/`5` — exactly
the row's own claim, `GET /api/admin/jobs` confirmed no job `running`.

**Root cause, precisely**: `adjudicateField` (`adjudicate.js`) only ever
returns `value: null` for `decision: 'absent'` — a field that had at least
one stored `field_candidates` row this pass (it's a key in `resolutions` at
all — `adjudicateRecord` only iterates `candidatesByField`'s own keys) but
none survived `canonicalize()`. `buildCoffeeColumnUpdates`'s old
`if (res.value == null) continue` treated that identically to "this field
was never voted on this pass at all" (which, per the above, is already
structurally impossible to reach this loop — such a field is simply absent
from `resolutions`, never a `continue`-triggering iteration). So the "leave
alone" and "must retract" cases were being conflated into the same
`continue`, and the retract case never happened.

**Fix** (`backend/src/lib/worker.js`, `buildCoffeeColumnUpdates`): guard is
now `if (res.value == null && res.decision !== 'absent') continue` (the
`!== 'absent'` half is defensive only — no real caller produces a null value
under any other decision, verified by reading every call site: the worker's
own `adjudicateRecord`, and `routes/review.js`/`routes/coffees.js`'s
`resolveField`-backed paths, which 422 rather than ever writing a null
value). Every switch case now writes an explicit `NULL` for its column(s)
when `value` is null instead of skipping: `rating`, `weight_g`, `roasted_on`,
`origin_farm_id`, `desc_*` (single column each); `altitude` (`min`+`max`);
`price` (all 5: amount/currency/eur/fx_rate/fx_rate_period — skips the EUR
conversion call entirely rather than calling `toEur` with nulls);
`roaster_id` (itself + its derived `roaster_country_id`); `origin_country_ids`
(+ `is_blend`); `profile` (`profile_id`/`profile_detail`/`is_decaf`).

**10 new `worker.test.js` cases** (236/236 green, up from 226): rewrote the
one existing test that asserted the *old* (buggy) skip behavior for
`rating`'s absent case into a retract-assertion, added matching absent-retract
cases for `altitude`, `weight_g`, `price`, `roaster_id`, `origin_country_ids`,
and `profile`, plus an explicit test that an *empty* `resolutions` object
(modeling "never voted on this pass at all") still produces no SET clauses —
the other half of the row's own "distinguish absent-from-map vs.
present-with-absent-decision" ask.

**Live-reproduced the exact bug against a real local Postgres 16** (fresh
`mycoffee_test49` DB, migrations 001–015 applied clean) before trusting the
unit tests alone: seeded a `coffees` row with `altitude_min_m/max_m = 2/30`
(simulating a stale prior `accepted` pass, pre-#39), fed it one
`field_candidates` row with an implausible `"2-30m"` altitude string, ran
`adjudicateAndApply()` directly. `parseAltitude` (#39, already on `main`)
correctly rejects it — `canonicalize` returns `null`, zero surviving
candidates, `decision: 'absent'`. **Before this fix** (verified by reverting
the change locally and re-running) the columns stayed `2`/`30`; **after**,
both come back `null`, and the `field_resolutions` row shows
`{field: 'altitude', value: null, confidence: 0}` — the resolution layer was
already correct (per #39's own writeup), now the denormalized column matches
it.

`cd backend && npm ci && npm test` — **236/236 green**.

Live-verified pre-push: `GET /health` → `{"ok":true,"db":true,"service":
"mycoffee-api"}`; `GET /api/admin/jobs` → 11 jobs, all `done`/`paused`, **none
`running`** — safe to push `backend/**` per the hard rule.

Flipped `#49` → `done` in `BACKLOG.md`. No row's `needs` references `49`, so
nothing else unblocks.

Pushed straight to `origin/main` (this session's own `claude/confident-cerf-fti5j5`
scratch branch carries the same commits, so it isn't orphaned per the
"integrate before you start" rule). Watched `railway-deploy.yml` to
completion (`31777952352`, both `test` and `deploy` jobs green).

**A real bug the live production run caught, not the unit suite**: the first
version of this fix retracted every absent field to `NULL`, including
`origin_country_ids`/`is_blend`/`is_decaf` — but `008_coffees.sql` declares
all three `NOT NULL` (`origin_country_ids ... NOT NULL DEFAULT '{}'`,
`is_blend ... NOT NULL DEFAULT false`, `is_decaf ... NOT NULL DEFAULT
false`). The unit tests I'd written for those two fields asserted `NULL` too
(same blind spot, no DB to catch it), so `npm test` was green while the
route would 500 in production. Running the actual `POST /api/admin/adjudicate`
against **production** immediately surfaced it: `500 {"code":"23502",
"error":"Internal Server Error","message":"null value in column
\"origin_country_ids\" of relation \"coffees\" violates not-null
constraint"}`. Fixed by retracting those three columns to the table's own
`DEFAULT` (`[]`/`false`/`false`) instead of `NULL`; updated the two affected
`worker.test.js` cases to match, and reproduced both the original 500 and its
fix against a real local Postgres (a coffee with real prior `origin_country_ids`/
`is_blend` values, fed an unresolvable origin-country candidate so it
decides `absent` — `adjudicateAndApply` no longer throws, and the row lands
on `{ids: [], isBlend: false}` as expected; same shape for a `profile`-absent
case landing on `is_decaf: false`). Re-ran `npm test` — **236/236 green**
with the corrected assertions — before pushing the fix commit and re-deploying.
This is exactly why this lane's protocol runs a real end-to-end verification
against production/a live Postgres in addition to the unit suite (see the
`origin_country_ids`/`price`/`profile` NOT-NULL-vs-nullable distinction now
called out inline in `worker.js`'s comments) — a unit test alone would have
shipped this to production green.

Once the fix redeployed (`railway-deploy.yml` run for the follow-up commit,
completed success), ran the actual $0 re-adjudication
(`POST /api/admin/adjudicate`) against **production** — the same safe,
no-LLM-spend operation #35/#36/#44 were verified live with — and it completed
without error this time. Re-checked the two coffee ids #39's own note named:
`GET /api/coffees/ZqjVWBODPm-oKNqoCTmQWg` and `.../zh8V1tWHHFmq0vyTox1sKQ`
now both return `altitudeMinM`/`altitudeMaxM` as `null` instead of the old
bogus `2`/`30` and `1`/`5` — confirms the fix closes #39's own flagged gap
end-to-end in production, not just in tests.

## Abandoned

_none_

- **2026-08-28 — #91 DONE: production re-adjudication, #51's caption-city
  roaster-country override finally applied to already-adjudicated rows.**
  `#51` shipped the code in 2026-08-15 but its own session's permission
  classifier denied the retroactive `POST /api/admin/adjudicate`, so every
  coffee adjudicated before that date still carried the vocab-derived
  `roaster_country_id`. Radu approved the re-run on 2026-08-28.

  Procedure: confirmed no job was `running` via `GET /api/admin/jobs` (newest
  was job 37, `done`, `photosDone: 0` — the merged ingest-drain routine's 08:13
  pass), captured `GET /api/snapshot` to disk, ran `POST /api/admin/adjudicate`
  → `{"photosReadjudicated": 411}`, then re-fetched the snapshot and diffed all
  410 coffees field by field. $0 — no LLM spend, it re-derives from stored
  `field_candidates`.

  **Measured diff (not asserted — every number below is from the before/after
  snapshot comparison):**

  | Field | Coffees changed | Notes |
  |---|---|---|
  | `roasterCountryId` | **1** | `COphnAhjvqLQ-5U7DXY_TQ`, 42 → 40. The fix this row existed for. |
  | `altitudeMin/Mid/MaxM` | **31** | `None` → a real altitude (1100, 1850, 1200, 2000 m …). Pure gain. |
  | `originFarmId` | 3 | Repointed onto newly-created farm rows — see the caveat below. |
  | `reviewState` | 2 | `clean` → `needs_review`; re-adjudication surfaced splits. Queue 6 → 8. |
  | *(new coffee)* | 1 | `ESVarM-49a21FnMXw36MqA` — a photo that had never materialized a coffee row now has one (rated 4.2, purchased 2024-10-23). 410 → 411. |

  **Honest read of the outcome:** the row's premise was that *many* coffees
  carried a stale vocab-guessed roaster country. In fact **one** did. The pass
  was still clearly worth running — 31 coffees gained altitude data and a
  missing coffee appeared — but the roaster-country blast radius was one bag,
  and the backlog row overstated it.

  **It also exposed a latent bug, filed as #98.** The pass created 4 farm rows,
  two of which duplicate farms that already existed under a longer name:
  `Banko Gotiti` (185) vs `Banko Gotiti Washing Station` (68), and
  `Nano Challa Cooperative` (186) vs `Nano Challa` (47). The farm vocabulary has
  no alias/fuzzy coverage for the `"<name>"` ↔ `"<name> Washing Station"` /
  `"Cooperative"` suffix pair, so #36/#44's get-or-create mints a second row
  rather than matching the first. **This is not a #91 regression** — the same
  path fires on any fresh extraction pass, so it was already latent and would
  have bitten on the next new coffee; the re-adjudication only made it visible
  at scale. The other two new rows are legitimate: `BENTI NENKA WASHING STATION`
  (187) is a genuinely different farm — which is also the negative test case any
  fuzzy fix must not break — and `Finca El Jaragual` (184) belongs to the new
  coffee. Fix + the production merge of the 2 duplicate pairs is data-lane work,
  tracked in #98.
