// POST /api/coffees/:publicId/rotation range validation (#73). Its own file
// because it needs INGEST_TOKEN configured before src/config.js is imported,
// whereas coffees.test.js asserts the unconfigured-token behaviour. `node --test`
// gives each file its own process, so the two don't interfere.
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
const { build } = await import('../src/server.js');

async function post(app, quarterTurns) {
  return app.inject({
    method: 'POST',
    url: '/api/coffees/some-id/rotation',
    headers: { authorization: 'Bearer test-ingest-token' },
    payload: { quarterTurns },
  });
}

test('rotation rejects out-of-range and non-integer quarter turns with 400', async () => {
  const app = await build();
  // Validation runs before the UPDATE, so these need no database.
  for (const bad of [-1, 4, 1.5, '1', null, undefined]) {
    const res = await post(app, bad);
    assert.equal(res.statusCode, 400, `quarterTurns=${JSON.stringify(bad)} should be rejected`);
    assert.equal(res.json().error, 'invalid_quarter_turns');
  }
  await app.close();
});

test('rotation accepts 0..3 (past validation, into the DB layer)', async () => {
  const app = await build();
  for (const ok of [0, 1, 2, 3]) {
    const res = await post(app, ok);
    // No DATABASE_URL here, so a valid value gets past validation and fails at
    // the query — anything but 400 proves it was accepted.
    assert.notEqual(res.statusCode, 400, `quarterTurns=${ok} should pass validation`);
  }
  await app.close();
});
