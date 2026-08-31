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
