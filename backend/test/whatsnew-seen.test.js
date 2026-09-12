// #201 — /api/whatsnew/seen validates and auths correctly before touching the
// DB. Same shape as brew.test.js: a valid body gets past validation and only
// then reaches a query (which fails here with no DATABASE_URL), so "not 400
// and not 401" proves acceptance without needing a live Postgres.
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
process.env.APP_TOKEN = 'test-app-token';
const { build } = await import('../src/server.js');

const READ = { authorization: 'Bearer test-app-token' };
const WRITE = { authorization: 'Bearer test-ingest-token' };

function post(app, payload, headers = WRITE) {
  return app.inject({ method: 'POST', url: '/api/whatsnew/seen', headers, payload });
}

test('POST /api/whatsnew/seen with a read token is 401', async () => {
  const app = await build();
  const res = await post(app, { key: 'abc' }, READ);
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('POST /api/whatsnew/seen with no key is 400', async () => {
  const app = await build();
  const res = await post(app, {});
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'bad_key');
  await app.close();
});

test('POST /api/whatsnew/seen with an empty key is 400', async () => {
  const app = await build();
  const res = await post(app, { key: '' });
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('POST /api/whatsnew/seen with a non-string key is 400', async () => {
  const app = await build();
  const res = await post(app, { key: 42 });
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('POST /api/whatsnew/seen with an oversized key is 400', async () => {
  const app = await build();
  const res = await post(app, { key: 'x'.repeat(4097) });
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('POST /api/whatsnew/seen with a valid body gets past validation', async () => {
  const app = await build();
  const res = await post(app, { key: 'abcd1234' });
  // Passes validation; fails at the DB with no DATABASE_URL → 500. The point
  // is that a valid body is neither 400 nor 401.
  assert.notEqual(res.statusCode, 400);
  assert.notEqual(res.statusCode, 401);
  await app.close();
});

test('GET /api/whatsnew/seen requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/whatsnew/seen' });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('GET /api/whatsnew (unchanged) still returns the content payload', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/whatsnew', headers: READ });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.ok(Array.isArray(body.live));
  assert.ok(body.plan);
  await app.close();
});
