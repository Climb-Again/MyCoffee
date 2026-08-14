// worker.js's DB-touching orchestration (claim/lease, process a photo,
// run the SIGTERM-safe loop) needs a live Postgres, same as the manual
// end-to-end verification done for #19/#21 (see status/backend.md) -- it
// isn't part of this committed suite because CI has no DATABASE_URL
// (railway-deploy.yml's test job only runs `npm test` with none set, same as
// every other backend/test/*.test.js file). What's pure -- input_sha hashing,
// the extraction-due predicate, and the field-to-coffees-column mapping --
// is fully unit-tested here without any DB.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeInputSha, isDueForExtraction, buildCoffeeColumnUpdates } from '../src/lib/worker.js';

test('computeInputSha is deterministic and content-derived, not photo-id-derived', () => {
  const opts = {
    agent: 'extract_a',
    provider: 'vertex',
    model: 'gemini-2.5-pro',
    promptVersion: 'v1',
    imageSha: 'aaa',
    textSha: 'bbb',
    vocabVersion: 1,
  };
  assert.equal(computeInputSha(opts), computeInputSha({ ...opts }));
  assert.notEqual(computeInputSha(opts), computeInputSha({ ...opts, textSha: 'ccc' }));
  assert.notEqual(computeInputSha(opts), computeInputSha({ ...opts, vocabVersion: 2 }));
});

test('isDueForExtraction: a processed photo is never due again', () => {
  assert.equal(isDueForExtraction({ has_image: true, state: 'processed' }), false);
});

test('isDueForExtraction: no image yet is never due', () => {
  assert.equal(isDueForExtraction({ has_image: false, state: 'text_received' }), false);
});

test('isDueForExtraction: text_received with an image is due immediately', () => {
  assert.equal(isDueForExtraction({ has_image: true, state: 'text_received' }), true);
});

test('isDueForExtraction: awaiting_text is due only once the 10-day deadline passes', () => {
  const now = new Date('2026-01-15T00:00:00Z');
  const notYet = { has_image: true, state: 'awaiting_text', text_wait_until: '2026-01-20T00:00:00Z' };
  const overdue = { has_image: true, state: 'awaiting_text', text_wait_until: '2026-01-10T00:00:00Z' };
  assert.equal(isDueForExtraction(notYet, now), false);
  assert.equal(isDueForExtraction(overdue, now), true);
});

const vocabCtx = {
  vocab: {
    roasters: { candidates: [{ id: 1, name: 'DAK', country_id: 5 }] },
    countries: {
      candidates: [
        { id: 10, name: 'Ethiopia', is_origin: true },
        { id: 99, name: 'Blend', is_origin: true, kind: 'pseudo' },
      ],
    },
  },
  profileIdBySlug: new Map([['washed', 2]]),
  fxRates: [{ currency: 'RON', period: '2020-05-01', rateToEur: 0.2 }],
  photoDate: '2020-05-15',
};

test('buildCoffeeColumnUpdates: a bare-scalar field decided "absent" explicitly retracts the column (#49)', () => {
  // Regression for #49: re-adjudication can flip a field from a stale prior
  // `accepted` to `absent` (e.g. #39's new altitude/weight/rating sanity
  // envelopes rejecting a value a previous, looser pass had accepted). The
  // column must be SET to NULL, not silently left holding the old value.
  const { sets, values } = buildCoffeeColumnUpdates(
    { rating: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['rating = $1']);
  assert.deepEqual(values, [null]);
});

test('buildCoffeeColumnUpdates: altitude decided "absent" retracts both min and max (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { altitude: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['altitude_min_m = $1', 'altitude_max_m = $2']);
  assert.deepEqual(values, [null, null]);
});

test('buildCoffeeColumnUpdates: weight_g decided "absent" retracts the column (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { weight_g: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['weight_g = $1']);
  assert.deepEqual(values, [null]);
});

test('buildCoffeeColumnUpdates: price decided "absent" retracts all five price columns, no EUR conversion attempted (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { price: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, [
    'price_original_amount = $1',
    'price_original_currency = $2',
    'price_eur = $3',
    'fx_rate = $4',
    'fx_rate_period = $5',
  ]);
  assert.deepEqual(values, [null, null, null, null, null]);
});

