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

test('buildCoffeeColumnUpdates skips a field with no value (absent, or a review with no trustworthy pick)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { rating: { decision: 'review', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, []);
  assert.deepEqual(values, []);
});

test('buildCoffeeColumnUpdates applies a provisional split pick even though the field still needs review (PLAN.md §11)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { roaster_id: { decision: 'review', reviewReason: 'split', value: 1 } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: roaster_id also denormalizes the roaster\'s country', () => {
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'unanimous', value: 1 } }, vocabCtx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: origin_country_ids also computes is_blend and drops invalid ids', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { origin_country_ids: { decision: 'unanimous', value: [10, 12345] } }, // 12345 isn't a real country id
    vocabCtx,
  );
  assert.deepEqual(sets, ['origin_country_ids = $1', 'is_blend = $2']);
  assert.deepEqual(values[0], [10]);
  assert.equal(values[1], false);
});

test('buildCoffeeColumnUpdates: price converts to EUR using the purchase-date rate, not a flat rate', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { price: { decision: 'unanimous', value: { amount: 45, currency: 'RON' } } },
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
    { profile: { decision: 'unanimous', value: { profileId: 'washed', isDecaf: false, detail: null } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['profile_id = $1', 'profile_detail = $2', 'is_decaf = $3']);
  assert.deepEqual(values, [2, null, false]);
});

test('buildCoffeeColumnUpdates: altitude writes both min and max', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { altitude: { decision: 'accept_flagged', value: { min: 1300, max: 1600 } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['altitude_min_m = $1', 'altitude_max_m = $2']);
  assert.deepEqual(values, [1300, 1600]);
});
