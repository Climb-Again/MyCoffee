# MyCoffee — build plan

## Context

Radu has reviewed specialty coffees for ~10 years using iPhone Photos as the
database: photograph the bag → move it to a "Coffees" album → type details into
the photo's title/caption/description, usually 4–5 days later. That's roughly
**870–890 coffees** of semi-structured prose that can't be filtered, sorted,
searched, or reasoned about.

The goal is a private, single-user **Vivino-for-coffee**: extract that decade of
prose into a real schema, then ship an iOS app with Vivino's interaction model —
a filterable/sortable listing, a rich coffee page, roaster and origin-country
pages, and an insights page correlating rating against everything else.

The repo already has a **working but domain-empty** scaffold from
`NEW_APP_SETUP_BRIEF.md`: Fastify 5 on Railway with Postgres and a `/data`
volume, a SwiftUI/XcodeGen app that can connect and ping, fastlane + TestFlight
CI. What's missing is *all* of the coffee domain — no tables beyond a generic
`ingest_events` envelope, no models, no real UI.

Extraction accuracy is the make-or-break. The brief says it plainly: *"this is
critical, and it only happens once in the beginning so we need to make sure
accuracy is top."*

## Decisions

Confirmed with Radu:

| Fork | Decision |
|---|---|
| Backfill transport | **Mac export script** — reads the Coffees album locally, uploads in resumable batches |
| AI ensemble | **Vertex-only, 5 passes** — no new provider secrets |
| Controlled vocabularies | **The docx lists are authoritative** for roasters + countries; farms and roaster→city are derived from the data and approved in the review queue |
| Extraction budget | **Vertex-only + cost levers ≈ $62** — evidence strings only below 0.9 confidence, `thinkingBudget: 0` on the flash extractor, flash instead of pro for the critic pass |
| Going forward | **Monthly Mac script run only.** No in-app capture, no camera, no PhotoKit watcher. Radu keeps captioning in Photos exactly as now; the same exporter runs monthly under `launchd` |
| Honey / pulped natural | **Fold into Experimental**, with `"Honey"` preserved verbatim in `profile_detail` |
| Unknown process | **Allow `NULL` + an "Unknown" facet + a review item.** The brief's "guess only very close matches" wins over "ALL coffees allocated to one of these six" |

**The capture decision meaningfully shrinks the iOS build.** Dropped entirely:
in-app camera, `PhotosPicker` attach, on-device Vision OCR, the field-prefill
parser, the draft store and draft strip, the coffee editor, and the PhotoKit album
watcher — roughly **5–6 dev days and 7 source files**. Also dropped:
`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, and the half-day
PhotoKit-caption spike (no longer needed — nothing is built on PhotoKit).
The app becomes **read-and-review only**: browse, filter, favourite, correct.
The BGTask narrows to sync + outbox flush + review count + thumbnail top-up.

The trade accepted: the **4–5 day caption gap stays**, handled server-side by the
`awaiting_text` / `text_wait_until` state machine (§3), and the Mac stays a
permanent dependency for ingestion.

## Pushback on the brief

1. **The two country-list headings are swapped.** "Roasters Countries list" holds
   Ethiopia/Kenya/Colombia/Brazil — *origin* countries. "Origin Countries list"
   opens with Belgium/Czech Republic/Netherlands/Latvia — *roaster* countries.
   Fixed in the seed, not by heading.
2. **Every list appears twice — two exports, one a subset of the other.**

   | Export | Roasters | Roaster countries | Origin countries |
   |---|---|---|---|
   | **A** | 46 names / **258** | 16 / **258** | 22 / **297** |
   | **B** | 60 names / **867** | — | 29 / **891** |

   Each export is internally consistent (A: 258 = 258; B: 867 vs 891), so **A is
   an older partial export of the same album, not a sibling list**. Never sum
   them — that double-counts. Use B's distribution (`Columbia 314`,
   `Ethiopia 164`, `Brazilia 61`, `Costa Rica 45`) as the reconciliation target
   and A purely as an extra source of alias strings. **Gate 1 of the data lane is
   counting the actual album** — the doc cannot settle the true corpus size.
3. **"Roasting profile" conflates three axes.** Natural/Washed/Anaerobic/
   Co-fermented are green-coffee *processing* methods; Experimental is a
   catch-all; **Decaf is orthogonal** — a decaf can be washed. Model
   `is_decaf BOOLEAN` separately from `profile_id`; keep Radu's label in the UI.
4. **"ALL coffees allocated to one of these" contradicts "guess only very close
   matches".** Forcing a profile onto a bag that never states one *is* a guess,
   and since Washed is the modal class a lazy prior would mislabel a long tail
   and then poison every profile correlation on the Insights page. Allow
   `profile_id NULL` internally, show a synthetic "Unknown" facet, queue each for
   review. **Never let a model default to Washed.**
5. **Origin isn't single-valued.** The data contains `Blend (3)` and
   `Colombia / Brazilia (1)`. Hence `origin_country_ids SMALLINT[]` + `is_blend`.
6. **"Max 7 cards" but 8 are enumerated** (4.5★ + Anaerobic + Co-fermented +
   top-4 origins + Favourites). Card selection is server-driven so the mix is
   tunable without an app release; default keeps the brief's explicit "top 4
   origin countries".
7. **"You only get to [roaster/country] page by clicking the flag"** — but a
   coffee page has two flags, and the flag beside the roaster is a *country*
   flag. Interpretation: roaster **name** row → roaster page; roaster flag →
   roaster-country page; origin flag → origin-country page. Behind one feature
   flag so it's a one-line revert.
8. **Price-per-100g needs weight.** Show `—` when weight is unknown rather than
   guessing; exclude those rows from €/100g sorting and faceting, and surface
   the count in Insights → Data quality.
9. **Rating-vs-everything correlations will manufacture nonsense** at n≈900
   across ~15 dimensions — "Papua New Guinea (1)" will look like the best origin
   ever. Minimum sample sizes and effect sizes are mandatory (§6.4).
10. **The brief has no edit or delete story.** In a 10-year archive you *will*
    find mistakes. Edit-anything costs almost nothing once the mutation outbox
    exists — include it.
11. **A roaster page needs a logo and a blurb that don't exist in the data.**
    Deterministic monogram avatar + a `blurb` field seeded mostly empty; omit
    the section when empty rather than shipping an empty box.

## Pre-existing defects to fix first

Cheap, and two of them bite silently:

1. **`GET /api/brief` can never succeed from the app.** `APIClient.swift:39`
   sends the Keychain *ingest* token on every request; `routes/brief.js` uses
   `requireAppToken` → guaranteed 401. Fix: mount app-facing **reads** on the
   already-existing `requireAnyToken` (`auth.js:50`).
2. **The AppIcon is an empty slot** — `AppIcon.appiconset/Contents.json`
   declares a 1024×1024 entry with **no `filename`** and no PNG. This still
   *compiles*, so the compile check stays green and hides it, but App Store
   Connect rejects it at **processing** time — and `Fastfile:73` sets
   `skip_waiting_for_build_processing: true`, so CI goes green and the rejection
   arrives by email ~20 min later. Must land before the first publish.
   `AccentColor` is already caramel `#A5824C` to design against.
