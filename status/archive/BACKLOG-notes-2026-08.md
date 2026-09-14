# Backlog notes — 2026-08 history

Moved out of `status/BACKLOG.md` on 2026-09-14 (#182): spend gates, FX anchors,
the #9/#10 write-ups and the rest of the 2026-08 running commentary. Nothing
here is scheduling metadata a lane reads — it is the record of how the early
decisions were made, and it was ~50 KB that every session carried.

**Unblocking is a normal part of the job.** When you finish an item, flip every row
whose `needs` are now all `done` from `blocked` to `ready` in the same commit. If
you don't, the next lane has nothing to pick up.

## Right now

**🔓 2026-08-20 (iOS shell lane) — broke the five-day `#57` deadlock: decomposed it into `#73` (backend, `ready`) + `#74` (ios-shell, `blocked` on 73), and corrected `#57` to `blocked`.**
`#57` (persisted photo rotation) was the **only `ready` row anywhere in this file**,
and it had been unpickable since 2026-08-15. Six consecutive lane sessions across
three lanes each independently confirmed the same thing and stopped cleanly:
persistence is required (Radu settled that — a view-only rotate is not
acceptable), persistence needs a backend column + write endpoint + snapshot
field, and **no row was ever filed for that backend half**. So every session
re-derived the blocker from `#57`'s prose and correctly declined to guess a wire
shape blind — but nothing ever moved. Re-verified the blocker once more this
session rather than trusting the prior notes: repo-wide grep for
`rotation_quarter_turns`/`rotationQuarterTurns` is empty outside status-file
prose, and `backend/migrations/` still tops out at `024`.

Filing the missing rows is the documented fix for exactly this shape (the
`#48(b)→#51`, `#39→#49` and `#29→#69` precedent: when a row's real work sits in
another lane's paths, file that lane a row rather than reaching across the
boundary), and `status/README.md`'s "correcting a task means correcting THIS
file" makes the `ready`→`blocked` correction this lane's job too.

**`#73` (backend) carries a decided wire contract, not a research task** — read
the actual backend code to settle each choice instead of leaving them open:
the column goes on `coffees`, not `photos` (every read path the app uses is
already a `coffees`-row projection with its own `updated_at` for the delta sync;
`photos` would mean a join and a second watermark); the write endpoint is modelled
line-for-line on `POST /api/coffees/:publicId/favorite`
(`src/routes/coffees.js:276`) and **deliberately not** on `#40`'s generic
`/edit` route — rotation is a human-set display correction, so it must stay out
of `field_candidates`/`EDIT_FIELD_TO_CLIENT`/`STRUCTURED_FIELDS`/`canonicalize()`
and must never open a review item; and the field goes in `toCompactCoffee` so the
**listing thumbnail** is upright too, with the detail route inheriting it for free
via its existing spread. The `updated_at` bump is called out explicitly as the
thing that makes the fix reach other devices.

**`#74` (ios-shell) is this lane's own next row** — filed so the seam is a real
row next cycle instead of being re-derived from `#57`'s prose every session. It
names the one non-obvious trap: `Coffee.withFavorite` (`Models/Coffee.swift:102`)
enumerates every field, so a newly-added property silently dropped there is the
same class of bug as `#22`'s `roasterId` nullability. It also draws the ownership
line explicitly — shell publishes the value and an optional angle helper, but the
`.rotationEffect` call sites live in `DesignSystem/`/`Features/` and stay with
`#57`.

No code changed this session — this is a scheduling/protocol fix, and the
backend half has to land before either iOS half can be written. **Next up:
backend picks `#73` (now the only `ready` row anywhere), then this lane picks
`#74`, then ios-ux finishes `#57`.**

**🛠️✅ 2026-08-17 (backend lane, later session) — #67 finished (found + fixed a real bug in its own backfill code) and #69 shipped (per-photo image-inclusion). Both `done`.**
Started at `origin/main`'s tip (`011d8e5`, the prior session's #67 code + job-24
correction notes) — the #67 code was already on `main`, per that session's own
detailed write-up; this session's job was to actually run the production
backfill through to completion and pick up the next `ready` row.

