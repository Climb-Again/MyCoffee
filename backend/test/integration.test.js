// #174: the ONE test file that runs a route handler body end to end.
//
// Before this, all 325 tests passed while exercising nothing: every route test
// asserted `[401, 503].includes(res.statusCode)`, and with no INGEST_TOKEN /
// APP_TOKEN / DATABASE_URL in CI only `auth.js`'s `auth_not_configured` branch
// ever ran. `safeEqual`, `presentedTokenKind`, every 200 path, `resolveField`,
// `getOrCreateVocabEntry`, `claimBatch`, `storeResolutions`, `db.js` and
// `migrate.js` had zero coverage — #166's data-loss bug and #168's unstable
// ETag would each have been caught by one test here.
//
// SKIPS ITSELF when DATABASE_URL is unset, so the existing no-DB suite still
// runs anywhere. CI sets it to a throwaway postgres:16 service container with
// throwaway tokens (never the real secrets — they are secrets, and the job must
// not read them; see railway-deploy.yml).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

const HAS_DB = Boolean(process.env.DATABASE_URL);
const INGEST = process.env.INGEST_TOKEN;
const APP = process.env.APP_TOKEN;

// The module graph reads config at import time, so only import it once we know
// the env is configured — otherwise an unconfigured run would build a pool
// against nothing.
let build;
let query;
let readjudicateAll;
let countPendingPhotos;

let app;
let ids = {};

const ingestAuth = () => ({ authorization: `Bearer ${INGEST}` });
const appAuth = () => ({ authorization: `Bearer ${APP}` });

before(async () => {
  if (!HAS_DB) return;
  ({ build } = await import('../src/server.js'));
  ({ query } = await import('../src/db.js'));
  ({ readjudicateAll, countPendingPhotos } = await import('../src/lib/worker.js'));
  const { runMigrations } = await import('../src/migrate.js');
  if (typeof runMigrations === 'function') await runMigrations();

  app = await build();

  // One photo + one coffee, inserted directly. Going through the ingest route
  // would drag in image derivation and an LLM call; the point here is the read
  // and mutation paths, not ingestion.
  const suffix = Date.now().toString(36);
  const { rows: photoRows } = await query(
    `INSERT INTO photos (public_id, source, source_id, state, has_image, captured_on, title)
     VALUES ($1, 'test', $2, 'processed', true, DATE '2026-01-15', 'Test bag')
     RETURNING id, public_id`,
    [`ph_${suffix}`, `src_${suffix}`],
  );
  ids.photoId = photoRows[0].id;
  ids.photoPublicId = photoRows[0].public_id;

  const { rows: coffeeRows } = await query(
    `INSERT INTO coffees (public_id, photo_id, purchased_on, raw_title, raw_description, rating, weight_g)
     VALUES ($1, $2, DATE '2026-01-15', 'Test bag', 'Procesare: Washed', 4.0, 250)
     RETURNING id, public_id`,
    [`co_${suffix}`, ids.photoId],
  );
  ids.coffeeId = coffeeRows[0].id;
  ids.coffeePublicId = coffeeRows[0].public_id;
});

after(async () => {
  if (!HAS_DB) return;
  if (ids.coffeeId) await query(`DELETE FROM coffees WHERE id = $1`, [ids.coffeeId]).catch(() => {});
  if (ids.photoId) await query(`DELETE FROM photos WHERE id = $1`, [ids.photoId]).catch(() => {});
  if (app) await app.close();
  const { pool } = await import('../src/db.js');
  await pool.end();
});

// ---- auth (the branches CI has never reached) ----

test('a real token authenticates; a wrong one is 401', { skip: !HAS_DB }, async () => {
  const ok = await app.inject({ method: 'GET', url: '/api/status', headers: appAuth() });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().db, true);

  const bad = await app.inject({ method: 'GET', url: '/api/status', headers: { authorization: 'Bearer nope' } });
  assert.equal(bad.statusCode, 401);
});