3. **`vertex.js` is dead code** and text-only — `generateContent()` is called
   from nowhere and hardcodes `parts: [{ text: prompt }]` (`vertex.js:114`).
   It's the one existing module that must change shape, not just grow.
4. **`Info.plist` declares `UIBackgroundModes` + `BGTaskSchedulerPermittedIdentifiers`
   (`ro.climbagain.mycoffee.refresh`) but no Swift code registers it**, so the
   entry is inert. Wire it to the sync job (§6.6). Drop `processing` from the
   plist — an unused background mode invites App Review questions.

Toolchain verified locally: Node v22.22.2, `npm test` = `node --test`, deps not
installed. A cheap Ubuntu backend CI job is trivially feasible — and there is
none today.

---

## 1. Data model

Postgres 16 on Railway; design needs ≥13. Files picked up by the existing
advisory-locked forward-only runner (`src/migrate.js`).

**Three immutability traps** — generated columns require IMMUTABLE expressions,
and all three of these are STABLE:
- `to_tsvector(text)` 1-arg → must write `to_tsvector('simple'::regconfig, …)`
- `unaccent(text)` → cannot appear in a generated column at all
- `timestamptz AT TIME ZONE 'Europe/Bucharest'` → cannot derive a local date

Consequence: the app writes `purchased_on DATE` and pre-folded search blobs
explicitly; only the tsvector is generated.

**Vocabulary** — canonical row + `*_aliases` table with a **unique `alias_norm`**
per kind, so a normalised string resolves to exactly one entity. Covers every
variant the brief exposes: `Columbia`→Colombia, `Etiopia`→Ethiopia,
`Brazilia`→Brazil, `Indonezia`, `Mexic`, `Thailanda`, `NIcaragua`, `DAK`≡`DAK
Coffee Roasters`, `Beansmith.s`≡`Beansmith's`, `RightSide`≡`Right Side`,
`Boo!`≡`BOO Modern Coffee`, `Candycane Coffee`≡`CandyCane`. Plus a `cities` table
(~40 rows) for the brief's Amsterdam→Netherlands inference, with an `ambiguous`
flag so "Cambridge" never auto-accepts. `countries` carries the ISO-3166 alpha-2
that drives flags, `is_origin`/`is_roaster` flags (a country can be both), and a
`kind='pseudo'` row for `Blend`.

**`photos` is the ingest unit; `coffees` is derived from it.** Three dedupe
identities with three different jobs:
- `(source, source_id)` — Photos library UUID, the **upsert key**; stable across
  exports, so re-running the exporter never duplicates.
- `content_sha256` — **change/duplicate detector**; a unique partial index
  catches the same bag re-imported under a new UUID, and a changed hash on an
  existing `source_id` means the photo was edited and derivatives must be rebuilt.
- `text_sha256` on a versioned `photo_texts` table — the **re-extraction
  trigger**, and how the 4–5 day caption gap is handled (§3).

**`coffees`** — `purchased_at`/`purchased_on` (+ generated year/month),
`roaster_id`, `roaster_country_id`, `origin_country_ids SMALLINT[]` (+ generated
`origin_country_id` for display, `is_blend`), `origin_farm_id`,
`altitude_min_m`/`max_m` (+ generated mid), `profile_id` (nullable),
`profile_detail`, `is_decaf`, `roasted_on`, `price_original_amount` +
`price_original_currency` + `price_eur` + `fx_rate` + `fx_rate_period`,
`weight_g`, generated `price_per_100g_eur`, `rating numeric(2,1)`, `is_favorite`
+ `favorite_set_by` (sticky when human), the three description parts, the
verbatim `raw_title`/`raw_caption`/`raw_description`, `review_state`, and
`min_field_confidence`.

`origin_country_ids` as an array rather than two FK columns because array
subscripting is IMMUTABLE (so the display value can be generated), `@>` is
GIN-indexable, and `unnest()` makes the origin facet a one-liner that correctly
counts a blend in *both* member countries. Cost: no referential integrity on
array members — enforce in `src/lib/vocab.js`.

**Text search uses `'simple'`, not `'english'`** — the corpus is multilingual
(Romanian captions, Czech/Dutch/Danish roaster copy) and English stemming would
mangle it. Diacritics are folded in JS before the blob is written, so
`to_tsvector` never needs `unaccent`. `setweight` + `||` are both IMMUTABLE, so
the weighted vector (labels `A`, prose `D`) is a legal generated column.

**Provenance** — this is what makes the accuracy requirement tractable:
- `extractions` — one row per *(photo, agent, exact input)*, holding the **raw**
  response, usage, and cost. Unique on `input_sha`.
- `field_candidates` — flattened per-field view for adjudication.
- `field_resolutions` — the decided value + confidence + agreement + voters, with
  **`locked BOOLEAN`** set when `decided_by = 'human'`.
- `review_items` — one row per **field**, not per record; partial-unique on open.

**`locked` is the single most important invariant in the pipeline.** Without it,
the monthly incremental run silently undoes Radu's review work.

**Indexes** — be honest with the implementer: at ~900 rows Postgres will
sequential-scan `coffees` in under a millisecond and ignore most of them. The
ones that earn their keep are GIN on `search_tsv` (ranked FTS), GIN on
`origin_country_ids` (containment), and trigram on vocab aliases (autocomplete
over ~500 strings). The btrees are documentation of intent. Don't add more.

**Migrations:** `003_extensions` (`pg_trgm`+`unaccent` in a `DO` block that
swallows `insufficient_privilege` — fuzzy matching lives in JS, so nothing
depends on them) · `004_vocab` · `005_vocab_seed` · `006_fx_rates` ·
`007_photos` · `008_coffees` · `009_search` · `010_extractions` ·
`011_resolutions` · `012_editorial` · `013_snapshot`.

## 2. Extraction: 5 voters, deterministic adjudication

