// #222 — GET /api/admin/vocab-observations. Validation + auth only; the DB
// isn't reachable in this test env, but a valid request must clear auth and
// query-parsing before hitting the query (same shape as brew.test.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
process.env.APP_TOKEN = 'test-app-token';
const { build } = await import('../src/server.js');

const WRITE = { authorization: 'Bearer test-ingest-token' };
const READ = { authorization: 'Bearer test-app-token' };

test('GET /api/admin/vocab-observations requires INGEST_TOKEN (401 with read token)', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/admin/vocab-observations', headers: READ });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('GET /api/admin/vocab-observations with a valid token gets past auth', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/admin/vocab-observations', headers: WRITE });
  // Passes auth; fails at the DB with no DATABASE_URL. Not 401 proves auth.
  assert.notEqual(res.statusCode, 401);
  await app.close();
});

test('GET /api/admin/vocab-observations accepts kind + limit query params without 400', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'GET',
    url: '/api/admin/vocab-observations?kind=roaster_logo_url&limit=5',
    headers: WRITE,
  });
  assert.notEqual(res.statusCode, 400);
  assert.notEqual(res.statusCode, 401);
  await app.close();
});