test('buildCoffeeColumnUpdates: roaster_id decided "absent" retracts both roaster_id and its derived country (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { roaster_id: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [null, null]);
});

test('buildCoffeeColumnUpdates: origin_country_ids decided "absent" retracts both origin_country_ids and is_blend (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { origin_country_ids: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['origin_country_ids = $1', 'is_blend = $2']);
  assert.deepEqual(values, [null, null]);
});

test('buildCoffeeColumnUpdates: profile decided "absent" retracts profile_id, profile_detail, and is_decaf (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { profile: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['profile_id = $1', 'profile_detail = $2', 'is_decaf = $3']);
  assert.deepEqual(values, [null, null, null]);
});

test('buildCoffeeColumnUpdates: a field that was never voted on this pass is not a key in resolutions at all, and stays untouched', () => {
  // This is the OTHER half of #49's distinction -- a field absent from
  // `resolutions` entirely (no candidates were ever stored for it, e.g. the
  // caption never mentioned weight) must not be confused with a field
  // present with `decision: 'absent'`. Passing an empty resolutions object
  // models that case directly: nothing gets set.
  const { sets, values } = buildCoffeeColumnUpdates({}, vocabCtx);
  assert.deepEqual(sets, []);
  assert.deepEqual(values, []);
});

test('buildCoffeeColumnUpdates applies a "split" decision\'s provisional value too -- it is not skipped', () => {
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'split', value: 1 } }, vocabCtx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: roaster_id also denormalizes the roaster\'s country', () => {
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'accepted', value: 1 } }, vocabCtx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: roaster_country_id can be set directly, without a roaster_id edit', () => {
  // The generic edit endpoint (PLAN.md §12 #40) can edit the roaster's country
  // on its own, unlike normal extraction where it's only ever a side effect
  // of resolving roaster_id.
  const { sets, values } = buildCoffeeColumnUpdates(
    { roaster_country_id: { decision: 'accepted', value: 10 } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_country_id = $1']);
  assert.deepEqual(values, [10]);
});

test('buildCoffeeColumnUpdates: a later roaster_country_id resolution overrides roaster_id\'s derived one, not both', () => {
  // A batch edit (roaster + roaster country together, #42's edit sheet) must
  // never emit "roaster_country_id = $1, roaster_country_id = $2" -- Postgres
  // rejects multiple assignments to the same column. Object key order is the
  // tiebreak: the explicit roaster_country_id resolution, listed second here,
  // wins over roaster_id's derived one.
  const { sets, values } = buildCoffeeColumnUpdates(
    {
      roaster_id: { decision: 'accepted', value: 1 },
      roaster_country_id: { decision: 'accepted', value: 10 },
    },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 10]);
});

test('buildCoffeeColumnUpdates: origin_country_ids also computes is_blend and drops invalid ids', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { origin_country_ids: { decision: 'accepted', value: [10, 12345] } }, // 12345 isn't a real country id
    vocabCtx,
  );
  assert.deepEqual(sets, ['origin_country_ids = $1', 'is_blend = $2']);
  assert.deepEqual(values[0], [10]);
  assert.equal(values[1], false);
});

test('buildCoffeeColumnUpdates: price converts to EUR using the purchase-date rate, not a flat rate', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { price: { decision: 'accepted', value: { amount: 45, currency: 'RON' } } },
    vocabCtx,
  );
  assert.deepEqual(sets, [
    'price_original_amount = $1',
    'price_original_currency = $2',
    'price_eur = $3',
    'fx_rate = $4',
    'fx_rate_period = $5',
  ]);
  assert.equal(values[0], 45);
  assert.equal(values[1], 'RON');
  assert.equal(values[2], 9); // 45 * 0.2
});

test('buildCoffeeColumnUpdates: profile writes id (via slug lookup), detail, and is_decaf together', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { profile: { decision: 'accepted', value: { profileId: 'washed', isDecaf: false, detail: null } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['profile_id = $1', 'profile_detail = $2', 'is_decaf = $3']);
  assert.deepEqual(values, [2, null, false]);
});

test('buildCoffeeColumnUpdates: altitude writes both min and max', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { altitude: { decision: 'accepted', value: { min: 1300, max: 1600 } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['altitude_min_m = $1', 'altitude_max_m = $2']);
  assert.deepEqual(values, [1300, 1600]);
});