| # | Voter | Model | Role |
|---|---|---|---|
| P1 | Extract-A | `gemini-2.5-pro`, temp 0.0 | whole-object, schema-constrained, "null unless present" |
| P2 | Extract-B | `gemini-2.5-flash`, temp 0.4, `thinkingBudget: 0` | same schema, **field-by-field checklist** framing so it fails differently |
| P3 | **Rules** | pure JS, no network | numbers, units, currency, vocab exact/alias. Free, deterministic, **better than any LLM here** |
| P4 | Critic | `gemini-2.5-flash`, temp 0.0 | sees image + text + all candidates; asked to **refute** each field and cite a span. Emits verdicts, never values |
| P5 | Reconciler | `gemini-2.5-pro`, temp 0.0 | sees everything + a top-k vocabulary shortlist; emits final value, per-field confidence, evidence span |

Prompt variation is real, not cosmetic: P1 is told *"the caption is
authoritative; use the bag image only to fill gaps"*; P5 is told *"read the bag
label first, then reconcile against the caption and report disagreements"*. The
vocabulary block is rendered in a different order per agent so ordering bias
doesn't correlate.

**Adjudication is a pure function over stored rows** (`src/lib/adjudicate.js`) —
the model never decides whether it was right:

1. **Canonicalise** to comparable forms (vocab → integer id; altitude →
   `{min,max,unit:'m'}`; money → cents + ISO currency; weight → grams).
2. **Cluster** with a field-specific `equal()` — altitude within ±50 m, price
   within €0.05, rating exact.
3. **Weight** voters per field class. **P3 carries 1.5× on every numeric and
   unit field**, and 0 on prose. This single rule is what stops `1.600` /
   `1,600` / `4,1` from being silently mangled.
4. **Decide** on the winning cluster's weight share `s` and mean confidence:
   unanimous (≥2 voters, min conf ≥0.75) → auto-accept · `s ≥ 0.60` → accept,
   flagged · split or `s < 0.60` → **review queue** · single voter → ×0.7.
