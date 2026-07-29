// Smoke tests that don't require a live database — same pattern as
// health.test.js. These only exercise the auth guard, since a valid request
// would need DATABASE_URL to reach the photos/photo_texts tables.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

test('POST /api/photos/manifest requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'POST',
    url: '/api/photos/manifest',
    payload: { entries: [] },
  });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('PUT /api/photos/:sourceId/image requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({
    method: 'PUT',
    url: '/api/photos/abc-123/image?sha256=' + '0'.repeat(64),
    payload: Buffer.from('not a real jpeg'),
    headers: { 'content-type': 'application/octet-stream' },
  });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('GET /media/:publicId/:variant.jpg rejects a missing signature', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/media/someid/thumb.jpg' });
  assert.equal(res.statusCode, 403);
  await app.close();
});

test('GET /media/:publicId/:variant.jpg rejects an unknown variant before any signature check', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/media/someid/original.jpg?exp=1&sig=abc' });
  assert.equal(res.statusCode, 404);
  await app.close();
});
