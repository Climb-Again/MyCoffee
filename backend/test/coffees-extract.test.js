// Add Coffee wizard (#75) request-shape validation for POST /api/coffees/extract
// and POST /api/coffees. Its own file because it needs INGEST_TOKEN configured
// before src/config.js is imported, whereas coffees.test.js asserts the
// unconfigured-token behaviour — same split as rotation.test.js. Only the
// validation that runs before any DB query is covered here; the DB-touching
// paths (photo lookup, extraction, upsertCoffeeBase, resolveField) were
// verified end-to-end against a real local Postgres 16 (see status/backend.md),
// same convention as every other worker.js-adjacent route in this repo.
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
const { build } = await import('../src/server.js');
const { buildExtractFields } = await import('../src/routes/coffees.js');
const { adjudicateRecord } = await import('../src/lib/adjudicate.js');

function post(app, url, payload) {
  return app.inject({
    method: 'POST',
    url,
    headers: { authorization: 'Bearer test-ingest-token' },
    payload,
  });
}

test('POST /api/coffees/extract rejects an empty/missing photoIds list with 400, no DB needed', async () => {
  const app = await build();
  for (const bad of [{}, { photoIds: [] }, { photoIds: 'not-an-array' }]) {
    const res = await post(app, '/api/coffees/extract', bad);
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, 'missing_photo_ids');
  }
  await app.close();
});

test('POST /api/coffees rejects an empty/missing photoIds list with 400, no DB needed', async () => {
  const app = await build();
  for (const bad of [{}, { photoIds: [] }, { photoIds: 'not-an-array' }]) {
    const res = await post(app, '/api/coffees', bad);
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, 'missing_photo_ids');
  }
  await app.close();
});

test('POST /api/coffees/extract with a non-empty photoIds list passes validation, into the DB layer', async () => {
  const app = await build();
  const res = await post(app, '/api/coffees/extract', { photoIds: ['some-id'] });
  // No DATABASE_URL here, so a valid shape gets past validation and fails at
  // the query -- anything but 400 proves it was accepted.
  assert.notEqual(res.statusCode, 400);
  await app.close();
});

test('POST /api/coffees with a non-empty photoIds list passes validation, into the DB layer', async () => {
  const app = await build();
  const res = await post(app, '/api/coffees', { photoIds: ['some-id'], fields: [] });
  assert.notEqual(res.statusCode, 400);
  await app.close();
});

test('POST /api/coffees/quick-create rejects an empty/missing photoIds list with 400, no DB needed', async () => {
  const app = await build();
  for (const bad of [{}, { photoIds: [] }, { photoIds: 'not-an-array' }]) {
    const res = await post(app, '/api/coffees/quick-create', bad);
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, 'missing_photo_ids');
  }
  await app.close();
});

test('POST /api/coffees/quick-create with a non-empty photoIds list passes validation, into the DB layer', async () => {
  const app = await build();
  const res = await post(app, '/api/coffees/quick-create', { photoIds: ['some-id'] });
  // No DATABASE_URL here, so a valid shape gets past validation and fails at
  // the query -- anything but 400 proves it was accepted. The background
  // extraction it would otherwise kick never gets a photo row to run on.
  assert.notEqual(res.statusCode, 400);
  await app.close();
});

test('POST /api/coffees/evaluate rejects an empty/missing photoIds list with 400, no DB needed', async () => {
  const app = await build();
  for (const bad of [{}, { photoIds: [] }, { photoIds: 'not-an-array' }]) {
    const res = await post(app, '/api/coffees/evaluate', bad);
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error, 'missing_photo_ids');
  }
  await app.close();
});

test('POST /api/coffees/evaluate with a non-empty photoIds list passes validation, into the DB layer', async () => {
  const app = await build();
  const res = await post(app, '/api/coffees/evaluate', { photoIds: ['some-id'] });
  // No DATABASE_URL here, so a valid shape gets past validation and fails at
  // the query -- anything but 400 proves it was accepted (#106's DB-touching
  // path is verified end-to-end against a real local Postgres separately,
  // same convention as /extract above).
  assert.notEqual(res.statusCode, 400);
  await app.close();
});

// ---- buildExtractFields (#121) -- pure over adjudicateRecord's output, so ----
// ---- this needs no DB/voter ensemble at all. ----

const roasterVocab = { candidates: [{ id: 1, name: 'DAK', slug: 'dak' }], aliasIndex: new Map() };

test('buildExtractFields: a roaster resolved against vocab is a normal accepted field', () => {
  const candidatesByField = { roaster_id: [{ agent: 'extract_a', value: 'DAK', confidence: 0.9 }] };
  const { resolutions } = adjudicateRecord(candidatesByField, { vocab: { roasters: roasterVocab } });
  const fields = buildExtractFields(resolutions, candidatesByField);
  assert.equal(fields.roaster.value, 'DAK');
  assert.equal(fields.roaster.decision, 'accepted');
});

test('buildExtractFields: #121 -- a brand-new roaster not in vocab still surfaces as an editable draft, not dropped', () => {
  const candidatesByField = {
    roaster_id: [
      { agent: 'extract_b', value: 'Spojka', confidence: 0.8 },
      { agent: 'reconciler', value: 'Spojka', confidence: 0.9 },
    ],
  };
  const { resolutions } = adjudicateRecord(candidatesByField, { vocab: { roasters: roasterVocab } });
  // Confirms the underlying bug still reproduces: canonicalize can't resolve
  // "Spojka" against the vocab, so the adjudicated value stays null.
  assert.equal(resolutions.roaster_id.value, null);
  const fields = buildExtractFields(resolutions, candidatesByField);
  assert.equal(fields.roaster.value, 'Spojka');
  assert.equal(fields.roaster.decision, 'draft');
  assert.equal(fields.roaster.confidence, 0);
});

test('buildExtractFields: a field with no candidates at all is still omitted (unrelated to #121)', () => {
  const { resolutions } = adjudicateRecord({}, { vocab: { roasters: roasterVocab } });
  const fields = buildExtractFields(resolutions, {});
  assert.equal(fields.roaster, undefined);
  assert.equal(fields.price, undefined);
});

test('buildExtractFields: an unresolvable *price* stays dropped -- the draft carve-out is roaster-only', () => {
  const candidatesByField = { price: [{ agent: 'extract_a', value: 'not a price', confidence: 0.9 }] };
  const { resolutions } = adjudicateRecord(candidatesByField, {});
  assert.equal(resolutions.price.value, null);
  const fields = buildExtractFields(resolutions, candidatesByField);
  assert.equal(fields.price, undefined);
});
