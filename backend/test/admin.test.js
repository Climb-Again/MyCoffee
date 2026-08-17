// Smoke tests that don't require a live database -- same pattern as
// coffees.test.js / photos.test.js. A query that actually reaches
// extraction_jobs needs DATABASE_URL, and starting a real job needs live
// Vertex credentials besides -- neither is available in this suite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

test('GET /api/admin/jobs requires the ingest token specifically', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/admin/jobs' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/jobs requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/jobs', payload: {} });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/jobs/:id/pause requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/jobs/1/pause' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/jobs/:id/resume requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/jobs/1/resume' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/adjudicate requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/adjudicate', payload: {} });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/rederive-photos requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/rederive-photos', payload: {} });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('POST /api/admin/backfill-ocr-text requires the ingest token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'POST', url: '/api/admin/backfill-ocr-text', payload: {} });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});
