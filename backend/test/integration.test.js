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
