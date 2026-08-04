// Smoke tests that don't require a live database -- same pattern as
// coffees.test.js / photos.test.js. A query that actually reaches
// review_items/field_resolutions needs DATABASE_URL.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

test('GET /api/review requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/review' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/review/:id requires the ingest token specifically', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/review/1', payload: { value: 'x' } });
  // No server token configured -> 503; a missing/wrong bearer -> 401. Never
  // gated only by APP_TOKEN, same rule as every other write route.
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/review/bulk requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/review/bulk', payload: { items: [] } });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/review/rules requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'POST',
    url: '/api/review/rules',
    payload: { kind: 'roaster', canonicalId: 1, alias: 'Etiopia' },
  });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});
