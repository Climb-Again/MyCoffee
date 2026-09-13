// #194 — /api/history validates and auths correctly before touching the DB.
// Same shape as whatsnew-seen.test.js: a valid body gets past validation and
// only then reaches a query (which fails here with no DATABASE_URL), so "not
// 400 and not 401" proves acceptance without needing a live Postgres.
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
process.env.APP_TOKEN = 'test-app-token';
const { build } = await import('../src/server.js');

const READ = { authorization: 'Bearer test-app-token' };
const WRITE = { authorization: 'Bearer test-ingest-token' };

function post(app, payload, headers = WRITE) {
  return app.inject({ method: 'POST', url: '/api/history', headers, payload });
}

test('POST /api/history with a read token is 401', async () => {
  const app = await build();
  const res = await post(app, { url: 'https://shop.test/a' }, READ);
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('POST /api/history with no bearer is 401', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/history', payload: { url: 'https://shop.test/a' } });
  assert.equal(res.statusCode, 401);
  await app.close();
});

function postRaw(app, jsonText, headers = WRITE) {
  return app.inject({
    method: 'POST',
    url: '/api/history',
    headers: { ...headers, 'content-type': 'application/json' },
    payload: jsonText,
  });
}

test('POST /api/history with a JSON primitive body is 400', async () => {
  const app = await build();
  const res = await postRaw(app, JSON.stringify('nope'));
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'bad_entry');
  await app.close();
});

test('POST /api/history with an array body is 400', async () => {
  const app = await build();
  const res = await postRaw(app, JSON.stringify([{ url: 'https://shop.test/a' }]));
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'bad_entry');
  await app.close();
});

test('POST /api/history with no url is 400', async () => {
  const app = await build();
  const res = await post(app, { score: 50 });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'bad_url');
  await app.close();
});

test('POST /api/history with an unparseable url that yields an empty key is 400', async () => {
  const app = await build();
  const res = await post(app, { url: '' });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'bad_url');
  await app.close();
});

test('POST /api/history with an oversized payload is 400', async () => {
  const app = await build();
  const res = await post(app, { url: 'https://shop.test/a', explanation: 'x'.repeat(9000) });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'payload_too_large');
  await app.close();
});

test('POST /api/history with a valid entry gets past validation', async () => {
  const app = await build();
  const res = await post(app, { url: 'https://shop.test/coffee', score: 88, roasterName: 'DAK' });
  // Passes validation; fails at the DB with no DATABASE_URL. The point is that
  // a valid body is neither 400 nor 401.
  assert.notEqual(res.statusCode, 400);
  assert.notEqual(res.statusCode, 401);
  await app.close();
});

test('GET /api/history with a read token is 401 (write token keys the list)', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/history', headers: READ });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('GET /api/history with no token is 401', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/history' });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('GET /api/history with the write token gets past auth', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/history', headers: WRITE });
  // Past auth; fails at the DB with no DATABASE_URL. Not a 401 is the point.
  assert.notEqual(res.statusCode, 401);
  await app.close();
});

test('DELETE /api/history with a read token is 401', async () => {
  const app = await build();
  const res = await app.inject({ method: 'DELETE', url: '/api/history', headers: READ });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('DELETE /api/history with the write token gets past auth', async () => {
  const app = await build();
  const res = await app.inject({ method: 'DELETE', url: '/api/history', headers: WRITE });
  assert.notEqual(res.statusCode, 401);
  await app.close();
});
