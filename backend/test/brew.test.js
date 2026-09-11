// Brew lab (PLAN.md §14, backlog #155). Two layers, no live database:
//   1. Validation via app.inject — every bad body is rejected 4xx BEFORE the
//      route reaches a query, so these run with no DATABASE_URL (same trick as
//      rotation.test.js: a valid body gets past validation and fails at the DB,
//      so "not 400" proves acceptance).
//   2. Pure unit tests of lib/brewState.js, imported directly.
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.INGEST_TOKEN = 'test-ingest-token';
const { build } = await import('../src/server.js');
const { nextTrialRows, impliedTrials } = await import('../src/lib/brewState.js');

const AUTH = { authorization: 'Bearer test-ingest-token' };

function postOption(app, payload) {
  return app.inject({ method: 'POST', url: '/api/brew-options', headers: AUTH, payload });
}
function postBrew(app, payload) {
  return app.inject({ method: 'POST', url: '/api/coffees/some-id/brew', headers: AUTH, payload });
}

// ── POST /api/brew-options validation ──────────────────────────────────────

test('POST /api/brew-options rejects an unknown kind with 400', async () => {
  const app = await build();
  const res = await postOption(app, { kind: 'bogus', label: 'X' });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'invalid_brew_kind');
  await app.close();
});

test('POST /api/brew-options rejects out-of-range grind clicks with 400', async () => {
  const app = await build();
  for (const bad of [0, 61, 1.5, '24', null]) {
    const res = await postOption(app, { kind: 'grind', valueNum: bad });
    assert.equal(res.statusCode, 400, `grind valueNum=${JSON.stringify(bad)} should be rejected`);
    assert.equal(res.json().error, 'invalid_grind_clicks');
  }
  await app.close();
});

test('POST /api/brew-options rejects out-of-range temperature with 400', async () => {
  const app = await build();
  for (const bad of [59, 101, 94.5, '94', null]) {
    const res = await postOption(app, { kind: 'temp', valueNum: bad });
    assert.equal(res.statusCode, 400, `temp valueNum=${JSON.stringify(bad)} should be rejected`);
    assert.equal(res.json().error, 'invalid_temperature');
  }
  await app.close();
});

test('POST /api/brew-options rejects an incomplete recipe with 400 invalid_recipe naming the field', async () => {
  const app = await build();
  const base = { doseG: 20, pours: 5, mlPerPour: 60, totalWaterMl: 300, grindClicks: 28, waterTempC: 92 };
  const cases = [
    [{ ...base, doseG: 0 }, 'doseG'],
    [{ ...base, pours: 13 }, 'pours'],
    [{ ...base, totalWaterMl: 0 }, 'totalWaterMl'],
    [{ ...base, grindClicks: 61 }, 'grindClicks'],
    [{ ...base, waterTempC: 50 }, 'waterTempC'],
    [undefined, 'recipe'],
  ];
  for (const [recipe, field] of cases) {
    const res = await postOption(app, { kind: 'recipe', label: 'Test', recipe });
    assert.equal(res.statusCode, 400, `recipe=${JSON.stringify(recipe)} should be rejected`);
    const body = res.json();
    assert.equal(body.error, 'invalid_recipe');
    assert.equal(body.field, field);
  }
  await app.close();
});

test('POST /api/brew-options rejects a recipe whose pours × ml/pour disagrees with total water', async () => {
  const app = await build();
  // 5 × 60 = 300, total 400 → 33% off, well beyond ±5%.
  const recipe = { doseG: 20, pours: 5, mlPerPour: 60, totalWaterMl: 400, grindClicks: 28, waterTempC: 92 };
  const res = await postOption(app, { kind: 'recipe', label: 'Mismatch', recipe });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'recipe_water_mismatch');
  await app.close();
});

test('POST /api/brew-options requires a label for a device', async () => {
  const app = await build();
  const res = await postOption(app, { kind: 'device', label: '   ' });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'missing_label');
  await app.close();
});

test('POST /api/brew-options accepts a valid body past validation (fails only at the DB)', async () => {
  const app = await build();
  // A well-formed grind and a well-formed recipe both clear validation; with no
  // DATABASE_URL they then fail at the query — anything but 400 proves acceptance.
  const grind = await postOption(app, { kind: 'grind', valueNum: 24 });
  assert.notEqual(grind.statusCode, 400, 'valid grind should pass validation');
  const recipe = await postOption(app, {
    kind: 'recipe', label: '4:6 test',
    recipe: { doseG: 20, pours: 5, mlPerPour: 60, totalWaterMl: 300, grindClicks: 28, waterTempC: 92 },
  });
  assert.notEqual(recipe.statusCode, 400, 'valid recipe should pass validation');
  await app.close();
});

