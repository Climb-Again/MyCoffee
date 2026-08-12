// Smoke test for GET /api/whatsnew (PLAN.md §13, issue #45) plus a pure shape
// check on the hand-curated data file -- it's edited by hand whenever a
// backlog row flips, so a structural regression (a renamed key, a lane typo)
// should fail the suite rather than surface as a blank client screen.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { build } from '../src/server.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_PATH = path.join(__dirname, '../src/data/whatsnew.json');

test('GET /api/whatsnew requires a token', async () => {
  const app = await build();
  const res = await app.inject({ method: 'GET', url: '/api/whatsnew' });
  assert.ok([401, 503].includes(res.statusCode));
  await app.close();
});

test('whatsnew.json has the shape the client DTO expects', () => {
  const content = JSON.parse(readFileSync(DATA_PATH, 'utf8'));

  assert.ok(Array.isArray(content.live));
  for (const item of content.live) {
    assert.equal(typeof item.title, 'string');
    assert.equal(typeof item.detail, 'string');
    assert.equal(typeof item.area, 'string');
  }

  assert.ok(content.plan && typeof content.plan === 'object');
  const { byLane, needsApproval } = content.plan;
  for (const lane of ['backend', 'data', 'ios']) {
    assert.ok(Array.isArray(byLane[lane]), `byLane.${lane} must be an array`);
    for (const item of byLane[lane]) {
      assert.equal(typeof item.title, 'string');
      assert.equal(typeof item.detail, 'string');
    }
  }

  assert.ok(Array.isArray(needsApproval));
  for (const item of needsApproval) {
    assert.equal(typeof item.title, 'string');
    assert.equal(typeof item.detail, 'string');
  }
});