test('a read token cannot write', { skip: !HAS_DB }, async () => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/favorite`,
    headers: appAuth(),
    payload: { favorite: true },
  });
  assert.equal(res.statusCode, 401);
});

// ---- #168: the snapshot must be able to 304 ----

test('#168: two back-to-back /api/snapshot responses share an ETag, and the second 304s', { skip: !HAS_DB }, async () => {
  const first = await app.inject({ method: 'GET', url: '/api/snapshot', headers: appAuth() });
  assert.equal(first.statusCode, 200);
  const etag = first.headers.etag;
  assert.ok(etag, 'no ETag on /api/snapshot — @fastify/etag not applied');

  const second = await app.inject({ method: 'GET', url: '/api/snapshot', headers: appAuth() });
  assert.equal(second.headers.etag, etag, 'ETag changed between two identical requests (unstable body)');

  const conditional = await app.inject({
    method: 'GET',
    url: '/api/snapshot',
    headers: { ...appAuth(), 'if-none-match': etag },
  });
  assert.equal(conditional.statusCode, 304);
});

test('#168: generatedAt is a real cursor, and /api/snapshot/text takes a since', { skip: !HAS_DB }, async () => {
  const full = await app.inject({ method: 'GET', url: '/api/snapshot', headers: appAuth() });
  const { generatedAt, coffees } = full.json();
  assert.ok(!Number.isNaN(new Date(generatedAt).getTime()), 'generatedAt is not a timestamp');
  assert.ok(coffees.some((c) => c.id === ids.coffeePublicId));

  // The cursor is millisecond-truncated (see the route's comment: the iOS
  // client can only round-trip 3 fractional digits), so a delta taken at it
  // re-sends at most the rows sharing that final millisecond — never the whole
  // corpus, and never nothing that changed. What matters is that it is STABLE,
  // because that is what lets the conditional GET 304.
  const deltaUrl = `/api/snapshot?since=${encodeURIComponent(generatedAt)}`;
  const delta = await app.inject({ method: 'GET', url: deltaUrl, headers: appAuth() });
  assert.ok(delta.json().coffees.length <= 1, `delta returned ${delta.json().coffees.length} rows, expected <= 1`);
  assert.equal(delta.json().generatedAt, generatedAt, 'the cursor moved on a no-op delta');

  const deltaAgain = await app.inject({
    method: 'GET',
    url: deltaUrl,
    headers: { ...appAuth(), 'if-none-match': delta.headers.etag },
  });
  assert.equal(deltaAgain.statusCode, 304, 'a repeated delta did not 304');

  const textFull = await app.inject({ method: 'GET', url: '/api/snapshot/text', headers: appAuth() });
  assert.equal(textFull.statusCode, 200);
  assert.equal(textFull.json().partial, false);

  const textDelta = await app.inject({
    method: 'GET',
    url: `/api/snapshot/text?since=${encodeURIComponent(new Date(Date.now() + 60_000).toISOString())}`,
    headers: appAuth(),
  });
  assert.equal(textDelta.json().partial, true);
  assert.equal(Object.keys(textDelta.json().texts).length, 0);
});

// ---- mutations ----

test('favorite round-trips and bumps updated_at', { skip: !HAS_DB }, async () => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/favorite`,
    headers: ingestAuth(),
    payload: { favorite: true },
  });
  assert.equal(res.statusCode, 200);
  const { rows } = await query(`SELECT is_favorite FROM coffees WHERE id = $1`, [ids.coffeeId]);
  assert.equal(rows[0].is_favorite, true);
});

test('rotation persists and rejects an out-of-range value', { skip: !HAS_DB }, async () => {
  const ok = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/rotation`,
    headers: ingestAuth(),
    payload: { quarterTurns: 2 },
  });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().rotationQuarterTurns, 2);

  const bad = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/rotation`,
    headers: ingestAuth(),
    payload: { quarterTurns: 9 },
  });
  assert.equal(bad.statusCode, 400);
});

// ---- #172: a half-applied multi-field edit ----