5. **Threshold per field, never per record** (the brief asks for exactly this):
   `profile_id`, `price_eur`, `weight_g`, `rating` at **0.90**; roaster and
   countries 0.85; farm 0.80; altitude 0.75; `roasted_on` 0.70 (brief: "not very
   relevant"); prose 0 — never blocks. All in `config.js`, tunable without a
   migration.
6. **Prose is selected, not voted.** For the three description parts, agents
   return **character offsets into the raw text**, not rewritten prose.
   Adjudication takes the median boundary and slices. Lossless,
   non-hallucinatable, and disagreement is measurable (spread >80 chars →
   review).
7. **Human decisions are sticky** — `locked` fields are skipped by every later
   pass.

**"Guess only very close matches"**, made mechanical: a fuzzy vocab match
auto-accepts only when **all three** hold — normalised Levenshtein ≥0.90 *or*
trigram ≥0.55; a **unique** best candidate; margin over runner-up ≥0.15.
Outcomes: `Columbia→Colombia` accepts; `Kofio` vs `Kolibri` (0.43) does not;
`Father's Coffee Roastery` vs `Father Carpenter` (margin 0.04) does not — both
become review items rather than a silent mis-merge.

**Normalisers** (`src/lib/normalize.js` — pure, no DB, the highest-value test
surface in the plan). Number parsing must be resolved **by shape and by field**,
never by locale guessing:

| Input | → | Rule |
|---|---|---|
| `4.1` / `4,1` | `4.1` | single separator, 1 decimal digit |
| `1.600` / `1,600` | `1600` | separator with exactly 3 trailing digits |
| `1.600,50` | `1600.50` | `.` before `,` → `.` groups |
| `1.6` | **field-dependent** | altitude → `1600`; rating → `1.6` |

That last row is why **there must never be one shared number parser**. Then:
altitude (`"1300 to 1600 masl"`, `"1.600m"`, and the brief's own typo
`"1300 ro 1600"` → `{min:1300,max:1600}`; plausibility-gated 900–2200 at full
confidence; range span >800 m → review, since the brief says ranges are usually
<200 apart) · price (`lei`→RON, `Kč`→CZK, `€`→EUR; bare number → conf 0.5, below
threshold, never silent) · weight (`g`/`gr`/`grams`; snap to the brief's
`{100,200,250}` within ±3 g; reject a candidate whose neighbourhood contains an
altitude marker) · rating (`4.1/5`, `3,9/5`, `⭐️4.1`; bare number → 0.6) · dates
(**day-first** when ambiguous; reject a roast date after the photo) ·
city→country · farm≡producer (strip `finca`/`fazenda`/`producer`/`washing
station` into `farms.kind`, match the residual, so `"Producer: Diego Bermudez"`
and `"Finca El Paraiso — Diego Bermudez"` resolve to one row).

**`parseProfile(text) → {profileId, isDecaf, detail}`** maps aliases onto exactly
the brief's six and sets `is_decaf` independently: `lavado`/`spalat`/`fully
washed` → Washed · `natural`/`dry process`/`uscat` → Natural ·
`anaerobic`/`carbonic maceration`/`CM` → Anaerobic ·
`co-ferment`/`cofermented`/`infused` → Co-fermented ·
`yeast`/`thermal shock`/`lactic`/`double fermentation` → Experimental ·
**`honey`/`yellow honey`/`black honey`/`pulped natural` → Experimental** (per
Radu's ruling), always with the literal term kept in `profile_detail` so the
coffee page still says "Yellow Honey" · `decaf`/`swiss water`/`EA`/`CO2
process`/`fara cofeina` sets `is_decaf = true` and leaves the process to resolve
separately. **No match → `NULL`, an "Unknown" facet chip, and a review item.**
Never default to Washed, even though it's the modal class.

**Currency must be dated.** RON/EUR moved from ~4.42 (2015) to ~4.98 (2026) — a
flat rate misprices a 2015 purchase by ~11%, which is enough to corrupt every
price band and price correlation. Commit a `fx_rates` seed of monthly ECB
averages for RON, CZK, PLN, HUF, SEK, DKK, NOK, GBP, USD, CHF × ~132 months
(~1,320 rows, ~60 KB). **CZK matters as much as RON** — after un-swapping the
headings, Czech Republic is the largest roaster country. Store the applied rate
and period on the row so EUR is reproducible. A live FX API would only add a
failure mode inside the extraction hot path for data that is by definition
historical.

**Idempotency.** `input_sha = sha256(agent|provider|model|promptVersion|
imageSha|textSha|vocabVersion)`, unique on `extractions`. The worker's first
action is a lookup — a hit means "already paid for this exact question". Safe to
re-run from scratch at any point, including after a crash mid-record.

**Worker** (`src/lib/worker.js`), designed for a box that *will* be SIGTERM'd by
an unrelated backend deploy: in-process loop guarded by
`pg_try_advisory_lock(48201976)`; claim-with-lease via `FOR UPDATE SKIP LOCKED`
+ a 10-minute reaper (this is what recovers a crash); concurrency **2 records**
in flight to leave Vertex quota for MyHealthOS; backoff `[2,5,15,45,120]s`;
spend cap from summed `cost_usd` with `POST /api/admin/jobs/:id/pause` so Radu
can stop a runaway at 03:00 without a redeploy.

**Run the free voter first.** Phase 0: P3 over all ~900 captions — costs nothing,
needs no images. Cluster the unresolved roaster/farm/country strings and confirm
them through the review queue, *then* bump `vocab_version` and start the LLM
passes. The agents now get a dictionary covering Radu's actual vocabulary, which
raises the exact/alias hit rate and shrinks the queue. Doing it the other way
round burns tokens teaching models to guess at names you could have confirmed
for free.

**Every raw response is stored forever.** Adjudication reads only stored rows, so
**re-adjudicating all ~900 records with new thresholds costs $0 and ~2 seconds.**
This is the one decision that makes "accuracy is top" affordable to iterate on.

### Cost

Assumptions: system+rules ~900 tok, vocab block ~2,300 (collapsing to ~320
effective under prompt caching), schema ~600, per-record text ~400, Gemini image
at 2048 px = 3×2 tiles × 258 = ~1,550, JSON out ~1,100, thinking ~1,500 on pro
and 0 on flash. Rates **$1.25/$10 per MTok (2.5 Pro)** and **$0.30/$2.50
(2.5 Flash)** — my recollection; **confirm against the Vertex price sheet before
the run.**

| Voter | $/record | ×900 |
|---|---|---|
| P1 pro | ~$0.030 | ~$27 |
| P2 flash (no thinking) | ~$0.004 | ~$3 |
| P4 flash critic | ~$0.005 | ~$5 |
| P5 pro reconciler | ~$0.030 | ~$27 |
| P3 rules | $0 | $0 |
| **total** | **~$0.069** | **~$62** |

Levers already applied above (flash for the critic, no thinking on P2, evidence
strings only below 0.9 confidence) take this from ~$95 to **~$62**. Wall clock
~40 s/record gated by the pro calls; at concurrency 2, **~5 hours** — run
overnight, fully resumable, well inside the brief's "no hurry".

**The accuracy caveat stands and should be stated plainly:** all four LLM voters
share a tokeniser, a vision encoder, and a training distribution. When Gemini
misreads a stylised label they tend to misread it *the same way* — and
**unanimous-but-wrong is the one failure mode voting cannot detect**, because it
auto-accepts at high confidence and never reaches the queue. Mitigations in this
design: P3's 1.5× weight on exactly the fields LLMs are weakest at, mandatory
evidence spans (a field with no span is capped at 0.5), and **a mandatory
hand-check of 30 random auto-accepted records before trusting the corpus**. If
that spot-check looks bad, adding Claude is one env var and ~$65 — and because
every raw response is stored, the existing votes still count.

**Human review estimate:** if ~8% of required-field decisions land in the queue,
900 × 5 × 8% ≈ **400 decisions ≈ 40 minutes** with the batch cards in §6.5, plus
~10 minutes for the free Phase-0 vocabulary pass.

## 3. Ingestion

**Push back on "likely that is using shortcuts".** Shortcuts on macOS cannot
reliably read a Photos asset's Caption/Description field — it exposes name, date
and album, but not the description that holds most of Radu's data. Bending
Shortcuts into this would lose the highest-value text in the corpus.

**Use `osxphotos` on the Mac**, driven by a ~50-line script and scheduled with
`launchd`. It reads the Photos library directly and exposes exactly what's
needed: `uuid`, `date`, `title`, `description`, `keywords`, `favorite`. It's also
*more* secure than the alternative — the token lives in the macOS Keychain and
never leaves the Mac. Shortcuts stays only as an optional "sync now" button that
invokes the same script.

**Two-phase upload** — a cheap JSON manifest decides what's needed, then bytes
only for what's missing:

```
POST /api/photos/manifest       ≤200 entries: sourceId, contentSha256, capturedAt,
                                capturedOn, title, caption, description, favorite, …
→ per entry: { photoId, need: "image"|"none", textChanged, textVersion, state }

PUT  /api/photos/:sourceId/image?sha256=<hex>     raw image/jpeg body
→ 201 created | 200 { deduped: true } | 409 sha256_mismatch
```

Raw `PUT` rather than multipart keeps the client a one-line `curl`, puts the
dedupe identity in the URL, and makes it idempotent — the server writes to
`/data/tmp/<uuid>` then `rename()`s to the content-addressed path, so a retry is
a no-op. A cold run is 5 manifest calls + ~900 PUTs; a repeat run is 5 manifest
calls + **zero** PUTs. Needs a route-level rate-limit override
(`INGEST_RATE_LIMIT_MAX`, default 1200) since the global cap is 300/min.

**Send derivatives, not camera originals** — iCloud Photos *is* the archive of
record and is already backed up, and `source_id` makes any original
retrievable. Storing 900 HEICs buys nothing and costs 4× the space.

| Variant | Size | Purpose | ×900 |
|---|---|---|---|
| `ocr` | 2048 px, q85 | uploaded original-of-record; extraction input | ~540 MB |
| `display` | 1290 px, q82 | coffee-page hero (covers a 3× 430 pt screen) | ~210 MB |
| `thumb` | 320 px, q75, cover | listing row | ~25 MB |
| | | **total** | **~775 MB** |

~15% of a 5 GB volume. 2048 px is well above what OCR needs (bag text is large).
Derivatives are generated server-side with `sharp` so the server owns EXIF: read
`DateTimeOriginal` to cross-check `capturedAt`, honour orientation, then **strip
all EXIF** — GPS on a coffee-bag photo is Radu's home address. Fallback if
`sharp` won't build under Nixpacks: `osxphotos` emits all three sizes and we
accept three PUTs per photo.

**Serving images:** SwiftUI `AsyncImage` can't attach an `Authorization` header,
so token-guarded image URLs would force a custom loader. Instead
`GET /media/:publicId/:variant.jpg?exp=&sig=` with
`sig = HMAC(MEDIA_SIGNING_KEY, publicId|variant|exp)`, constant-time compared;
key defaults to `HMAC(APP_TOKEN,'media')` so it adds **no new env var**.
`ETag: "<sha256>"` + `Cache-Control: immutable`.

**The 4–5 day caption gap** is a state machine, not a wait:

1. **New photo, no caption** → create the row, run P3 + **flash only** (~$0.004)
   for a provisional roaster/origin so it's visible in the app immediately. Set
   `state='awaiting_text'`, `text_wait_until = captured_at + 10 days`. Don't
   spend the full pass.
2. **Caption arrives** (`text_sha256` appears or changes) → new `photo_texts`
   version, enqueue the full pass. Since `input_sha` includes `textSha256` this
   is genuinely a new question and correctly re-charges; the image-only
   extraction is retained and can still vote.
3. **Deadline passes, still no caption** → full pass image-only, then queue the
   required fields.
4. **A caption edited years later** → identical mechanism. Locked human fields
   survive.

## 4. Read API — delta sync, not eleven query endpoints

The brief wants filtering and sorting on ~11 dimensions, free-text search across
everything, and **live per-value facet counts** (`Ethiopia (12)`). Server-side
that's a round-trip per tap and eight own-dimension-excluded aggregates per
keystroke — precisely the fiddly, expensive part. Client-side it's one pass over
an in-memory array — precisely the free part.

Once vocab is dictionary-encoded and rows reference it by id, the whole
structured dataset is **~165 KB raw / ~35 KB gzipped**. So the app holds it all
and does every filter, sort, facet count and search **on-device, instantly, and
offline**.

```
GET  /api/snapshot            → { version, generatedAt, vocab{…}, coffees[~140 B ea], deleted[] }
                                 ETag; 304 when unchanged
GET  /api/snapshot/text       → { texts: { <pid>: "<folded search blob>" } }   ~230 KB gz
GET  /api/coffees…            → paged/faceted parity route (debug + review tooling)
GET  /api/coffees/:publicId   → detail + 3 rails + per-field provenance
GET  /api/coffees/top-filters → ≤7 server-ordered cards
POST /api/coffees/:publicId/favorite
GET  /api/search, /api/insights, /api/roasters/:slug, /api/origins/:slug
GET  /api/review, POST /api/review/:id, POST /api/review/bulk
GET  /api/config              → { tokenKind, capabilities, snapshotVersion, features }
GET|POST /api/admin/{jobs,adjudicate,reindex,sync,vocab}
GET  /media/:publicId/:variant.jpg?exp=&sig=
```

`@fastify/etag` and `@fastify/compress` are already registered, so a no-op sync
costs **one 304**. Reads use `requireAnyToken` (fixing defect #1); writes keep
`requireIngestToken`; `/api/config` lets the Connect screen self-diagnose instead
of showing an opaque 401.

**`POST /api/review/rules` is the highest-leverage endpoint in the system.** When
Radu confirms `Etiopia → Ethiopia` once, the alias persists server-side, so every
future import inherits it and the question is never asked twice.

## 5. iOS data architecture

**Full local snapshot as an in-memory index over one versioned file — not
SwiftData/SQLite.** The arguments, in order of weight:

- **`#Predicate` is a compile-time macro.** Composing 11 optional multi-select
  dimensions dynamically means 2^11 hand-written predicates or `NSPredicate`
  string-building. This alone disqualifies SwiftData.
- **Facet counts need GROUP BY**, and `FetchDescriptor` has no aggregates on
  iOS 17. You'd fetch every row anyway — so the store buys nothing.
- **~900 rows × ~1 KB ≈ 1 MB.** It fits in memory a thousand times over.
- **No local Xcode** (CI-only builds). SwiftData schema migrations, `@Model`
  macro surprises and container-init crashes are all **runtime** failures that a
  compile-only CI job will never catch. A `Codable` struct + JSON file has
  essentially no runtime failure mode beyond "decode failed → refetch".

```swift
struct CoffeeIndex: Sendable {                     // pure value type, no I/O, unit-testable
    let coffees: [Coffee]                          // canonical order: boughtOn desc
    let byID: [Coffee.ID: Int]
    let searchKeys: [String]                       // parallel array, diacritic-folded haystacks
    let postings: [FilterDimension: [AnyFacetKey: IndexSet]]
    func matches(_ f: CoffeeFilter) -> IndexSet
    func facets(for f: CoffeeFilter) -> FacetCounts
    func topFilterCards(limit: Int = 7) -> [TopFilterCard]
}
```

Filtering is `IndexSet` intersection over prebuilt postings — OR within a
dimension, AND across dimensions. At 900 rows this is microseconds, so the filter
sheet's `Show 862 coffees` button and every facet count recompute
**synchronously on every tap**: no debounce, no spinner, no `Task`.

**Facet semantics — the part people get wrong:** for dimension `D`, counts are
computed over `matches(filter.clearing(D))`, so every *other* active filter
applies but `D` doesn't constrain itself. That's what keeps "Ethiopia (12) /
Colombia (31)" meaningful after you've already selected Ethiopia. Zero-count
values render **disabled at 30% opacity, not hidden** — a stable vocabulary
teaches you "I own no Panama naturals", and pills that vanish under your thumb
are infuriating.

**Bucketing.** Altitude bands are **multi-valued**: a coffee stored as
1300–1600 m intersects both 1000–1500 and 1500–2000, so altitude facet counts sum
to more than the total. That's correct — the section gets a footnote. Rating bands
are half-open `[lower, upper)` with 5.0 folded into 4.5–5.0, plus an `Under 3`
bucket rendered only when non-empty.

**Sync:** `since = lastSyncAt − 60s` (clock skew), page until `nextCursor == nil`,
apply upserts + `deletedIDs`, rebuild the index **once** at the end, write the
snapshot atomically, then publish. `schemaVersion` mismatch or `totalCount`
divergence → drop and full-resync.

**Cold start never shows a blank list:** snapshot present → decode off-main
(~25 ms), publish, *then* delta-sync in the background. No snapshot → skeleton
rows, and the first 500-row page publishes immediately.

**Photos: a custom `ImageStore` actor, not `URLCache`.** `URLCache`'s
`diskCapacity` is a soft LRU budget — a ten-year archive is *data*, not a cache,
and must not be evicted at the OS's discretion. It also gives no hook to
downsample on write, so a 12 MP JPEG would decode to a 48 MB bitmap in a
scrolling list. Downsample with `CGImageSourceCreateThumbnailAtIndex` +
`…FromImageAlways` + `…WithTransform` — never `UIImage(data:)` then resize.
900 thumbs ≈ **70 MB, prefetch them all** over Wi-Fi via the BGTask so the
listing scrolls fully offline; fulls are lazy, capped at 250 MB, evicted after
30 days unused. In-flight coalescing (`[URL: Task]`) stops a fast scroll
launching 40 duplicate requests.

**Writes go through a `MutationOutbox` actor**: tap heart → mutate in memory and
publish immediately, enqueue, flush when online. On sync, the server row wins
**unless** a pending mutation for that `(id, field)` is un-acked. Single writer,
so last-write-wins is correct; anything more is theatre.

## 6. iOS screens

Three tabs — **Coffees / Insights / Review**. Search is `.searchable` on the
listing, not a tab: a Search tab would render the same rows through the same
filter model and create two sources of truth for `filter.query`. Settings sits
behind a toolbar gear. The Review tab is always present with a
`.badge(pendingCount)` — never conditionally inserted, which reindexes the bar.

### 6.1 Listing
**Use `List`, not `ScrollView`+`LazyVStack`** — `.listStyle(.plain)` gives sticky
section headers (exactly the "July 2026" behaviour) plus real cell reuse for 900
rows. Draw the Vivino card with hidden separators and clear row backgrounds.

Row (min 108 pt, `@ScaledMetric` thumb): 84×84 thumb · roaster flag + name ·
farm/lot title (2 lines, semibold) · origin flag + `Farm, Country` ·
`ProcessTag` + `⭐️4.1` + heart · right-aligned `€18.50` over `€7.40 / 100 g` ·
full-width grey footer strip with the exact date.

**Section headers per sort order** — the brief only specifies the date case:

| Sort | Header | Nil rows |
|---|---|---|
| date bought | `July 2026` | — |
| rating | `4.5 – 5.0 ★` | trailing `Unrated` |
| price | `€15 – €20` | trailing `No price` |
| €/100 g | `€6 – €8 / 100 g` | trailing `No price` |

When *not* sorted by date, the row footer switches from the exact date to
`July 2026`, so the brief's required month-year is never lost.

**Top filter cards** resolve the brief's 8-into-7 overbooking: Favourites
(pinned) · 4.5+ (pinned) · the single most-represented *interesting* process
(Natural and Washed excluded — at ~70% of the library they aren't a shortcut) ·
the top 4 origin countries **by count of coffees rated ≥4.0** (the brief's
explicit rule), tie-broken by localized name for stable ordering. Each card is
gated on `count ≥ 5` and `< total`, and deduped by resulting row set — so a thin
library shows 2 cards, not 7 empty ones. **Tapping a card replaces the whole
filter** (Vivino's behaviour); additive cards on top of a filter sheet make
"Show 862" incomprehensible.

### 6.2 Filter sheet
`.presentationDetents([.large])`. Sections in the brief's order. Pills are
`Label (count)` plus a trailing `★ 4.31` where available. `LazyVGrid` is wrong
for variable-width pills — a ~40-line `WrapLayout: Layout` (iOS 16+, zero deps).
Truncate to the top 8 per dimension then `Show all (312) ›` → a `.searchable`
full list — **mandatory** for Roaster (~100 values) and Farm (hundreds). Sticky
footer: `✕ Clear` and `Show \(total) coffees`.

### 6.3 Coffee detail
Full-bleed photo with circular back/share as real `ToolbarItem`s — **not**
`.navigationBarBackButtonHidden` + overlay, which kills edge-swipe-back. Then a
white card curving up (big rating, star row, `Your rating ›`), an inset
overlapping thumbnail, the roaster row with chevron, title, pill row,
`ProcessTag` + full `profile_detail`, a `FactRowsCard` (**missing fields omit
their row entirely — never "N/A"**), three note blocks (farm/lot and brew guide
expanded, roaster copy collapsed), then three rails.

Rails are ordered by **rating desc, not date** — the question "what else from
this roaster" is *what else is good*, not *what else is recent*. A rail with
fewer than 2 items is omitted; one item looks broken. Rail "More" goes to the
roaster/country **entity page** rather than a bare filtered list (which would
duplicate the roaster page and orphan its blurb and stats) — behind
`FeatureFlags.railMoreGoesToEntityPage`.

### 6.4 Insights
**Swift Charts, correlations computed on-device** — the data is already local, so
recomputation after any edit is instant and offline; the statistics are
elementary; and templated sentences are deterministic, where an LLM would add
hallucination risk and per-render cost. Reuse the existing `/api/brief` +
`briefs` table for a clearly separated *"This month"* editorial section.

**Gates, without which the page is a noise generator:** categorical needs n ≥ 5
in-group *and* out-group with |Δmean| ≥ 0.08; ordinal uses Spearman ρ with n ≥ 20
and |ρ| ≥ 0.15; cap at 12 sentences ordered by effect size; wording always
associative ("tend to"), never causal; **every sentence states its n**; never
render a p-value.

Charts (all iOS 17-safe — `BarMark`/`LineMark`/`RuleMark`,
`.chartForegroundStyleScale`, `.chartXSelection`; **avoid** iOS 18's
`BarPlot`/`LinePlot` and iOS 26's `Chart3D`): yearly stacked counts by origin
country, by process, by roaster (top 6 + Other), plus average rating by year with
a `RuleMark` at the all-time mean. Colours are pinned via
`.chartForegroundStyleScale(domain:range:)` so a series never changes hue between
charts and matches the listing tags.

Two additions the brief doesn't ask for but should have: a **Data quality** card
(completeness per field, each row tapping through to the review queue filtered to
that field) pinned at the top, and a **within-year z-score toggle** — one
person's ratings over 10 years cluster in 3.5–4.5 and drift upward as taste
calibrates, so raw effect sizes will be small and "2019 was a low-scoring year"
will masquerade as signal. ~15 lines, and it's the difference between insight and
artefact.

### 6.5 Review queue — the highest-volume interaction
**Budget: ≤1.5 s per decision, so ~400 fields ≈ 8 minutes.** Everything falls out
of that number.

**Batch cards first, and they are what make this tractable.** Any group of ≥8
tasks sharing `(field, normalizedValue)` collapses into one card: *"23 coffees
say **Etiopia** → Ethiopia? [Accept all 23] [Review individually]"*. Given the
brief's own data (`Columbia 314`, `Brazilia 61`, `Indonezia`, `NIcaragua`,
`Thailanda`, `Mexic`, `DAK` vs `DAK Coffee Roasters`), batch cards alone clear the
large majority of the queue in **under 30 decisions**. Then per-coffee groups
ordered by *fewest open fields first*, so you finish coffees and feel progress.

Card: progress counter · **the source photo at ~40% height, auto-zoomed to the
OCR bounding box and pinch-zoomable** — the killer feature, you read the actual
bag without leaving the card · the raw snippet with the match highlighted · the
top candidate as one big chip · 3–5 alternates with hints ("3 other coffees") ·
a `TextField` revealed only on `Other…`, because the keyboard is the enemy of the
budget.

| Gesture | Effect |
|---|---|
| swipe right / tap chip | accept, advance immediately — **no confirm step** |
| **long-press chip** | accept **and create a mapping rule** applied to every remaining task with the same normalised value, POSTed so future imports inherit it |
| swipe left | skip to back of queue |
| swipe down | `.notPresent` — not on the bag, stop asking forever |
| toast Undo (5 s) | 20-deep undo stack |

**Nothing in the deck ever awaits the network** — the whole queue is cached,
images for the next 3 tasks prefetched, resolutions go through the outbox. The
entire triage session works on a plane.

### 6.6 Design system, and two CI-specific rules
Process tags are tinted capsules with light/dark hex pairs defined in code via
`UIColor(dynamicProvider:)` — zero new asset entries, nothing for CI to
mis-generate: Decaf `moon.zzz.fill` `#4A5568`/`#A7B4C4` · Natural `sun.max.fill`
`#B23A1E`/`#FF9E7D` · Washed `drop.fill` `#0B6BB5`/`#7CC4FF` · Anaerobic
`seal.fill` `#6B3FA0`/`#C6A7F0` · Co-fermented `arrow.triangle.merge`
`#0E7C6B`/`#6FD9C4` · Experimental `testtube.2` `#A8145A`/`#FF9BC4`.

**Flags from ISO codes, not 40 PNGs:**
```swift
extension String {
    var flagEmoji: String? {
        let s = uppercased().unicodeScalars.filter { ("A"..."Z").contains(Character($0)) }
        guard s.count == 2 else { return nil }          // count SCALARS, not Characters
        return String(String.UnicodeScalarView(s.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    }
}
```
The trap: the two regional indicators combine into **one** grapheme cluster, so
`result.count == 2` is always false. Fall back to `🏳️` + code for `nil` — the data
contains `Blend` and `Colombia / Brazilia`, which are not countries. Names come
from `Locale.localizedString(forRegionCode:)`, so localization is free.

Two rules that exist purely because **there is no local Xcode**:
- **Every SF Symbol name lives in one `DesignSystem/Symbols.swift`.** They're
  strings the compiler can't check, and a typo renders as a silent blank.
- **One shared `JSONDecoder` with a fractional-seconds-tolerant ISO-8601
  strategy.** Postgres `timestamptz` serializes with fractional seconds and
  `.iso8601` **rejects** them. This bites every project once; pre-empt it.

**Zero SPM dependencies.** SwiftUI + Swift Charts + BackgroundTasks + Observation
cover 100% of this (Vision and PhotoKit are no longer needed — see §6.7). A
package-resolution failure is a 20-minute CI round-trip to diagnose with no way to
reproduce locally; SDK frameworks never do that.

**BGTask** — `ro.climbagain.mycoffee.refresh` is already permitted in
`Info.plist` but unregistered. Register in `MyCoffeeApp.init()` (registration must
complete before `didFinishLaunching` returns), reschedule *first* inside the
handler, then: delta sync → flush outbox → refresh review count → Wi-Fi-only
thumbnail top-up → refresh the editorial brief.

### 6.7 Going forward — Photos stays the capture surface, permanently
Radu keeps working exactly as he has for ten years: photograph the bag, move it to
the Coffees album, type the details into the caption a few days later. The **same
`osxphotos` exporter used for the backfill runs monthly** under `launchd`, and
because the manifest is content-addressed a re-run of unchanged photos costs
nothing (`need: "none"` for every entry).

**The app builds no capture surface at all** — no camera, no `PhotosPicker`, no
on-device OCR, no drafts, no editor, no PhotoKit watcher. It is **read-and-review
only**: browse, filter, favourite, and correct low-confidence fields. That also
means **no new Info.plist permission strings** — no camera, no photo-library, no
`NSPhotoLibraryAddUsageDescription` (the app never writes to the library).

Why the watcher isn't worth building even as a nag: **`PHAsset` exposes no public
API for the title/caption/description typed in the Photos app.** Those live in the
Photos database, not in the asset, and `PHAssetResource` returns original bytes
without them. Since the entire 10-year dataset lives in exactly those fields, a
PhotoKit path could detect a new photo but never read the text that matters — so
the Mac exporter would still be required, and the watcher would be a second
mechanism buying only an earlier reminder. Skipping it also cancels the half-day
PhotoKit spike: **nothing in this plan depends on PhotoKit.**

The cost of this choice is that the **4–5 day caption gap stays**. It's absorbed
server-side by the `awaiting_text` / `text_wait_until` state machine (§3): a photo
that arrives without a caption gets a cheap flash-only pass so it's visible
immediately, and the full 5-voter pass fires when `text_sha256` appears. Because
`input_sha` includes `textSha256`, that's correctly treated as a new question.

**Marginal cost per new coffee:** ~$0.07 (a full 5-voter pass) rather than the
~$0.005 an in-app confirmation flow would have cost — negligible at a handful of
bags a month, and the reason this trade is cheap.

**`project.yml` needs almost no change**: `sources: [MyCoffee/Sources,
MyCoffee/Resources]` with `createIntermediateGroups: true` already recurses, so
every new folder is picked up. The only addition is an optional `MyCoffeeTests`
unit-test target — run on dispatch only, never on every `main` push, since macOS
minutes bill at 10×.

## 7. Parallel agent lanes

Six lanes, as asked. **Only two of them cost macOS minutes**, so going from two
lanes to six doesn't change the bill.

| Lane | Branch | Owns (glob-checkable) | Conflicts with |
|---|---|---|---|
| Backend | `main` | `backend/src/**`, `backend/migrations/00[6-9]…`, `backend/test/**` | Data (migrations, `src/lib/`) |
| Data | `main` | `ops/**`, `005_vocab_seed.sql`, `src/lib/{normalize,fuzzy,vocab,fx,deterministic,prompts}.js` | Backend |
| iOS shell | `ios-staging` | `Sources/{App,Store,API,Models,Query,Utilities}/**` | iOS UX (at the seam only) |
| iOS UX | `ios-staging` | `Sources/{Features,DesignSystem}/**`, `Resources/**` | iOS shell (at the seam only) |
| Compile | dispatch only | — | Publish (one workflow, one concurrency group) |
| Publish | `main` | `certs/`, `profiles/`, `match_version.txt`, `.github/workflows/**` | Compile |

The iOS partition is genuinely disjoint and checkable by path glob: **shell owns
plumbing, UX owns presentation.** The seam is the `CoffeeStore`/`CoffeeIndex` API
surface — shell publishes it, UX consumes it. Both work on `ios-staging`; because
their file sets don't overlap, git merges cleanly and only the seam needs a claim.

**Compile and Publish share one workflow** with `concurrency: ios-testflight,
cancel-in-progress: false`, so a queued publish sits behind a compile. Rule:
**Publish is the only lane allowed to dispatch `publish=true`**, and it checks for
an in-flight run first. Compile only ever dispatches `publish=false`.

**Claim protocol.** `BUILD_STATUS.md`'s single mutable "Claims" section is itself
a merge-conflict generator with six agents. Replace it with **`status/<lane>.md`
— one file per lane**, so git never conflicts by construction. `BUILD_STATUS.md`
stays as the human-readable index: external checklist plus an append-only Done
log, newest first. A claim older than 24 h with no commits on its branch is
reclaimable by any lane.

**CI changes** — two, and one deliberate non-change:
- **Add a `test` job to `railway-deploy.yml` and make `deploy` need it.** Backend
  deploys now run through a GitHub workflow (`railway up --ci --service MyCoffee`)
  rather than Railway's native trigger, so gating is free and needs no Railway
  setting: one `ubuntu-latest` job running `npm ci && npm test` in `backend/`, with
  `deploy: needs: [test]`. Both jobs are 1× billing. This is strictly better than
  the separate advisory workflow I'd first sketched — a red test now stops a bad
  deploy instead of merely reporting it, and it costs one extra ~30-second job.
- **No change to `ios-testflight.yml`.** Adding `ios-staging` to `push.branches`
  would burn a ~200-minute macOS job on *every* iOS-lane push, several times a
  day. `workflow_dispatch` already targets any branch via `ref`, so the Compile
  lane dispatches `publish=false` against `ios-staging` with zero workflow edits.
- **No linter.** Nothing is configured today, Swift can't be usefully linted
  without a local toolchain, and the backend is covered by `node --test`.

**Cron** (UTC; MyHealthOS fires at 09:00, so all macOS work stays at 20:00 on
non-colliding days):

| Lane | Cron | macOS/run | Runs/mo |
|---|---|---|---|
| Backend | `0 */3 * * *` | none | ~240 |
| Data | `30 1 * * *` | none | ~30 |
| iOS shell | `0 3,15 * * *` | none | ~60 |
| iOS UX | `0 9,21 * * *` | none | ~60 |
| Compile | `0 20 * * 3,6` | ~20 min → 200 billed | ~8.7 |
| Publish | `0 20 * * 4,0` | ~20 min → 200 billed | ~8.7 |

~350 *actual* macOS minutes/month for MyCoffee. The free 2000 includes the 10×
multiplier, i.e. ~200 free actual macOS minutes shared with MyHealthOS, so
MyCoffee's share is roughly **$20/month, ~$40 combined** — matching the setup
brief. **During build-out, hold Publish to Sundays only** (`0 20 * * 0`): saves
~$7/month and enforces the "batch 2–4 ready items" rule that makes a red ship
cheap to diagnose.

**New lane rule for `CLAUDE.md`: never ship `backend/**` while an extraction job
is `running`.** Railway auto-deploys on push and would SIGTERM the worker. The
lease reaper makes it survivable, but check `GET /api/admin/jobs` first.

## 8. Phasing, and the one step to de-risk immediately

**Phase 0 — all four code lanes in parallel, nothing blocks anything:**
- Backend: `003`–`006` + `normalize`/`fuzzy`/`vocab`/`fx` + tests. No API change.
- Data: extract the docx lists into seed files; build the normaliser test corpus
  from the brief's own examples (`"1300 ro 1600"`, `4,1/5`, `1.600`).
- iOS shell: models, `CoffeeIndex`, filter/facet/bands, `BundledSampleRepository`.
- iOS UX: design system, listing, filter sheet, sort, detail — **fully working on
  30 bundled rows, zero backend dependency.**
- **Publish: fix the AppIcon and dispatch the first `publish=true` now.**

**That last item is the single highest-risk unproven step in the whole project**
and it is currently scheduled last, which is backwards. `match` has never run,
`certs/` and `profiles/` are empty, there is **no distribution certificate under
team `PH2NNQ47UB`** (the setup brief's cert-reuse claim was wrong — that team
isn't on this Apple ID), and the empty AppIcon fails at *processing* time, after
CI has already gone green. Prove the whole signing and upload chain **while the
app is still trivial**, when a red ship costs one cheap diagnosis instead of
blocking a finished app.

Then: **1** photos ingest (`007` + images + media) — gate: run the Mac exporter on
**20 photos**, confirm derivatives, dedupe (re-run → all `need:"none"`), signed
URLs. **2** coffees + search (`008`–`009` + snapshot) — gate: the app lists a live
empty dataset. **3** extraction (`010`–`011`) — gate: **Phase-0 rules pass over
the full corpus for $0**, vocabulary confirmed through the review queue, then
thresholds tuned on 25 records and re-adjudicated free until the queue looks
right. **4** full backfill overnight with the spend cap set — gate: **30 random
auto-accepted records hand-checked.** **5** review queue UI, insights, roaster and
country pages. **6** harden the incremental path: `launchd` monthly schedule on the
Mac, the `awaiting_text` deadline sweep, and `POST /api/admin/sync` on a backend
cron. (There is no in-app-capture phase — see §6.7.)

## 9. Verification

```bash
BASE="https://mycoffee-production-bd43.up.railway.app"; TOK="${APP_TOKEN:-$INGEST_TOKEN}"
curl -s "$BASE/health"                                    # {"ok":true,"db":true,"service":"mycoffee-api"}
curl -s "$BASE/api/status"  -H "Authorization: Bearer $TOK"
curl -s "$BASE/api/config"  -H "Authorization: Bearer $TOK"   # tokenKind + capabilities + snapshotVersion
curl -sI "$BASE/api/snapshot" -H "Authorization: Bearer $TOK"  # ETag; repeat with If-None-Match → 304
curl -s "$BASE/api/admin/jobs" -H "Authorization: Bearer $INGEST_TOKEN"  # progress + spendUsd
cd backend && npm ci && npm test                          # node:test, no DB needed
```

**Cannot be verified from inside the sandbox, and a human must confirm:** the
agent's egress policy may block `*.railway.app`, so run the curls from a machine
that can reach Railway; TestFlight *processing* outcome arrives by email ~20 min
after a green CI job (the `skip_waiting_for_build_processing` consequence); and
the actual on-device UI. The GitHub MCP server disconnected mid-session, so
Actions run status needs `curl` against the REST API rather than the MCP tools.

## 10. Docs to update

`CLAUDE.md` §4 (six lanes, not two), §5 (dev/ship split with two iOS lanes), §10
(new cron table), §12 (add: don't ship `backend/**` during an extraction job).
`BUILD_STATUS.md` → replace the Claims section with `status/<lane>.md` and close
out the four stale queue items, all of which said "once the product brief lands".
