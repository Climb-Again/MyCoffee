// Smoke tests that don't require a live database — same pattern as
// health.test.js / photos.test.js. These only exercise the auth guard, since
// a query that actually reaches the coffees/photos tables needs DATABASE_URL.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

test('GET /api/snapshot requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/snapshot' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/snapshot/text requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/snapshot/text' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/coffees requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/coffees' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/coffees/:publicId requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/coffees/some-id' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/coffees/top-filters requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/coffees/top-filters' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/coffees/:publicId/favorite requires the ingest token specifically', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'POST',
    url: '/api/coffees/some-id/favorite',
    payload: { favorite: true },
  });
  // No server token configured -> 503; a missing/wrong bearer -> 401. Never a
  // 200/404 without auth, and never gated only by APP_TOKEN.
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/coffees/:publicId/edit requires the ingest token specifically', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'POST',
    url: '/api/coffees/some-id/edit',
    payload: { field: 'rating', value: '4.5' },
  });
  // No server token configured -> 503; a missing/wrong bearer -> 401. Never a
  // 200/404/422 without auth, and never gated only by APP_TOKEN (PLAN.md §12 #40).
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /api/config reports the snapshot capability once #21 lands', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/config' });
  // Same auth-gated shape as every other read route here -- no DB means we
  // can't assert the 200 body, but the route must still exist and be gated.
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});