test('#172: one bad field among good ones writes NOTHING', { skip: !HAS_DB }, async () => {
  const before = await query(`SELECT weight_g, rating FROM coffees WHERE id = $1`, [ids.coffeeId]);
  const beforeLocked = await query(`SELECT count(*)::int AS n FROM field_resolutions WHERE photo_id = $1`, [ids.photoId]);

  const res = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/edit`,
    headers: ingestAuth(),
    payload: {
      edits: [
        { field: 'weight', value: '500g' },
        // Countries are a closed vocab (#36) — an unknown one is the canonical
        // 422, and it is the LAST edit, so the first would already have been
        // written under the old loop.
        { field: 'originCountry', value: 'Not A Real Country At All' },
      ],
    },
  });
  assert.equal(res.statusCode, 422);

  const after = await query(`SELECT weight_g, rating FROM coffees WHERE id = $1`, [ids.coffeeId]);
  assert.equal(after.rows[0].weight_g, before.rows[0].weight_g, 'weight was applied despite the 422');

  const afterLocked = await query(`SELECT count(*)::int AS n FROM field_resolutions WHERE photo_id = $1`, [ids.photoId]);
  assert.equal(afterLocked.rows[0].n, beforeLocked.rows[0].n, 'a locked human resolution was written despite the 422');
});

test('#172: an all-good multi-field edit does apply', { skip: !HAS_DB }, async () => {
  const res = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/edit`,
    headers: ingestAuth(),
    payload: { edits: [{ field: 'weight', value: '500g' }, { field: 'rating', value: '4.5/5' }] },
  });
  assert.equal(res.statusCode, 200);
  const { rows } = await query(`SELECT weight_g, rating FROM coffees WHERE id = $1`, [ids.coffeeId]);
  assert.equal(rows[0].weight_g, 500);
  assert.equal(Number(rows[0].rating), 4.5);
});

test('#172: POST /api/review/rules 404s on an unknown canonical id instead of 500', { skip: !HAS_DB }, async () => {
  const res = await app.inject({
    method: 'POST',
    url: '/api/review/rules',
    headers: ingestAuth(),
    payload: { kind: 'roaster', canonicalId: 99_999_999, alias: 'Some Alias' },
  });
  assert.equal(res.statusCode, 404);

  const bad = await app.inject({
    method: 'POST',
    url: '/api/review/rules',
    headers: ingestAuth(),
    payload: { kind: 'roaster', canonicalId: 'abc', alias: 'Some Alias' },
  });
  assert.equal(bad.statusCode, 400);
});

// ---- #166: re-adjudication must not eat the appended OCR text ----

test('#166: readjudicateAll preserves an appended OCR block', { skip: !HAS_DB }, async () => {
  const withOcr = 'Procesare: Washed\n\nOCR text\nAltitude 1800 masl';
  await query(`UPDATE coffees SET raw_description = $1 WHERE id = $2`, [withOcr, ids.coffeeId]);
  await readjudicateAll({ photoId: ids.photoId });
  const { rows } = await query(`SELECT raw_description FROM coffees WHERE id = $1`, [ids.coffeeId]);
  assert.ok(rows[0].raw_description.includes('OCR text'), 're-adjudication wiped the appended OCR block');
});

// ---- #170 / #169: the daily no-op ----

test('#170: pending counts use claimBatch\'s own predicate', { skip: !HAS_DB }, async () => {
  const before = await countPendingPhotos();
  // Our fixture photo is `processed`, so it is not claimable.
  assert.equal(typeof before.total, 'number');
  assert.equal(before.total, before.textReceived + before.awaitingTextOverdue);

  await query(`UPDATE photos SET state = 'text_received' WHERE id = $1`, [ids.photoId]);
  const after = await countPendingPhotos();
  assert.equal(after.textReceived, before.textReceived + 1);
  await query(`UPDATE photos SET state = 'processed' WHERE id = $1`, [ids.photoId]);

  const res = await app.inject({ method: 'GET', url: '/api/admin/jobs', headers: ingestAuth() });
  assert.equal(res.statusCode, 200);
  assert.ok(res.json().pending, '/api/admin/jobs does not report pending');
});