// ── POST /api/coffees/:publicId/brew validation ────────────────────────────

test('POST …/brew rejects an invalid state with 400 invalid_brew_state', async () => {
  const app = await build();
  for (const bad of ['won', '', null, undefined, 5]) {
    const res = await postBrew(app, { optionId: 1, state: bad });
    assert.equal(res.statusCode, 400, `state=${JSON.stringify(bad)} should be rejected`);
    assert.equal(res.json().error, 'invalid_brew_state');
  }
  await app.close();
});

test('POST …/brew rejects a non-integer optionId with 400', async () => {
  const app = await build();
  for (const bad of ['1', 1.5, null, undefined]) {
    const res = await postBrew(app, { optionId: bad, state: 'tried' });
    assert.equal(res.statusCode, 400, `optionId=${JSON.stringify(bad)} should be rejected`);
    assert.equal(res.json().error, 'invalid_option_id');
  }
  await app.close();
});

test('POST …/brew accepts a valid body past validation (fails only at the DB)', async () => {
  const app = await build();
  const res = await postBrew(app, { optionId: 1, state: 'best' });
  assert.notEqual(res.statusCode, 400, 'valid brew state should pass validation');
  await app.close();
});

// ── lib/brewState.js pure unit tests ───────────────────────────────────────

test('nextTrialRows: setting best demotes the old best of that kind', () => {
  const current = { bestOptionId: 7 };
  const option = { id: 9, kind: 'device' };
  const { mutations } = nextTrialRows(current, option, 'best');

  const demote = mutations.find((m) => m.action === 'demote');
  assert.ok(demote, 'a demote of the prior best must be emitted');
  assert.equal(demote.optionId, 7, 'the OLD best (7) is demoted');

  const upsert = mutations.find((m) => m.action === 'upsert');
  assert.ok(upsert, 'the new option is upserted');
  assert.equal(upsert.optionId, 9);
  assert.equal(upsert.isBest, true);

  // Demote must come before the upsert so the one-best-per-kind index is never
  // momentarily violated.
  assert.ok(mutations.indexOf(demote) < mutations.indexOf(upsert));
});

test('nextTrialRows: best with no prior winner emits no demote', () => {
  const { mutations } = nextTrialRows({ bestOptionId: null }, { id: 3, kind: 'grind' }, 'best');
  assert.equal(mutations.filter((m) => m.action === 'demote').length, 0);
  assert.deepEqual(mutations, [{ action: 'upsert', optionId: 3, kind: 'grind', isBest: true }]);
});

test('nextTrialRows: tried upserts is_best=false; untried deletes', () => {
  const tried = nextTrialRows({ bestOptionId: null }, { id: 5, kind: 'device' }, 'tried');
  assert.deepEqual(tried.mutations, [{ action: 'upsert', optionId: 5, kind: 'device', isBest: false }]);

  const untried = nextTrialRows({ bestOptionId: 5 }, { id: 5, kind: 'device' }, 'untried');
  assert.deepEqual(untried.mutations, [{ action: 'delete', optionId: 5 }]);
});

test('impliedTrials: a recipe implies exactly one grind + one temp tried row', () => {
  const recipe = { kind: 'recipe', grindClicks: 28, waterTempC: 92 };
  const trials = impliedTrials(recipe);
  assert.equal(trials.length, 2);

  const grind = trials.filter((t) => t.kind === 'grind');
  const temp = trials.filter((t) => t.kind === 'temp');
  assert.equal(grind.length, 1);
  assert.equal(temp.length, 1);
  assert.equal(grind[0].valueNum, 28);
  assert.equal(temp[0].valueNum, 92);
  assert.ok(trials.every((t) => t.state === 'tried'), 'implied rows are tried, never best');
});

test('impliedTrials: a non-recipe option implies nothing', () => {
  assert.deepEqual(impliedTrials({ kind: 'device', grindClicks: null, waterTempC: null }), []);
  assert.deepEqual(impliedTrials(null), []);
});
