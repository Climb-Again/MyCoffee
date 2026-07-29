// Smoke tests that don't require a live database.
// `app.inject` exercises routing without binding a port; healthcheck() fails
// gracefully to db:false when no DATABASE_URL is configured.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

test('GET /health responds ok', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.ok, true);
  assert.equal(body.service, 'mycoffee-api');
  await app.close();
});

test('GET /api/status requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/status' });
  // No token configured server-side -> 503; token configured but missing -> 401.
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/ingest rejects unauthorized writes', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'POST',
    url: '/api/ingest',
    payload: { type: 'test', payload: {} },
  });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/brief requires a token but accepts either kind', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/brief' });
  // No token configured server-side -> 503; token configured but missing -> 401.
  // Never 404 (the route exists) and never a hardcoded APP_TOKEN-only 401.
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/config requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/config' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});