test('#169: a job records includeImages + limit, and a bad :id is 400 not 500', { skip: !HAS_DB }, async () => {
  const created = await app.inject({
    method: 'POST',
    url: '/api/admin/jobs',
    headers: ingestAuth(),
    payload: { includeImages: false, limit: 7, spendCapUsd: 0 },
  });
  assert.equal(created.statusCode, 202);
  const job = created.json();
  assert.equal(job.includeImages, false);
  assert.equal(job.photoLimit, 7);

  const bad = await app.inject({ method: 'POST', url: '/api/admin/jobs/abc/pause', headers: ingestAuth() });
  assert.equal(bad.statusCode, 400);

  await query(`DELETE FROM extraction_jobs WHERE id = $1`, [job.id]).catch(() => {});
});

// ---- brew (#155) ----

test('brew options are served and a trial round-trips', { skip: !HAS_DB }, async () => {
  const opts = await app.inject({ method: 'GET', url: '/api/brew-options', headers: appAuth() });
  assert.equal(opts.statusCode, 200);
  const list = opts.json().options ?? opts.json();
  assert.ok(Array.isArray(list) && list.length > 0, 'no brew options seeded');

  const optionId = (list[0].id ?? list[0].optionId);
  const set = await app.inject({
    method: 'POST',
    url: `/api/coffees/${ids.coffeePublicId}/brew`,
    headers: ingestAuth(),
    payload: { optionId, state: 'best' },
  });
  assert.ok([200, 201].includes(set.statusCode), `brew POST returned ${set.statusCode}: ${set.body}`);

  const snap = await app.inject({ method: 'GET', url: '/api/snapshot', headers: appAuth() });
  const mine = snap.json().coffees.find((c) => c.id === ids.coffeePublicId);
  assert.ok((mine.brewTried ?? []).includes(optionId), 'brew trial did not reach the snapshot');
});

// ---- #198: browsing grows the VOCAB, never the coffee library ----

test('#198: a new roaster is created with an alias, and coffees is untouched', { skip: !HAS_DB }, async () => {
  const name = `Test Roaster ${Date.now().toString(36)}`;
  const before = await query(`SELECT count(*)::int AS n FROM coffees`);

  const res = await app.inject({
    method: 'POST',
    url: '/api/vocab/observations',
    headers: ingestAuth(),
    payload: {
      sourceUrl: 'https://shop.test/about',
      roaster: {
        name,
        description: 'A small roaster that exists only in this test.',
        logoUrl: 'https://shop.test/logo.png',
        countryName: 'Romania',
      },
    },
  });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.ok(body.roasterId, 'no roaster created');
  assert.ok(body.created.includes('roaster'));

  const { rows } = await query(`SELECT name, blurb, logo_url, country_id FROM roasters WHERE id = $1`, [body.roasterId]);
  assert.equal(rows[0].name, name);
  assert.ok(rows[0].blurb, 'blurb not applied');
  assert.equal(rows[0].logo_url, 'https://shop.test/logo.png');

  // CLAUDE.md §12: a vocab row with no alias is invisible to extraction.
  const { rows: aliases } = await query(`SELECT count(*)::int AS n FROM roaster_aliases WHERE roaster_id = $1`, [body.roasterId]);
  assert.ok(aliases[0].n > 0, 'the new roaster has no alias and can never be matched from text');

  const after = await query(`SELECT count(*)::int AS n FROM coffees`);
  assert.equal(after.rows[0].n, before.rows[0].n, 'an observation created a coffee — the one thing it must never do');

  await query(`DELETE FROM roaster_aliases WHERE roaster_id = $1`, [body.roasterId]);
  await query(`DELETE FROM vocab_observations WHERE target_id = $1`, [body.roasterId]);
  await query(`DELETE FROM roasters WHERE id = $1`, [body.roasterId]);
});

