# ops/ — Data lane tooling

Everything here is owned by the Data extract + validate lane (`CLAUDE.md` §4,
`status/README.md`). Two independent tools live side by side:

- `seed-fx-rates.mjs` / `fx_rates_seed.sql` — one-time FX seed generator (#34).
- `mycoffee_export.py` / `test_mycoffee_export.py` — the Mac exporter +
  uploader for the "Coffees" Photos album (#20), documented below.

## `mycoffee_export.py` — Mac exporter + uploader

Two-phase upload against `backend/src/routes/photos.js`, per `PLAN.md` §3:

1. `POST /api/photos/manifest` — cheap metadata batch (≤200 entries/request).
   The server replies per photo with `need: "image" | "none"`.
2. `PUT /api/photos/:sourceId/image?sha256=<hex>` — only for photos the
   manifest flagged, raw JPEG body. The server generates the `ocr`/`display`/
   `thumb` derivatives itself via `sharp` (see `routes/photos.js`).

**This only runs end-to-end on macOS, on Radu's Mac, against his real Photos
library.** It depends on:

- [`osxphotos`](https://github.com/RhetTbull/osxphotos) (`pip install
  osxphotos`) to read the "Coffees" album — `PHAsset`/PhotoKit cannot expose
  the title/caption/description typed into Photos (`CLAUDE.md` §12), so this
  is the only viable read path.
- macOS's built-in `sips` to convert each original (often HEIC) down to a
  2048px JPEG — the same shape as the server's `ocr` derivative — **before**
  it ever reaches `sharp`, since prebuilt `sharp`/`libvips` binaries commonly
  ship without HEIF decode support.

Everything above the "macOS-specific I/O" marker in `mycoffee_export.py`
(manifest-entry shaping, batching, the on-disk state cache, HTTP retry logic)
has no Photos-library or `sips` dependency and is unit-tested on any platform:

```bash
cd ops && python3 -m unittest test_mycoffee_export -v
```

The macOS-only glue (`iter_album_photos`, `convert_to_jpeg`) cannot be
exercised outside a Mac with the real library — those functions are covered
by mocking in the `run()` orchestration tests instead of by an integration
test.

### Setup (on the Mac)

```bash
pip install osxphotos
export MYCOFFEE_INGEST_TOKEN=...      # or INGEST_TOKEN; the Railway INGEST_TOKEN value
```

`--backend-url` defaults to the live Railway URL
(`https://mycoffee-production-bd43.up.railway.app`, `CLAUDE.md` §0); override
with `MYCOFFEE_BACKEND_URL` or `--backend-url` for local testing against a
`node src/server.js` instance.

### Running

```bash
# PLAN.md §8's de-risking gate: try 20 photos first, confirm derivatives and
# dedupe before trusting a full run.
python3 ops/mycoffee_export.py --limit 20

# See what would be sent without any network calls or uploads:
python3 ops/mycoffee_export.py --dry-run

# The real, full backfill once the 20-photo gate looks right:
python3 ops/mycoffee_export.py
```

Gate checklist (PLAN.md §8, not yet run — needs Radu's Mac):
- [ ] 20-photo `--limit` run completes without error
- [ ] `GET /api/admin/jobs` / a manual `psql` check shows sane rows (title,
      description, `captured_on`, `favorite`)
- [ ] Re-running the same 20 photos is a no-op (manifest `need: "none"` for
      all, zero PUTs, matching the log's "0 photo(s) need an image upload")
- [ ] Spot-check one `GET /media/:publicId/ocr.jpg?...` signed URL round-trips
      a real, correctly-oriented image. **Not `sharp .rotate()` server-side**
      as this line used to say — that assumed the orientation tag survives
      the exporter's `sips` conversion, and it doesn't (#59). The exporter
      itself now bakes the correction into pixels before upload; `sharp` never
      sees a tag to act on either way. Take one deliberately-sideways photo
      in the test batch and confirm it uploads upright.

### Design notes worth knowing before changing this

- **`contentSha256` must be the hash of the exact bytes later PUT, not of the
  original file.** The server stores whatever `contentSha256` the manifest
  declares as `photos.content_sha256`, and the `PUT` route 409s
  (`sha256_mismatch`) if the uploaded body's hash doesn't match it. So the
  script always hashes the **post-`sips`** JPEG, never the HEIC original —
  see `build_manifest_entry` / `run()`.
- **The state cache (`--state-file`, default under `~/Library/Application
  Support/MyCoffee/`) skips re-running `sips` on unchanged files**, keyed by
  `(size, mtime)` rather than a full re-hash — a repeat run over ~900
  unchanged photos should cost a `stat()` each, not 900 image conversions.
  This is a local optimization only; it is never the source of truth for
  whether the server needs an image (the manifest response is), so a stale
  or deleted cache just costs one extra `sips` conversion per photo, never a
  correctness bug.
- **`caption` is always sent as `null`.** The manifest schema
  (`routes/photos.js`) accepts a separate `title` / `caption` / `description`,
  but Photos.app itself only exposes one free-text field beyond Title —
  `osxphotos` surfaces it as `.description` — so there is no real "caption" to
  send. All prose goes into `description`.
- **Images are re-encoded to JPEG client-side** (not sent as HEIC/original)
  specifically so the server's `sharp` pipeline never has to decode HEIF.
  `sips -s format jpeg -s formatOptions <quality> --resampleHeightWidthMax
  <dim>` matches the server's `ocr` derivative (2048px, q85) — see
  `DERIVATIVES` in `routes/photos.js`.
- **Retry/backoff (`(2, 5, 15, 45, 120)`s) only applies to 5xx/network
  errors.** A 4xx (bad request, auth, `sha256_mismatch`) is deterministic —
  retrying would just repeat the same failure, so those return immediately.
- **Rate limit:** `PUT /api/photos/:sourceId/image` is overridden to
  `INGEST_RATE_LIMIT_MAX` (1200/min) server-side specifically for a cold
  ~900-photo backfill (`backend/src/config.js`) — no client-side throttling
  needed for a single-run backfill.
- **EXIF orientation is baked into pixels here, not left to the server (#59).**
  `sips`'s own format/resize conversion above silently drops the orientation
  tag without rotating the pixels — the root cause of photos that display
  upright on the Mac but sideways in the app. `convert_to_jpeg` now calls
  `read_exif_orientation` (a `sips -g orientation` query) on the *source*
  first, maps the result through the pure `sips_orientation_args` (table-
  driven tests, all 8 EXIF values), and passes the matching `--rotate`/
  `--flip` flags in the same `sips` invocation that does the format/resize —
  so the JPEG that leaves this script is already upright, tag or no tag.
  **Not verified against a real `sips` binary** — this sandbox has no macOS
  runner, same limitation as the rest of this file's macOS-only glue; the
  EXIF-orientation → rotate/flip mapping itself is the standard one used by
  every image library (not `sips`-specific), but the exact `sips` flag names
  (`--rotate`, `--flip {horizontal|vertical}`) are unverified pending a real
  run. Photos already uploaded sideways before this fix need #57's persisted
  client-side rotate (their retained `ocr` source is already baked sideways)
  or a re-export from the Mac — this only fixes photos ingested from here on.

### Not built here (later work)

- **Scheduling** (`launchd`, monthly re-run) is #29's job, not #20's — this
  script is invoked manually for now. `PLAN.md` §6.7 describes the intended
  cadence once #29 lands.
- **The `awaiting_text` deadline sweep** (a caption arriving 4–5 days after
  the photo, or never) is a **server-side** state machine driven by
  `photo_texts` versions on each manifest re-run, not something the exporter
  itself needs to reason about.