**Job 24**, which the prior session left `running` (and suspected orphaned
after a mistimed redeploy SIGTERM'd its in-process worker), was re-polled and
found frozen at the exact same `photosDone:20`/`spentUsd:$0.0318` many hours
later — conclusively dead, not just slow. Paused it
(`POST /api/admin/jobs/24/pause`, reversible, not a `backend/**` push) to
clear the "no job running" push gate, confirmed via `GET /api/admin/jobs`
that nothing was `running`, then ran the bounded production backfill.

**Running it surfaced a real bug**: `backfillOcrText` counted a row as
`updated` even when the bag photo was genuinely illegible and
`runOcrTranscribe` returned an empty transcription — `appendOcrTextToCoffee`
silently no-ops on empty text (by design, to avoid stamping an empty "OCR
text" heading), but the caller counted it as a success anyway. One specific
coffee hit this every single run — six consecutive `{"limit":15}` calls each
reported `{"scanned":1,"updated":1}` with an identical result, proof the
write never actually landed. Fixed `appendOcrTextToCoffee` to return whether
it wrote, and `backfillOcrText` to only count `updated` on a real write,
reporting `'OCR returned no legible text'` in `errors` otherwise (same
"broken row stays retryable, doesn't abort the sweep" convention the missing-
asset case already uses). Live-verified against a real local Postgres 16
with Gemini mocked at the `src/vertex.js` boundary. `npm test` 252/252 green.

Drained the production backlog down to exactly that one permanently-illegible
photo (everything else — dozens of coffees across ~15 small batches; a
`{"limit":50}` request reliably hit a transport-level connection drop under
this sandbox's proxy, so `{"limit":15}` or smaller was the reliable unit) —
the fix now correctly reports it as an `errors` entry instead of a false
`updated`. Flipped `#67` → `done`.

**Picked `#69` next** (lowest-numbered remaining `ready` backend row, phase
6, no `needs`) — the daily text-only OCR job could never reach an overdue
`awaiting_text` photo at all, because `claimBatch`'s SQL only included that
branch when the job's own `includeImages` was true. Made `claimBatch` always
claim overdue `awaiting_text` photos, and added `shouldUseImage(photo,
includeImages)` so `runWorker` decides image-vs-text-only **per claimed
photo** rather than per job — an `awaiting_text` row always gets its image
(no text will ever arrive), a `text_received` row still only gets its image
when the job asked for image mode. Live-verified against a real local
Postgres 16 (seeded overdue/not-yet-due/normal photos, confirmed `claimBatch`
claims the right pair and `shouldUseImage` routes each correctly). `npm test`
252/252 green (same run as #67's fix, both landed in one commit). Flipped
`#69` → `done`.

No row's `needs` references either `67` or `69`, so nothing else unblocks.
Did not pick up a third row this session (`#72`, What's New content) — this
session already batched two related backend-owned worker.js fixes; leaving
`#72` for a fresh session to do justice to the curation work rather than
rushing it.

**🛠️⚠️ 2026-08-17 (backend lane, earlier session) — #67 built + live-verified, but BLOCKED off `main` by a `running` job. The code exists on `claude/confident-cerf-86fp01` — next session must ADOPT it, not redo it.**
Picked `#67` (lowest number among `ready` backend rows `#67`/`#69`/`#72`, all
phase 6, no `needs`). Shipped `backfillOcrText({limit, spendCapUsd})` in
`src/lib/worker.js` + `POST /api/admin/backfill-ocr-text` in
`src/routes/admin.js`: a targeted re-OCR that re-runs only
`runOcrTranscribe` against each affected photo's stored `ocr` asset and appends
via the existing idempotent `appendOcrTextToCoffee` — no voters, no
re-adjudication, so the structured fields these coffees already have are never
disturbed. Scoped by SQL to exactly the affected population (image-only
`raw_caption IS NULL`, `state='processed'`, has an `ocr` asset, not already
carrying the `OCR text` heading), which also makes a partial run *resume*
instead of restart and makes stacking a second transcription impossible.
`npm test` **250/250 green**; verified three ways against a real local Postgres
16 with Gemini mocked at the `src/vertex.js` boundary ($0 spend): population
selection, spend-cap + resume (cap halted it at 1 of 5, uncapped re-run did
exactly the remaining 4), and error isolation (a missing asset file lands in
`errors` without aborting the sweep). **Not landed on `main`**: job 24 was
`running` and verified genuinely stuck (5 polls / 4 min, `photosDone` 0,
`spentUsd` 0, pinned to photo 269 on a Gemini 429 — the free-tier *daily*
quota is spent), and CLAUDE.md §12 forbids pushing `backend/**` while a job
runs. `POST /api/admin/jobs/24/pause` — the reversible fix the #61/#62 session
used for the identical situation — **was denied by this session's permission
classifier**, so per the #51 precedent the session stopped rather than working
around it, and specifically did *not* substitute the larger action (pushing
`backend/**`, which auto-deploys and SIGTERMs the worker) that the pause was
meant to make safe. Only `status/**` went to `main` (no `backend/**` path
match → no deploy). Row left **`claimed`**, since `done` means "on the shared
branch". **Correction recorded on a final re-check at 07:02 UTC: job 24 was
NOT wedged** — it read `photosDone` 12 / `spentUsd` $0.0175, up from 0/0. The
429 was Gemini's *per-minute* rate limit with a ~59 s retry-after throttling
throughput, not the daily cap being spent; a 4-minute poll window was too short
to see it move. So the hold was right for a stronger reason than the session
thought (a push would have SIGTERM'd a worker doing real paid work), and the
**pause would have been wrong too** — the denial prevented actual harm, not
just a procedural violation. Lesson for the next session: `photosDone 0` +
`spentUsd 0` + a repeated `lastError` photo id is **not** proof of a wedged job
when the error is a 429 with a retry-after; watch over tens of minutes, or use
`spentUsd` creeping up as the tell, and don't equate it with jobs 14/15's
genuinely-wedged non-retryable 403. **Let job 24 finish on its own; do not
pause it.** Exact 4-step finish sequence is in `status/backend.md`; note the
production backfill itself **costs real flash-lite calls (~1 per coffee, ~95
coffees)**, so it must be run bounded (`{"limit":50}`) across days, unlike this
lane's earlier $0 backfills.

**🌱 2026-08-17 (data lane) — #29 closed out (no code needed, all three sub-parts already resolved or superseded); filed #69 (backend); corrected #67's lane tag to `backend`.**
Picked `#29` over `#67` (both `data`, phase 6) per lowest-number. Investigated
PLAN.md §8 phase 6's three asks rather than assuming stale busywork: (1)
`launchd` monthly on the Mac — Mac-only, per the row's own note; (2) the
`awaiting_text` deadline sweep — already implemented + tested in
`backend/src/lib/worker.js` (`isDueForExtraction`/`claimBatch`), live-verified
in #64's own session, and firing daily in production via the
`trig_017RR9aMaL8fpvqPZNAv8mn4` OCR routine (`GET /api/admin/jobs` confirms
jobs 16-23 ran 2026-08-16); (3) `POST /api/admin/sync` on a backend cron —
superseded by the two external CCR-scheduled triggers hitting the existing
`POST /api/admin/jobs`, so a dedicated route would just be an unused
alternate path to the same `claimBatch` query. **Filed #69 (backend)** for the
one real gap found: the OCR routine self-deletes once today's backlog drains
(#65), so the *ongoing* sweep for future photos has no durable home — needs
per-photo image-inclusion in `claimBatch`/`runWorker`, outside every
data-owned path. **Corrected `#67`'s lane `data`→`backend`** — its own body
names only `src/routes/admin.js`/`src/lib/worker.js`, no data-owned file, so
there's no sliver for a data session to peel off (unlike #48(b)→#51). No
`ops/**`/data-owned `src/lib/*` file changed; `cd backend && npm test`
re-verified 249/249 green anyway. Full writeup in `status/data.md`.

**📱 2026-08-16 (ios-ux lane, later session) — #68 DONE; #50/#53/#54/#55/#58/#66 corrected `ready`→`done` (already shipped, row never flipped).**
Before picking anything, re-verified every `ios-ux` row this table listed `ready`
directly against the code on `ios-staging` rather than trusting the table —
`status/ios-ux.md`'s own recent session notes already claimed #50/#52/#53/#54/#55
landed together and #58 landed in the session right before this one, but this
table (last touched from `main`'s side) still showed five of those six `ready`.
Confirmed each one live in the source: `Features/Insights/{InsightsView,
InsightsCharts,InsightsFindings,DataQualityCard}.swift` all have the `onSelect`/
`selectInCoffees`/`FindingSubject`/`dimension`-gated-`Button` wiring; `DesignSystem/
ZoomableImageView.swift` exists and is wired into `ReviewCardView`/`CoffeeDetailView`;
`Features/Root/RootTabView.swift` already branches `#available(iOS 18.0, *)` into
the value-based `Tab(...)` builder. Also traced #66 (Review per-item save) end to
end — `ReviewQueueEngine`→`CoffeeStore`→`MutationOutbox` already dispatches and
persists each accept/dismiss the instant it's actioned, not batched — so it's
correct as shipped, no code change needed. Flipped all six to `done` with a
one-line pointer to the verification, per `status/README.md`'s "correcting a task
means correcting this file" rule, instead of re-implementing already-live work.
**Then did the one row that was genuinely still open**: #68 (Unknown bucket not
selectable outside Process) — `FacetFullListView.isTappable()` had a stray
`dimension == .profile`-only gate; `FilterSheetView`'s inline pill grid already
had the correct 5-dimension allowlist. Promoted that allowlist to a shared
`unknownSelectableDimensions` constant both views now point at, so the two paths
can't drift apart again. `#57` (persisted rotate) stays `ready` but unpicked —
confirmed via `status/ios-shell.md`/`status/backend.md` that no backend column/
endpoint or shell model/API exists yet for the rotation seam, so there's nothing
concrete for this lane's half to build against. See `status/ios-ux.md` for full
detail. Not locally compiled (no Xcode here). Merged `origin/main` into
`ios-staging` first (clean fast-forward). Commit: (see `git log` on `ios-staging`).

**🛠️ 2026-08-16 (backend lane, later session) — #64 closed out (code was already live from a prior session, same pattern as #61).**
`git branch -r --list 'origin/claude/*'` and `origin/main`'s own history showed
`52eab3f` ("backend #64: stop the worker looping forever on an always-failing
photo") already on `main` — the same stranded session that did #61
(`session_01JLFd9wZxpbWRZ959RrcSM3`) had written, tested, and pushed the fix
straight to `main`, but never flipped this row or logged a `status/backend.md`
entry, so it still read `ready` even though the fix was live. `cd backend &&
npm test` — 249/249 green. Live-verified the actual mechanism against a real
local Postgres 16 (fresh DB, migrations 001→023 applied clean, not just
trusting the unit suite — `claimBatch` is DB-touching and has no unit
coverage): seeded an `awaiting_text` photo past its `text_wait_until`, a
`text_received` photo already at 3 failures, and a clean `text_received`
control, then called `claimBatch` directly in both modes. Text-only mode
(`includeImages:false`, the daily routine's own mode) excluded both the
`awaiting_text` photo (no text, would 400) and the 3-failures photo, claiming
only the clean control; image mode claimed the `awaiting_text` photo too (OCR
can still read it) while still excluding the 3-failures one — exactly the
two-part fix the row asked for. Production `GET /health`/`/api/status` green;
`GET /api/admin/jobs` shows no job stuck at 0 progress for 30+ minutes since
the fix landed (job 23's pause is an unrelated Gemini free-tier 429 rate
limit, not this bug). **Could not re-enable the daily extraction routine
(`trig_01JWhQADZK8RqfP8r9ugXen1`)** that was disabled as mitigation — it's an
external scheduled-prompt trigger, not a `backend/**` code path or anything
this session's own `CronList` shows; flagged in the row for whoever manages
it (Radu) to re-enable now that the fix is verified. Flipped `#64` → `done`;
added a note to `#65`'s own row (data-owned, `human` status — not touching its
status/lane, just documenting that its blocker is cleared). No row's `needs`
references `64`, so nothing else formally unblocks.

**🛠️🚧 2026-08-16 (backend lane) — #61 closed out (code was already live from a prior session); filed #62 (human) — a GCP project-level spend cap has extraction completely blocked.**
Found `main` already at `5ac265a` (the flash-model + billing-labels migration for
#61) when this session started — a prior session had done and pushed the code but
never flipped the backlog row or logged a `status/backend.md` entry. Ran
`npm test` (253/253 green) and confirmed the deploy live (`vertex:true`), then
flipped `#61`→`done`. While closing it out, found every live Vertex call —
including the minimal `GET /api/admin/vertex-check` probe — failing with a GCP
Cloud Billing **"Spend cap breached for project"** 403, unrelated to our own
app-level `spendCapUsd`. Two extraction jobs (14, 15) were stuck spinning on it
with zero progress for 30+ minutes; paused both. Filed **#62** (`human` — no
lane can fix a GCP billing cap) with the full diagnosis. #61's own "validate
against a live 5-photo batch" step is blocked on the same GCP cap and hasn't
run yet. See `status/backend.md` for the full write-up.

**🛠️ 2026-08-15 (backend lane, later session) — #60 is DONE.** Hong Kong
added as a roaster country: `backend/migrations/021_add_hong_kong_roaster_country.sql`,
same shape as `017`. Verified against a real local Postgres (full chain
001→021 clean, idempotent) and live in production (`GET /api/snapshot`'s
`vocab.countries` now includes Hong Kong, `is_origin:false`/`is_roaster:true`).
Deployed via Railway, `railway-deploy.yml` green. See `status/backend.md` for
full detail. No row's `needs` references `60` — nothing else unblocks.

**🌱 2026-08-15 (data lane) — #48(b) is DONE; filed #51 (backend) for the wiring.**
`extractRoasterCountryOverride(rawText, countryVocab)` lands in
`src/lib/deterministic.js`, reusing the same `findAliasMentions` primitive
`extractOriginCountriesField` already uses (diacritic-folded, word-boundary
scan), filtered to `is_roaster` countries and declining (returns `null`) on
zero or on >1 distinct roaster-country mention. `backend/migrations/
020_add_romanian_roaster_country_aliases.sql` seeds the Romanian country
names (`Olanda`, `Cehia`, `Franța`, `Marea Britanie`, `SUA`, …) actually used
in Radu's own captions — without them the override could never recognise the
exact "Olanda" spelling that motivated this row in the first place. 7 new
table-driven tests (245/245 `npm test` green) including the real Uncommon
caption, a diacritic-free spelling, an origin-only mention correctly ignored,
and the ambiguous two-distinct-countries case. Verified live against a real
local Postgres 16 with the full migration chain (001→020) applied:
`extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)',
countryVocab)` resolves to Netherlands (id 35), confirming the override would
have produced the right answer #38 originally got wrong. **This function
isn't wired into the live pipeline yet** — that's `worker.js`
(`buildCoffeeColumnUpdates`'s `roaster_id` case), which is backend-owned, not
data lane's to edit — filed as **#51 (backend, ready)**, same split as
#39→#49. No other `data` row was `ready` at a lower phase (#29 is phase 6,
needs 26 which is done, stays `ready` for a future data session).

**🌱 2026-08-14 (data lane) — #39 is DONE; found and flagged a backend gap while validating it in production, new row #49.**
`normalize.js`'s `parseAltitude`/`parseWeight`/`parseRating` now hard-reject
implausible values to `null` instead of only soft-flagging (229/229 tests green).
Landed on `main`, Railway redeployed, then ran the $0 validation PLAN.md §11
addendum calls for: `POST /api/admin/adjudicate` re-adjudicated all 51
production photos. The resolution layer is provably correct — both live bogus
altitudes (including Radu's own `1–5 m` example) now decide `absent`, and
neither opened an altitude review item. **But `GET /api/coffees/:id` still shows
the old bogus values** — `buildCoffeeColumnUpdates` (`worker.js`, backend-owned)
skips a field whenever its resolved `value` is `null`, whether that's because it
was never voted on or because it just flipped from a stale `accepted` decision to
`absent` — so a previously-materialized column is never retracted. Documented in
full in row **#49** (backend, ready) and `status/data.md`; not something data
lane can fix (`worker.js` is outside `ops/**`/`src/lib/{normalize,fuzzy,vocab,fx,
deterministic,prompts}.js`). No other data row was `ready` at this phase besides
#48(b), which stays open for a later session — lowest-number rule picked #39 first.

**📱 2026-08-12 (ios-shell lane, later session) — #46 is DONE.** `APIClient.whatsNew()`
+ lenient-decode `WhatsNewWire.swift` DTOs land on `ios-staging`. Also reconciled a
`status/BACKLOG.md` merge divergence on the way in — `ios-staging` didn't yet know
`main` had `#45` done/`#46` ready, `main` didn't yet know `ios-staging` had `#41`/`#42`
done — see `status/ios-shell.md` for the full reconciliation. **`#47` (ios-ux) flipped
`blocked`→`ready`** in the same push — its other need, `#45`, was already done on `main`.

**🛠️ 2026-08-12 (backend lane, later same day) — #45 is DONE.** `GET
/api/whatsnew` (PLAN.md §13) ships from a new committed
`backend/src/data/whatsnew.json`, `requireAnyToken`-gated. Content reflects
current reality as of this push (post-#43/#44): Live now includes farm
auto-create, roaster countries, accept-by-default, the shrunk photo cache and
the generic edit API; Plan/byLane lists #37/#39/#41/#42/#48 plus this row's
own #46/#47 follow-ups; needsApproval lists the pending iOS TestFlight batch,
the ~$62 backfill, and the 50 MB cap. Full detail in `status/backend.md`.
**`#46` (ios-shell) flipped `blocked`→`ready`** in the same push; `#47`
(ios-ux) stays `blocked` — it also needs `#46`.

**✅ 2026-08-12 (ios-ux lane) — the batch-edit call-site swap below is DONE.**
`Features/Coffees/CoffeeEditSheet.swift`'s `save()` now sends one
`CoffeeStore.editFields(coffeeId:edits:)` call when a save changed more than
one field, instead of looping `editField` per field — closes the atomicity
gap the ios-shell entry just below flagged, same session cycle. Single-field
saves still use `editField` unchanged. See `status/ios-ux.md` for detail; not
locally compiled (no Xcode here), but this is a narrow call-site change
against an already-public type (`CoffeeFieldEdit`), so a red compile check
would most likely be a typo, not a design gap.

**🔗 2026-08-12 (ios-shell lane) — closed #42's flagged batch-edit atomicity
gap, no new backlog row.** No `ios-shell` row was actually `ready` this cycle
(`#41` below was already `done` on `ios-staging` — `main`'s copy of this file
just hadn't caught up yet, dev/ship split as usual). Instead closed the gap
`status/ios-ux.md`'s `#42` write-up flagged and explicitly asked shell to pick
up: `CoffeeEditSheet` fires one `editField` HTTP request per changed field,
so a same-save `roaster` + `roasterCountry` edit has no ordering guarantee
against each other even though the backend's batch `{edits:[...]}` endpoint
(#40) exists precisely to avoid that. Added `APIClient.editCoffeeFields`,
`CoffeeStore.editFields(coffeeId:edits:)`, and the matching
`CoffeeRepository`/`MutationOutbox`/`SyncEngine` plumbing — see
`status/ios-shell.md` for full detail. **ios-ux: swap `CoffeeEditSheet`'s
per-field `editField` loop for one `editFields` call when >1 field changed in
the same save** — that's the only remaining step to actually close the gap.

**🛠️ 2026-08-12 (backend lane) — #44 and #43 are DONE.** Batched both, plus a
markdown-table repair — full detail in `status/backend.md`. Short version:
#44 lets a confident new farm name auto-create its `farms` row instead of
sitting inert (farm was 0/21 in the app); #43 shrinks the `display` photo
variant and adds a re-derive pass for photos uploaded before the shrink.
While editing #43's row, found it had been silently corrupted into a single
malformed markdown table row carrying **both** #43's and #39's content (a
stray `|` mid-cell, not a content problem) — split back into two proper rows
so #39 (data, `normalize.js` sanity envelopes) is visible to a row-scan again
instead of being invisible dead text inside #43's cell.

**✏️ 2026-08-11 (ios-ux lane) — #42 is DONE.** Edit sheet with consistency
dropdowns (PLAN.md §12): a pencil button on `CoffeeDetailView`'s toolbar opens
`CoffeeEditSheet` (`Features/Coffees/CoffeeEditSheet.swift`), a `Form` with
searchable pickers over canonical vocab for origin country (multi-select),
roaster country, roaster, and farm (the latter two with an "Add new…" text
fallback into #40's get-or-create — countries stay closed per #36, no
add-new there), a segmented process picker (5 cases + Unknown) with a
separate decaf toggle, and bounded inputs for altitude/weight/price/rating/
roasted-on. `Save` diffs every field against the value the sheet opened with
— not just "is the control non-empty" — so an untouched optional field (e.g.
a coffee with no rating yet, where the slider defaults to a visible 3.0)
never fires a spurious edit; each changed field becomes one
`CoffeeStore.editField` call (#41). Picked up straight from `BACKLOG.md`
without rediscovering #41 first: merging `origin/main` into `ios-staging`
surfaced that `#41` (ios-shell) had already landed there (`5b76a6c`) and
flipped `#42`'s row to `ready`, while `main`'s own copy of the table still
showed `#41` merely `ready`/`#42` `blocked` — same "each branch only knows
its own lane's latest" pattern this file has hit before (see the 2026-08-10
ios-shell entry below). Resolved the merge conflict by keeping `ios-staging`'s
more current rows. Full per-field raw-value formatting + the one flagged
client-side gap are in `status/ios-ux.md`. Not locally compiled (no Xcode
here) — flag the compile lane to `Features/Coffees/CoffeeEditSheet.swift`
first if the next check goes red; the `Profile?`-tagged `Picker` and the
`VocabEntry` `Identifiable` wrapper (added to dodge tuple-keypath ambiguity
in `ForEach`) are the two least-proven-by-precedent pieces in this file.

**📱 2026-08-11 (ios-shell lane) — #41 is DONE.** Edit API surface (PLAN.md
§12): `APIClient.editCoffeeField(publicId:field:value:)` (same raw-string-in
shape as `resolveReview` — checked `resolveField.js`'s `canonicalize()`,
every field runs the raw value through a string parser, no structured shape
to bridge); `MutationOutbox` gets a fourth `PendingMutation` case (`.edit`,
one outstanding edit per `(coffeeId, field)`, falls into the existing
4xx-drops/5xx-retries split); `SyncEngine.editField` queues + flushes like
`setFavorite` then re-fetches detail on success (unlike a favorite bool, an
edit's backend-derived side effects — e.g. `roaster` deriving
`roasterCountryId` — can't be guessed at locally); `CoffeeStore.editField`
merges the refreshed `Coffee` into `index`. `SampleCoffeeRepository`'s is a
no-op, same reasoning as its `resolveReview`/`dismissReview` no-ops. Landed on
`ios-staging`, not `main` (this lane never pushes `ios/**` to `main` — see
`status/ios-shell.md` for full detail). **`#42` (ios-ux) flipped
`blocked`→`ready`** in the same push; it also needed `#40`, already done.
Not locally compiled (no Xcode here) — a red compile check should point at a
typo, not a design gap, since every piece mirrors an existing shape.

**🛠️ 2026-08-11 (backend lane) — #40 is DONE.** Generic per-field edit endpoint
(PLAN.md §12): `POST /api/coffees/:publicId/edit`, single or batch. Reuses
#35/#36's locked-resolution + get-or-create machinery via a new shared
`src/lib/resolveField.js` (also now used by `routes/review.js`, refactored
per the issue's own ask). Added the `roaster_country_id` direct-edit case the
row called out, and fixed a real bug it exposed: batching a `roaster` edit
with a `roasterCountry` edit in the same call used to emit two SET clauses
for the same column (Postgres error) — `buildCoffeeColumnUpdates` now dedupes
by column. Full verification detail (curl-driven, against a real local
Postgres, including the batch-edit-wins-over-derived-value proof) in
`status/backend.md`. **`#41`(ios-shell) flipped `blocked`→`ready`** in the
same push; `#42` (ios-ux) stays `blocked` — it also needs `#41`.

**🌍 2026-08-10 (data lane) — #38 is DONE, and its own premise was wrong.**
The row said to seed `roasters.country_id` "from the product brief" — verified
directly against the docx's `word/document.xml` that it holds no such pairing
at all (just a flat roaster-name list and two flat, already-known-swapped
country tallies). Sourced live via web search per roaster instead of guessing
from names; caught the row's own example ("Concept Coffee Roasters→Romania")
being wrong (it's Slovakia) in the process. 80/89 roasters now have a country;
9 left `NULL` on purpose per Radu's "guess only very close matches" brief line
rather than pattern-matched. Full table + verification in `status/data.md`.
No other `data` row was `ready` this cycle (`#26` still `human`, `#29` still
blocked on it) — nothing else picked up.

**🧭 2026-08-08 (Radu directive) — accept-by-default; review is optional, not a gate.**
After using the live builds Radu was explicit: the extractor's picks are
essentially always right ("69.00 lei in text → 69.00 lei picked = definitely
correct; haven't found a single miss"). He wants to **push identified info and
correct the rare mistakes**, not review everything. New backlog rows **#35–#37**
carry this out; full design is **PLAN.md §11**. #35 (accept-by-default
adjudication) is the headline and is $0 to iterate — re-adjudication runs over
stored `field_candidates`, no new LLM spend — so tune it against the existing
corpus. Two concrete bugs feed the same theme: (a) **reviewing a farm name does
nothing** because 0 farms are seeded and the resolve endpoint 422s (→ #36,
get-or-create on accept); (b) **most "needs review" coffees open an empty review
sheet** because their open items are non-reviewable fields (→ #35 removes those
rows at the source; #37 is the client belt-and-braces).

**📦 2026-08-08 — a batch of UI/review fixes is already on `main`, awaiting the Publish lane.**
Do **not** re-implement these; they're landed (`main` `9bb27d6..2b3b0e1`) and
compile-green, just not yet dispatched `publish=true`:
real review feed wired to `GET/POST /api/review` (backend enrich: signed
`thumbUrl` + raw text + field mapping + candidate cleaning; canonicalizing,
corruption-safe resolve); full source text on the coffee page + review card
(now a collapsible section, expanded by default); listing thumbnails carried in
the snapshot (`SNAPSHOT_VERSION=2`, survives re-sync); per-coffee review sheet
from the "needs review" marker; single back arrow + removed the overlapping
inline thumbnail on the coffee page; review card swipe→buttons + Back (was
dismissing on scroll); **multiple origins shown for blends**; and the
**vertical-wrapped process-tag** fix (`lineLimit(1)` + `fixedSize`). Radu asked
**not to manually publish** — the Publish lane ships `main` on its Thu/Sun cron.

**🔀 2026-08-04 (ios-shell lane, merging `main` into `ios-staging`) — reconciled a
second branch-divergence, same shape as the `#27` one below.** `ios-staging` had
`#22`/`#27`/`#28` (iOS) done but only knew `main`'s older state for `#25`/`#26`
(showed `ready`/`blocked`); `main` had `#25` done and `#26` promoted to `human`
(Radu's 5-photo verdict pending) but only knew `#22` as `ready` and `#27`/`#28` as
`blocked` (ios-staging doesn't push to `main`, so `main` never saw the iOS lane's
work land). The table above now reflects both halves: `22/25/27/28` done, `26`
human. No new code in this reconciliation — same "each branch is stale about the
other's lane" pattern `status/README.md` calls out, not a regression.

**🟢 2026-08-04 (ios-ux lane, later same session) — `#27` is DONE.** Review
queue built in full against a local sample fixture (`ReviewSampleData`):
batch-card collapsing at the ≥8 threshold, per-coffee singles ordered by
fewest-open-fields-first, all five gestures (tap/long-press/swipe
right/left/down), a 20-deep undo stack with a 5 s toast, and an "Other…"
free-text fallback. **One real gap, flagged rather than guessed around** (see
`status/ios-ux.md`): the real `GET /api/review` / `POST /api/review/:id` /
`POST /api/review/rules` feed has no `CoffeeStore`/`APIClient` surface yet —
same class of gap as #28's flagged `loadBrief()` — so every action today only
mutates local state, nothing round-trips through the mutation outbox. Claimed
in both `status/ios-ux.md` and `status/ios-shell.md` per the seam rule in
`status/README.md`.

**🟢 2026-08-04 (ios-ux lane, merging `main` into `ios-staging`) — `#27` flipped `blocked`→`ready`.**
Each branch only knew half the picture: `ios-staging` had `#22` (ios-shell) done
but still carried a stale `blocked` for backend's `#23`/`#24`/`#25`; `main` had
`#23`/`#24` done but still showed `#22` as merely `ready` (ios-shell doesn't push
to `main`, so `main` never saw it land). `#27`'s `needs` are `22, 24` — both are
in fact done once the two branches are reconciled — so this merge is what
surfaces `#27` as this lane's next row, not new work by either lane individually.

**#22 is DONE (2026-08-01, ios-shell session)** — `RemoteCoffeeRepository` +
`SyncEngine` + `MutationOutbox` + `ImageStore` land, delta-syncing
`/api/snapshot` and persisting to disk; `CoffeeStore`'s default repository is
now the real one, not `SampleCoffeeRepository`. Full detail + two real
wire-format bugs found and fixed (`Country`'s `iso2`/`kind` columns vs.
`isoCode`/`isPseudo`; Postgres `NUMERIC` columns arriving as JSON strings, not
bare numbers) in `status/ios-shell.md`. Unblocks **#28** (ios-ux), flipped
`blocked`→`ready` above; **#27** stayed `blocked` at the time (still needed
`#24`, which was only `blocked` on `main` as of this ios-shell session — see
the 2026-08-04 note at the top of this section for the merge that resolved it).

Two follow-ups flagged, not done in this session because they're outside
`ios-shell`'s owned paths or backend-owned:
- **iOS UX**: `DesignSystem/Thumbnail.swift` still uses a plain `AsyncImage`,
  not the new `ImageStore`; and no view calls the new
  `CoffeeStore.toggleFavorite(_:)` / `.loadDetail(for:)` yet — the heart icon
  in `CoffeeRowView.swift` has no tap gesture, and `CoffeeDetailView.swift`
  never fetches the detail payload that carries real notes/images (the
  compact snapshot doesn't). Both store methods exist and are ready to call.
  **Resolved** in the 2026-08-02 ios-ux session below (`Thumbnail.swift` now
  uses `ImageStore`, the heart has a tap target, detail fetches on appear).
- **Backend**: the compact snapshot has no per-row image URL, so bulk
  thumbnail prefetch (PLAN.md §5) has nothing to prefetch from yet — a batch
  media-URL endpoint doesn't exist. `ImageStore` is built and ready once one
  does; not guessing its shape here, same as the backend lane's own note
  below about this exact gap.

**✅ 2026-08-04 (authorized session) — `claude/peaceful-mccarthy-kix48i` is MERGED.**
The stranded #25 work below is now on `main` (clean fast-forward, `npm test`
180/180 re-verified post-merge). `#25`→`done`, `#26`→`ready`. Radu explicitly
authorized the 5-photo LLM sample (spend-gate step 2), so the Phase-0 rules pass
($0) and then the 5-photo sample are being run against the real 28 photos in this
session. The "needs an authorized session to merge" ask below is now SATISFIED —
don't act on it again.

**🟡 2026-08-04 (data lane) — #25's code is done, but not yet on `main`.**
`backend/src/lib/deterministic.js` (the P3 "rules" voter) + tests landed and
were verified end-to-end against a real local Postgres 16 — see
`status/data.md` for the full writeup, including a real bug this pass found
and fixed (`parsePrice`/`parseRating`'s bare-number fallback grabbing an
unrelated digit — a date, an altitude — out of free text when nothing else in
the caption looked like a price or rating). **Left `#25` at `claimed`, not
`done`** — this session's `git push` is restricted to its own branch
(`claude/peaceful-mccarthy-kix48i`), which is not `main` (`origin/main` is
still `0ad0023`, from 2026-07-29, well behind even this file's own account of
what's landed). Per `status/README.md`'s "done means on the shared branch"
rule, `#25` can't be marked `done` and `#26` can't unblock until an authorized
session merges `claude/peaceful-mccarthy-kix48i` into `main` — the same
structural gap `status/data.md`'s 2026-08-01 correction already documented for
`rwi2ql`. **Nothing has been run against production**: the live Railway
backend's `/api/admin/jobs` is empty and `GET /api/coffees` reports
`total: 0` — the worker has genuinely never touched the 28 real photos #20
uploaded, so the actual Phase 0 pass over real data — and any LLM spend under
#26 — waits on this merge. Whoever can push to `main`: fast-forward/merge
`claude/peaceful-mccarthy-kix48i`, confirm `npm test` (180/180) and the
Railway deploy, then flip `#25`'s row to `done` and `#26` to `ready`.

**🟢 2026-08-04 (later same day, backend lane) — #24 is DONE.** Migrations
`010_extractions`/`011_resolutions` + `src/lib/adjudicate.js` (pure
deterministic adjudication) + `src/lib/agents.js` (the 4 LLM voters) +
`src/lib/worker.js` (the SIGTERM-safe claim-with-lease loop) +
`routes/review.js` + `routes/admin.js` all landed on `main`, verified
end-to-end against a real local Postgres using fake no-network voters (no
live Vertex spend -- that stays gated behind the data lane's spend protocol
below). See `status/backend.md` for full detail, including the one deliberate
scope gap (the "provisional pass while still awaiting_text" nuance from
PLAN.md §3 isn't implemented yet -- only `text_received`/deadline-passed
photos are claimed). **`#25` (data) flipped `blocked`→`ready`** — its own gate
(Radu's spend protocol below) still applies before any real LLM run.
P3 (rules) is intentionally absent: `agents.js`'s `loadRulesVoter()` dynamically
imports the data lane's `src/lib/deterministic.js` and simply runs without it
if that file doesn't exist yet, so `#25` can add it without any backend-side
coordination -- the only contract is a `{agent:'rules', provider:'rules',
run(ctx) => Promise<{fields, usage, costUsd}>}` voter object.

**🟢 2026-08-04 — the on-Mac §8 photo gate has RUN AND PASSED (Radu, real Mac).**
The exporter ran against the real "coffees" Photos album: 28 originals uploaded to
`POST /api/photos/manifest` + `PUT /api/photos/:sourceId/image`, and a second run
returned `0 need an image upload` (dedupe verified). This is the gate the backend
lane had been holding `#23`/`#24` on ("blocked on purpose per §8"). **That block is
now lifted: `#23` flipped `blocked`→`ready`.** Backend lane: `#23` (extend
`vertex.js`) is your next row; finishing it unblocks `#24` (worker/agents), which
unblocks `#25` (the first extraction pass — which has its own 5-photo spend gate in
`#26` before any real spend). More photos keep arriving as Radu's iCloud originals
finish downloading and he re-runs the exporter (idempotent).

**#20 is DONE** (2026-08-02, data lane session) — `ops/mycoffee_export.py`, the
two-phase Mac exporter + uploader against `POST /api/photos/manifest` +
`PUT /api/photos/:sourceId/image` (`routes/photos.js`, #19). Structured so the
pure logic (manifest-entry shaping, ≤200-entry batching, an on-disk
`(size, mtime)` state cache that skips re-`sips`-converting unchanged photos,
HTTP retry/backoff that never retries a 4xx) is unit-tested without macOS —
`ops/test_mycoffee_export.py`, 29/29 green — and only the Photos-library read
(`osxphotos`) and HEIC→JPEG conversion (`sips`) are macOS-specific, isolated
behind lazy imports so the test run needs neither installed. Full detail,
including the `contentSha256`-must-equal-the-uploaded-bytes trap and why
`caption` is always sent `null`, is in `ops/README.md`.

**Not done, and can't be from this sandbox:** the actual on-Mac verification
gate PLAN.md §8 asks for — run against Radu's real "Coffees" album with
`--limit 20`, confirm derivatives + dedupe-on-rerun. This session has no
macOS runner and no access to the real Photos library; `ops/README.md` has a
checklist ready for whoever runs it. `#25` (needs 20, 24) stays `blocked` —
`#24` is still blocked upstream, so nothing newly unblocks this session.

**✅ 2026-08-01 (Backend lane session): the `claude/peaceful-mccarthy-rwi2ql`
merge described in the warning below is DONE — this is real `origin/main` now.**
The prior backend session that wrote the warning had validated the branch
(86/86 tests) but had its direct push to `main` blocked by its own session's
permission classifier. This session re-verified the same result, merged it
(`git merge --no-ff` then `git pull --rebase` linearized it onto `main` as
three commits, no conflicts — `main` had only moved by two backend audit-note
commits since), reran the suite (still 86/86), and pushed. `git rev-parse
main origin/main` now agree and both contain #12/#13/#14/#34's real code —
confirmed via `git show origin/main:backend/src/lib/vocab.js`. No human
action was needed after all; the earlier session's blocker was specific to
that session, not a structural one. The stale "needs a human" framing in
`status/data.md`'s matching note is now historical, not current — don't act
on it.

**#21 (this session, backend) is also DONE**, built on top of the now-real
`#14`: migrations `008_coffees`/`009_search` + `GET /api/snapshot`,
`GET /api/snapshot/text`, `GET /api/coffees`, `GET /api/coffees/:publicId`,
`GET /api/coffees/top-filters`, `POST /api/coffees/:publicId/favorite`. Ran
the full migration chain against a real local Postgres (all 9 files applied
cleanly, generated columns compute correctly — spot-checked `purchased_year`/
`altitude_mid_m`/`price_per_100g_eur`/`is_blend` against a hand-inserted row),
then exercised every new route end-to-end over `app.inject()` against that
same DB (not just the auth-guard smoke tests in `test/coffees.test.js`) —
snapshot, detail, list, top-filters, and the favorite write all returned the
expected shape. 93/93 `npm test` green. Unblocks **#22** (ios-shell), flipped
`blocked`→`ready` in the same commit.

Two scope notes for whoever picks up #22/#28 next: (1) the compact snapshot
row deliberately omits a signed thumbnail URL to stay near the ~140 B/row
budget (PLAN.md §4) — only `GET /api/coffees/:publicId` returns
`thumbUrl`/`displayUrl` today, so bulk thumbnail prefetch (PLAN.md §5's
"prefetch them all over Wi-Fi via the BGTask") needs a batch media-URL
endpoint that isn't in the PLAN.md §4 list yet; flagging rather than guessing
its shape. (2) `GET /api/coffees/top-filters` implements the origin-country
card type exactly as PLAN.md §6.1 specifies (gated count≥5 and <total, top 4
by count-rated-≥4.0, tie-broken by name) plus the two pinned cards and the
single top "interesting" process card — that's everything §6.1 specifies
today; it returns real counts (0 for everything on the still-empty table,
verified live) and will start returning non-trivial cards once #20/#25/#26
land real coffee rows.

**#14's lane tag corrected `backend` → `data`** (2026-07-31 Backend lane session).
The original GitHub issue #14 body says "Lane: backend" (it predates the lane
split), and this row still carried that tag. But `CLAUDE.md` §4, `status/README.md`
§Lanes, and `PLAN.md` §7 — all written after the issue and all more current —
agree `backend/src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` is a
single glob owned by **Data**, not Backend; `fx.js` (also originally in #14's
"backend" scope) already landed under Data's #34 for the same reason
(`status/data.md`). Backend's own claimed ownership this session explicitly
excludes `src/lib/vocab.js`. Leaving the row tagged `backend` would repeat the
exact stale-note failure mode `status/README.md` documents for #33: a lane
executing a note faithfully instead of the current ownership table. Corrected the
tag rather than writing the file out-of-lane. **This was the only `ready` row
tagged `backend` this cycle** — with it reassigned, the Backend lane found no
in-scope work and is stopping cleanly (no invented work). Next `ready` row for
Data is `#20` (already was), now also `#14`.

**Data lane #12/#13/#34 are DONE and consolidated onto `main`** (2026-07-31) — they
had been done three times over on separate fired-session branches that never merged,
so `main` never advanced and each new session redid them. Rebuilt cleanly and
Postgres-validated (59/59 tests). See `status/data.md` and the "un-integrated prior
work" rule in `status/README.md` — **check for stranded lane branches before starting
new work.**

**#14 is now DONE** (2026-08-01 data lane session) — `src/lib/vocab.js` + 24 tests,
86/86 green. See `status/data.md` for detail. Unblocked **#21** (backend, needs
11+14 — both done now), flipped `blocked`→`ready` in the same commit.

Ready rows now:
- **#20** (data) — `ops/` Mac exporter + uploader (unblocked by #19 already).
- **#22** (ios-shell) — Remote repository + SyncEngine + ImageStore + MutationOutbox,
  newly unblocked now that #21 is done (see the top of this section).

**iOS #17 + #18 are DONE, merged to `main`, and compile-green** (run #18 on `29c1def`,
2026-07-31). `ios-staging` was merged here after its first-ever compile check passed;
the compile lane fixed two first-build Swift errors (`ProcessTag` dot-shorthand,
`CoffeeDetailView` optional-chain `flatMap`) beforehand. Detail lives in
`status/ios-ux.md` / `status/ios-shell.md` (the one-line `ContentView.swift` swap; the
`Hashable` conformances on `Profile`/`SortOption` now declared at origin; the
`Id`/`Eur` acronym-casing convention that matches `.convertFromSnakeCase`). Remaining
iOS work (#22, #27, #28) stays blocked on backend #21/#24. **Publish to TestFlight is
still a separate explicit `publish=true` dispatch — the publish lane's call, not done
here.**

**#11, #15, #16, #19 are done** (backend). Migrations 003/004/006
landed (extensions, vocab tables incl. a fixed `profiles` seed + the `Blend`
pseudo-country, and the `fx_rates` table structure); `railway-deploy.yml` now
gates `deploy` on a `test` job; `GET /api/brief` moved to `requireAnyToken` and
`GET /api/config` shipped; migration 007 (`photos`/`photo_texts`/`assets`) plus
`src/media.js` + `routes/photos.js` + `routes/media.js` landed and were verified
end-to-end against a local Postgres + real JPEG (manifest upsert, dedupe on a
re-run, sha256-mismatch rejection, duplicate-content-hash handling, signed
`/media` URLs). That unblocks **#20**.

**Two P0 gaps found by live smoke test, now owned:**

- **#33 — DONE.** Cause was a newline captured into the env var *name*: the process
  received both `"GOOGLE_PRIVATE_KEY"` (empty) and `"GOOGLE_PRIVATE_KEY
"` (the real
  2,391-byte key). Railway's UI renders these identically **and collapses the rows** —
  it showed 8 variables while the container had 9 — so it was invisible from the
  console, and no redeploy could help. Fixed in code (`0b38388`): `config.js` resolves
  by exact name, falling back to a trimmed-name match. `/api/status` now reports
  `vertex:true`. The earlier `e238f10` lane fix is correct and stays; it addressed a
  different credential shape.
- **#34 — `fx_rates` has structure but no rows.** Now owned, sourced from
  Frankfurter (ECB, no API key). `#14` depends on it. Watch the direction:
  Frankfurter returns EUR→X but the column is `rate_to_eur`, so invert.

**Environment note:** `mycoffee-production-bd43.up.railway.app` is allowlisted, so
lanes can now verify live — `/health`, `/api/status`, `/api/config` and
`/api/brief` were all confirmed green from a session.

**The product brief lives in the OTHER repo.** `Climb-Again/mycoffee-private` is
attached to every lane routine as a second source; the brief is
`brief/MyCoffee app.docx` on its `main`. That is the **authoritative source for the
roaster and country vocabularies** (#12) — `PLAN.md` carries the analysis and the
alias pairs but *not* all ~105 roaster names verbatim, so seeding from `PLAN.md`
alone would produce a silently incomplete vocabulary. Extract it with
`unzip` + parse `word/document.xml` (`<w:p>` paragraphs, `<w:t>` runs); note that
many entries split the name and its `(count)` across **adjacent paragraphs**, so
pair them when parsing.

**Never copy the docx or any personally-identifying excerpt into this public repo.**
Extracted vocabulary *values* are the deliverable; the document is not. It was moved
out precisely because it holds ten years of personal purchase history and
screenshots containing a profile avatar.

**Frankfurter is reachable and verified (#34 unblocked).** Both
`api.frankfurter.app` and `api.frankfurter.dev` are allowlisted. `.app`
301-redirects to `.dev/v1/…`, so **follow redirects** (`curl -L` / `fetch` default)
or call `.dev` directly.

Working request shape, confirmed against a live response — do not guess the params:

```
GET https://api.frankfurter.dev/v1/2015-01-01..2015-01-31?base=EUR&symbols=RON
→ {"amount":1.0,"base":"EUR","start_date":…,"end_date":…,"rates":{"2015-01-02":{"RON":4.4761}, …}}
```

Note it is **`base` + `symbols`** (not `from`/`to`), the path is `/v1/`-prefixed, and
`rates` is keyed by date with a nested currency object. Only ECB business days are
present — expect ~21–22 observations per month, which is the correct set to average.

**Verified inversion anchors.** Frankfurter returns EUR→X; `fx_rates.rate_to_eur`
is "1 unit of quote = N EUR", so invert. Real values:

| Month | EUR→RON | `rate_to_eur` |
|---|---|---|
| 2015-01 | 4.4872 | **0.222856** |
| 2019-06 | 4.7259 | 0.211602 |
| 2024-06 | 4.9767 | **0.200935** |

If a 2015 RON row comes out near `4.49` instead of `0.22`, the direction is
backwards and every RON price will be ~24× too large. Use these three as the test
fixture. RON drifted 4.49 → 5.23 (~17%) across the corpus window, which is exactly
why the rate must be dated rather than flat.

**#9 is done** — a valid placeholder AppIcon landed on `main` (`c427f3f`), verified
1024×1024, RGB, no alpha. That unblocks **#10**, which is now the next thing to do
and is `human` on purpose: the first `match` run has to create a distribution
certificate under `PH2NNQ47UB` where none exists, and it is the riskiest step in
the project. Run it by hand, on the current placeholder app, while a red ship is
cheap to diagnose. The Compile and Publish routines stay disabled until it passes.

## Spend gates (data lane)

Radu's explicit instruction, in order:
1. Deterministic rules pass over the corpus — **free**, run freely.
2. **5 photos only** (~$0.35) → **stop and report every extracted field** so Radu
   can judge accuracy himself.
3. Only after he approves: 25-record tuning run, then re-adjudicate for $0 until
   thresholds settle.
4. **Never launch the full ~$62 backfill autonomously.** Prepare, set
   `EXTRACTION_MAX_SPEND_USD=80`, then ask.

Confirm current Vertex per-token rates before any LLM run — the figures in
`PLAN.md` §2 are estimates, and Gemini 2.5's thinking tokens dominate output cost.