test('#198: an existing blurb/logo is never overwritten', { skip: !HAS_DB }, async () => {
  const name = `Kept Roaster ${Date.now().toString(36)}`;
  const first = await app.inject({
    method: 'POST',
    url: '/api/vocab/observations',
    headers: ingestAuth(),
    payload: { roaster: { name, description: 'the original', logoUrl: 'https://a.test/one.png' } },
  });
  const id = first.json().roasterId;

  const second = await app.inject({
    method: 'POST',
    url: '/api/vocab/observations',
    headers: ingestAuth(),
    payload: { roaster: { name, description: 'a shop page trying to clobber it', logoUrl: 'https://b.test/two.png' } },
  });
  assert.ok(second.json().declined.includes('blurb'));
  assert.ok(second.json().declined.includes('logo'));

  const { rows } = await query(`SELECT blurb, logo_url FROM roasters WHERE id = $1`, [id]);
  assert.equal(rows[0].blurb, 'the original');
  assert.equal(rows[0].logo_url, 'https://a.test/one.png');

  await query(`DELETE FROM roaster_aliases WHERE roaster_id = $1`, [id]);
  await query(`DELETE FROM vocab_observations WHERE target_id = $1`, [id]);
  await query(`DELETE FROM roasters WHERE id = $1`, [id]);
});

test('#198: countries stay closed — an unknown one creates nothing', { skip: !HAS_DB }, async () => {
  const before = await query(`SELECT count(*)::int AS n FROM countries`);
  const res = await app.inject({
    method: 'POST',
    url: '/api/vocab/observations',
    headers: ingestAuth(),
    payload: { originCountryName: 'Definitely Not A Coffee Country' },
  });
  assert.equal(res.statusCode, 200);
  assert.ok(res.json().declined.includes('originCountry'));
  const after = await query(`SELECT count(*)::int AS n FROM countries`);
  assert.equal(after.rows[0].n, before.rows[0].n, 'a scraped string minted a country row');
  await query(`DELETE FROM vocab_observations WHERE extracted_value = 'Definitely Not A Coffee Country'`);
});

test('#198: a non-http logo src is rejected before it reaches the column', { skip: !HAS_DB }, async () => {
  const name = `Safe Roaster ${Date.now().toString(36)}`;
  const res = await app.inject({
    method: 'POST',
    url: '/api/vocab/observations',
    headers: ingestAuth(),
    payload: { roaster: { name, logoUrl: 'javascript:alert(1)' } },
  });
  const id = res.json().roasterId;
  const { rows } = await query(`SELECT logo_url FROM roasters WHERE id = $1`, [id]);
  assert.equal(rows[0].logo_url, null);
  await query(`DELETE FROM roaster_aliases WHERE roaster_id = $1`, [id]);
  await query(`DELETE FROM vocab_observations WHERE target_id = $1`, [id]);
  await query(`DELETE FROM roasters WHERE id = $1`, [id]);
});

test('#198: an empty observation is a 400, not a silent no-op', { skip: !HAS_DB }, async () => {
  const res = await app.inject({ method: 'POST', url: '/api/vocab/observations', headers: ingestAuth(), payload: {} });
  assert.equal(res.statusCode, 400);
});

// ---- #126(c): a captioned photo gets ONE image pass, not zero ----

