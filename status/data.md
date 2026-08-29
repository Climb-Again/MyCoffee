# Lane: Data extract + validate

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

> **Older entries are in [`archive/data-history.md`](archive/data-history.md)** (#92). This file keeps live claims and the last two weeks of real work; pure "no ready row" session-check notes were archived regardless of date — the 2026-08-27 audit found they were 44% of all commits.

## Starting the daily extraction batch (2026-08-15)

**Start a batch with `bash ops/start-extraction-batch.sh`, not a raw curl.** An
unattended (fired) CCR session's auto-mode permission classifier denies an ad-hoc
money-spending `POST /api/admin/jobs`, so the daily routine silently didn't run
(Radu flagged it 2026-08-15; live check showed no job started that day, last job
was #12). The script is the *named* command allowlisted in `.claude/settings.json`
(`permissions.allow`), which an ad-hoc POST can't be. It refuses to start if a job
is already `running` (exit 3), stays text-only (`includeImages=false`), reads
`$INGEST_TOKEN` from the env (never prints it), and honours `BATCH_LIMIT` /
`BATCH_SPEND_CAP_USD` / `BATCH_VOTER_SET` overrides (defaults 50 / 8 / full). The
daily routine (`trig_01JWhQADZK8RqfP8r9ugXen1`) now calls it. If the classifier
still blocks it on the next fired run, the fallback is a manual "run it" from Radu.

## Claimed

_none_

## 2026-08-17 — #29 closed out: all three sub-parts already resolved, no data-owned code change needed; #69 filed (backend) for the one real residual gap; #67's lane tag corrected to `backend`

Picked `#29` (phase 6, needs `26` — done) over `#67` (phase 6, needs `—`) per the
lowest-phase-then-lowest-number rule. `main`/`origin/main` agree (`git ls-remote
origin main` matches this session's own `HEAD` exactly — the local
`origin/main` ref was just a stale shallow-clone cache showing an older sha;
no fast-forward needed, nothing stranded). `cd backend && npm test` —
249/249 green (unchanged; this session touches no code).

**Row #29's ask, PLAN.md §8 phase 6**: "harden the incremental path: `launchd`
monthly schedule on the Mac, the `awaiting_text` deadline sweep, and `POST
/api/admin/sync` on a backend cron." Went through all three pieces rather than
assuming the row was stale busywork; none needed a change in a data-owned path
(`ops/**`, `005_vocab_seed.sql`, `src/lib/{normalize,fuzzy,vocab,fx,
deterministic,prompts}.js`):

1. **`launchd` monthly on the Mac** — the row's own note already calls this
   "effectively covered by the CCR daily-extraction routine," and literally
   installing a `launchd` plist is a Mac-side system-service step this sandbox
   has no way to perform, same class as #20's own on-Mac gate. Nothing to add.

2. **`awaiting_text` deadline sweep** — already built and tested, just never
   credited to this row. `isDueForExtraction()`/`claimBatch()`
   (`backend/src/lib/worker.js`, backend-owned) implement PLAN.md §3 step 3
   exactly ("deadline passes, still no caption → full pass image-only"):
   `claimBatch`'s SQL predicate when `includeImages:true` is
   `(state = 'text_received' OR (state = 'awaiting_text' AND text_wait_until
   <= now()))`. The pure predicate has direct unit coverage
   (`test/worker.test.js`: `"isDueForExtraction: awaiting_text is due only
   once the 10-day deadline passes"`); the DB-touching half (`claimBatch`
   itself has no unit coverage — it's `FOR UPDATE SKIP LOCKED` SQL) was
   live-Postgres-verified in #64's own session: an `awaiting_text` photo
   seeded past its `text_wait_until` was correctly excluded in text-only mode
   and correctly claimed in image mode. It also already fires for real
   operationally: the standing daily OCR routine
   (`trig_017RR9aMaL8fpvqPZNAv8mn4`, `includeImages:true`) claims exactly
   this state on every run, alongside plain `text_received` photos — checked
   `GET /api/admin/jobs` live and confirmed it's been running daily (jobs
   16-23, 2026-08-16).

3. **`POST /api/admin/sync` on a backend cron** — never built as a literally
   named route, but superseded by how the system actually evolved rather than
   missing: the "backend cron" role is filled by two external CCR-scheduled
   triggers hitting the existing `POST /api/admin/jobs`
   (`trig_01JWhQADZK8RqfP8r9ugXen1` daily text-only,
   `trig_017RR9aMaL8fpvqPZNAv8mn4` daily image-OCR) instead of a
   Fastify-internal cron calling a dedicated sync route. `claimBatch`'s own
   query already re-derives "what's newly eligible" on every job start — the
   entire job a `/sync` endpoint would have done. Treating this as
   resolved-by-design, not outstanding.

**One real gap this pass surfaced, filed as `#69` (backend) instead of patched
here**: `#65` documents the daily OCR routine as *self-deleting* once a run
finds zero image-only photos left — correct for draining today's backlog, but
it means the ongoing per-photo deadline sweep (point 2 above) stops firing
entirely once that happens, for any *future* photo that lands in
`awaiting_text` and later goes 10 days with no caption. The standing
text-only routine can't safely take over that job: its `includeImages` is a
whole-job flag, not per-photo, so flipping it to `true` would also send every
plain `text_received` photo's image to Gemini for no reason — directly
against Radu's "keep the daily routine text-only, keep it cheap" instruction
(this file's 2026-08-15 note; `ops/start-extraction-batch.sh`'s own comment,
"MUST stay false — text-only"). A real fix needs per-photo image-inclusion
inside `claimBatch`/`runWorker` (claim `text_received` photos text-only but
still OCR the *specific* overdue `awaiting_text` rows in the same pass) —
that's `backend/src/lib/worker.js` + `routes/admin.js`, entirely outside
every data-owned path, so filed rather than guessed at here. Not urgent:
today's existing backlog is fully covered by the current OCR routine; this is
a latent risk for the steady state *after* that routine finishes draining and
deletes itself, not an active bug today.

**`#67`'s lane tag corrected `data` → `backend`.** Its own body names only
`src/routes/admin.js` and `src/lib/worker.js` as the files to touch — both
backend-owned; nothing in `ops/**` or a data-owned `src/lib/*` file. Unlike
`#48(b)`→`#51`, where a real data-ownable half existed and shipped, there's no
data-lane sliver to peel off `#67` — the whole thing is one backend-owned
admin endpoint. Re-tagged so a data-lane session doesn't keep reading past it
as "its own `ready` row" for a lane that structurally can't implement any of
it; a backend session can now pick it up cleanly. No code touched by this
correction, just the row's own `Lane` column and a note
(`status/README.md`'s "correcting a task means correcting THIS file" — the
same kind of premise-correction #38 and #48 did for their own rows).

No `ops/**` / `005_vocab_seed.sql` / data-owned `src/lib/*` file changed this
session — this was entirely a verification-and-bookkeeping pass, closing out
work that (per points 1-3 above) was already done, plus filing/correcting two
rows so the next lane sees an accurate backlog. — branch `main`, this commit.

## 2026-08-15 — #48(b) is DONE: caption-city roaster-country override

**Integration note first:** this session's assigned branch
(`claude/peaceful-mccarthy-6n4yw7`) was 57 commits ahead of `origin/main` —
every lane (backend, ios-shell, ios-ux, data) had been pushing to this same
branch across many prior firings without it ever landing on `main`, the
identical "stranded branch" failure mode CLAUDE.md §12 documents, just with
one shared branch name instead of several. `origin/main` was a strict
ancestor (clean fast-forward, `git rev-list --count branch..main` = 0), so
fast-forwarded `main` to the branch tip and pushed — `origin/main` now
matches what `BACKLOG.md` already described as done (through #49). Backend
`npm test` re-verified 238/238 green on that merged state before doing any
new work, and confirmed via `GET /api/admin/jobs` that no extraction job was
`running` before the push (CLAUDE.md's hard interlock).

**The work itself:** `#48`'s row had one part left — "(b) durable rule: when
a caption explicitly states the roaster's city/country, prefer that for
`roaster_country_id` over the derived vocab country." Added
`extractRoasterCountryOverride(rawText, countryVocab)` to
`src/lib/deterministic.js`, right next to `extractOriginCountriesField` since
it's the same shape of problem: reuses `findAliasMentions` (the existing
diacritic-folded, word-boundary alias scan already built for the roaster/
origin voter fields), filtered to `is_roaster` countries so an origin mention
("Etiopia" describing the beans) can never be misread as the roaster's
location, and returns `null` (decline, keep whatever the caller already has)
when zero or more than one distinct roaster-country is mentioned — the same
"ambiguous never auto-resolves" rule `resolveCityCountry` already applies to
cities.

**The alias gap this surfaced:** Radu's captions are Romanian
("Prăjitorie: Uncommon (Amsterdam, Olanda)"), but `005_vocab_seed.sql` only
ever seeded English country names/aliases for roaster countries — so the
override could recognise "Netherlands" in a caption but never "Olanda", the
actual spelling in the one caption that motivated this whole row. Added
`backend/migrations/020_add_romanian_roaster_country_aliases.sql`, seeding
Romanian names for the 20 existing roaster countries that don't already share
an identical spelling with English (skipped Canada/Austria/Slovenia/Romania —
same word in both languages): Belgia, Cehia, Danemarca, Franța, Germania,
Irlanda, Letonia, Olanda, Norvegia, Polonia, Slovacia, Spania, SUA/Statele
Unite, Marea Britanie/Anglia, Italia, Suedia, Finlanda, Coreea de Sud,
Elveția. Diacritics kept as typed in `alias_norm` (e.g. `franța`) — exact
`alias_norm` lookups (`resolveVocab`) don't fold them, but the new override
goes through `findAliasMentions`, which folds both sides before comparing, so
a diacritic-free caption spelling ("Franta") still matches; this is called
out in the migration's own header comment so it isn't rediscovered as a bug.

**Tests:** 7 new table-driven cases in `test/deterministic.test.js` (245/245
`npm test` green): the real Uncommon caption resolving to Netherlands; the
same caption with diacritics stripped (proves the fold-at-match-time design);
no country mention at all (declines); an origin-only mention ("Ethiopia")
correctly never read as a roaster location; two distinct roaster-countries in
one caption (ambiguous, declines); the same country via two different
aliases ("Netherlands" + "Olanda" both present — one distinct id, not
ambiguous); and `undefined` vocab passed (declines rather than throwing).

**Live verification, not just unit tests:** started a local Postgres 16,
applied the full migration chain 001→020 (all clean, 020 idempotent on a
second run), loaded the real seeded `countries`/`country_aliases` via
`loadCountryVocab`, and called
`extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)',
countryVocab)` against it directly — resolved to Netherlands (id 35), not
United Kingdom (id 41, the vocab's stale guess from #38) — proving the
override would have produced the correct answer on the exact caption that
prompted this backlog row. Dropped the test database afterward; did not
touch production Postgres (this feature has no live wiring yet — see below).

**Not done, filed as #51 (backend, ready) instead of guessed at:** the
override function exists and is tested, but nothing calls it yet.
`buildCoffeeColumnUpdates`'s `roaster_id` case (`src/lib/worker.js`) still
unconditionally does `set('roaster_country_id', roaster?.country_id ?? null)`
— wiring it up needs `rawText` threaded into the `ctx` object
`applyResolutionsToCoffee` builds (today just `{...sharedCtx, photoDate}`)
and a call to the new override before falling back to the vocab-derived
country. `worker.js` is backend-owned, not this lane's to edit — same split
as #39 (data, `normalize.js` sanity envelopes) → #49 (backend, the
`worker.js` fix those envelopes exposed a gap in). Until #51 lands, the edit
sheet (#42) still covers any individual miscoded roaster country per-coffee,
same as #48(a) noted.

## Abandoned

_none_