test("#126c: a text-only pass that leaves core fields unresolved flags the photo, once", { skip: !HAS_DB }, async () => {
  const { shouldUseImage, unresolvedCoreFields } = await import('../src/lib/worker.js');

  // Our fixture photo is captioned (state was 'text_received' at some point),
  // has an image, and has no field_resolutions at all.
  const missing = await unresolvedCoreFields(ids.photoId);
  assert.ok(missing.length > 0, 'fixture should have unresolved core fields');

  // Not flagged yet -> a text-only job does NOT send its image.
  assert.equal(shouldUseImage({ state: 'text_received', needs_image_pass: false }, false), false);
  // Flagged -> it does, whatever the job's own flag says. That is the rule
  // change: before this, a captioned photo's image was never sent, ever.
  assert.equal(shouldUseImage({ state: 'text_received', needs_image_pass: true }, false), true);
  // And an image-only photo still always sends its image (#69, unchanged).
  assert.equal(shouldUseImage({ state: 'awaiting_text', needs_image_pass: false }, false), true);

  // The escalation is claimable even from 'processed' — that is what re-opens
  // the photo for its one pass — and is counted in `pending` so the ingest
  // script (#171) does not exit early while one is outstanding.
  await query(
    `UPDATE photos SET state = 'processed', needs_image_pass = true, image_pass_at = NULL WHERE id = $1`,
    [ids.photoId],
  );
  const pending = await countPendingPhotos();
  assert.ok(pending.imageEscalation >= 1, `expected an escalation in pending, got ${JSON.stringify(pending)}`);
  assert.ok(pending.total >= 1, 'an outstanding escalation must not read as "nothing pending"');

  // Once the pass has run, image_pass_at closes it out permanently: a bag whose
  // fields are genuinely absent cannot burn a vision call on every run.
  await query(`UPDATE photos SET image_pass_at = now(), needs_image_pass = false WHERE id = $1`, [ids.photoId]);
  const after = await countPendingPhotos();
  assert.equal(after.imageEscalation, 0, 'a completed escalation is still being claimed');

  await query(`UPDATE photos SET state = 'processed', image_pass_at = NULL WHERE id = $1`, [ids.photoId]);
});

// ---- #152 (option A): the roaster content write path ----

test('#152: PATCH sets a blurb, clears it with "", 404s an unknown slug', { skip: !HAS_DB }, async () => {
  const slug = `t-roaster-${Date.now().toString(36)}`;
  const { rows } = await query(`INSERT INTO roasters (name, slug) VALUES ($1, $2) RETURNING id`, ['T Roaster', slug]);
  const id = rows[0].id;

  const set = await app.inject({
    method: 'PATCH', url: `/api/roasters/${slug}`, headers: ingestAuth(),
    payload: { blurb: '  A small roaster that exists only in this test.  ' },
  });
  assert.equal(set.statusCode, 200);
  const after = await query(`SELECT blurb, content_source FROM roasters WHERE id = $1`, [id]);
  assert.equal(after.rows[0].blurb, 'A small roaster that exists only in this test.', 'blurb not trimmed/stored');
  assert.equal(after.rows[0].content_source, 'app', 'provenance not recorded');

  // Empty string clears — the in-app editor (#153) needs an undo, and NULL is
  // what "no blurb" means everywhere else (the checklist counts on it).
  const cleared = await app.inject({
    method: 'PATCH', url: `/api/roasters/${slug}`, headers: ingestAuth(), payload: { blurb: '' },
  });
  assert.equal(cleared.statusCode, 200);
  assert.equal((await query(`SELECT blurb FROM roasters WHERE id = $1`, [id])).rows[0].blurb, null);

  const missing = await app.inject({
    method: 'PATCH', url: '/api/roasters/no-such-roaster-at-all', headers: ingestAuth(), payload: { blurb: 'x' },
  });
  assert.equal(missing.statusCode, 404);

  const bad = await app.inject({
    method: 'PATCH', url: `/api/roasters/${slug}`, headers: ingestAuth(), payload: {},
  });
  assert.equal(bad.statusCode, 400);

  await query(`DELETE FROM roasters WHERE id = $1`, [id]);
});

test('#152: PUT a logo — normalized, content-addressed, served back, and the vocab points at us', { skip: !HAS_DB }, async () => {
  const sharp = (await import('sharp')).default;
  const slug = `t-logo-${Date.now().toString(36)}`;
  const { rows } = await query(`INSERT INTO roasters (name, slug) VALUES ($1, $2) RETURNING id`, ['T Logo', slug]);
  const id = rows[0].id;

  // 900px: deliberately ABOVE the 512 cap, so the downscale is actually
  // exercised. The colour is RANDOM per run, and that matters: logos are
  // content-addressed, so a fixed fixture writes the same sha every time and
  // the "first upload" is only a 201 on a machine that has never run this test.
  // It returned 200/deduped on the second local run and would do the same on
  // any re-used DATA_DIR — a test that passes once and then reports a false
  // failure. A unique image makes both halves deterministic: genuinely new, then
  // genuinely deduped.
  const png = await sharp({
    create: {
      width: 900,
      height: 600,
      channels: 3,
      background: {
        r: Math.floor(Math.random() * 256),
        g: Math.floor(Math.random() * 256),
        b: Math.floor(Math.random() * 256),
      },
    },
  }).png().toBuffer();

  const put = await app.inject({
    method: 'PUT', url: `/api/roasters/${slug}/logo`,
    headers: { ...ingestAuth(), 'content-type': 'image/png' },
    payload: png,
  });
  assert.equal(put.statusCode, 201, put.body);
  const body = put.json();
  assert.equal(body.width, 512, 'longest side was not capped at 512');
  assert.equal(body.height, 341);
  assert.ok(body.bytes < png.length, 'WebP re-encode did not shrink a flat PNG');
  assert.match(body.logoUrl, new RegExp(`/roaster-logos/${slug}\\.webp$`));

  // The snapshot vocab must now point at OUR host, not raw.githubusercontent —
  // that is #152's "in-app write is source of truth" decision, made real.
  const row = await query(`SELECT logo_url, content_source FROM roasters WHERE id = $1`, [id]);
  assert.equal(row.rows[0].logo_url, body.logoUrl);
  assert.equal(row.rows[0].content_source, 'app');

  // Served back, unsigned and with the right type — no token, because
  // AsyncImage cannot attach one.
  const get = await app.inject({ method: 'GET', url: `/roaster-logos/${slug}.webp` });
  assert.equal(get.statusCode, 200);
  assert.equal(get.headers['content-type'], 'image/webp');
  assert.ok(Number(get.headers['content-length']) > 0);

  // Content-addressed: the identical upload writes nothing new.
  const again = await app.inject({
    method: 'PUT', url: `/api/roasters/${slug}/logo`,
    headers: { ...ingestAuth(), 'content-type': 'image/png' }, payload: png,
  });
  assert.equal(again.statusCode, 200);
  assert.equal(again.json().deduped, true);

  await query(`DELETE FROM roaster_logos WHERE roaster_id = $1`, [id]);
  await query(`DELETE FROM roasters WHERE id = $1`, [id]);
});

test('#152: a non-image body is 400, not 500, and an unknown slug 404s', { skip: !HAS_DB }, async () => {
  const slug = `t-bad-${Date.now().toString(36)}`;
  const { rows } = await query(`INSERT INTO roasters (name, slug) VALUES ($1, $2) RETURNING id`, ['T Bad', slug]);

  const notAnImage = await app.inject({
    method: 'PUT', url: `/api/roasters/${slug}/logo`,
    headers: { ...ingestAuth(), 'content-type': 'application/octet-stream' },
    payload: Buffer.from('this is definitely not a picture'),
  });
  assert.equal(notAnImage.statusCode, 400, 'a bad upload is the caller\'s problem, not a server fault');

  const unknown = await app.inject({
    method: 'PUT', url: '/api/roasters/no-such-roaster-at-all/logo',
    headers: { ...ingestAuth(), 'content-type': 'image/png' }, payload: Buffer.from('x'),
  });
  assert.equal(unknown.statusCode, 404);

  const missingLogo = await app.inject({ method: 'GET', url: `/roaster-logos/${slug}.webp` });
  assert.equal(missingLogo.statusCode, 404, 'a roaster with no logo row must 404, not 500');

  await query(`DELETE FROM roasters WHERE id = $1`, [rows[0].id]);
});

test('#152: the logo route requires a write token', { skip: !HAS_DB }, async () => {
  const res = await app.inject({
    method: 'PUT', url: '/api/roasters/anything/logo',
    headers: { ...appAuth(), 'content-type': 'image/png' }, payload: Buffer.from('x'),
  });
  assert.equal(res.statusCode, 401);
});
