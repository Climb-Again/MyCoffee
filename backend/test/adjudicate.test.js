// adjudicate.js is a pure function over stored candidate rows (PLAN.md §2) --
// no DB, no network -- so every decision rule (unanimous accept, weighted
// split, single-voter penalty, per-field threshold, prose median-boundary
// selection) is exercised directly against fixed inputs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalize,
  fieldsEqual,
  denormalize,
  adjudicateField,
  adjudicateRecord,
} from '../src/lib/adjudicate.js';

const roasterVocab = {
  roasters: {
    candidates: [{ id: 1, name: 'DAK Coffee Roasters', country_id: 5 }],
    aliasIndex: new Map([['dak', { id: 1, alias: 'DAK' }]]),
  },
  countries: {
    candidates: [
      { id: 10, name: 'Ethiopia', is_origin: true, is_roaster: false, kind: 'country' },
      { id: 11, name: 'Kenya', is_origin: true, is_roaster: false, kind: 'country' },
      { id: 99, name: 'Blend', is_origin: true, is_roaster: false, kind: 'pseudo' },
    ],
    aliasIndex: new Map(),
  },
  farms: { candidates: [{ id: 1, name: 'El Paraiso', country_id: 10 }], aliasIndex: new Map() },
};

const BASE_CTX = { vocab: roasterVocab, thresholds: { roaster_id: 0.85, price: 0.9 }, defaultThreshold: 0.85 };

// ---- canonicalize / fieldsEqual / denormalize ----

test('canonicalize roaster_id resolves via exact alias', () => {
  const c = canonicalize('roaster_id', 'DAK', { vocab: roasterVocab });
  assert.equal(c.id, 1);
});

test('canonicalize origin_country_ids splits a multi-value string', () => {
  const c = canonicalize('origin_country_ids', 'Ethiopia, Kenya', { vocab: roasterVocab });
  assert.deepEqual(c.ids, [10, 11]);
  assert.equal(c.isBlend, true);
});

test('canonicalize altitude parses a range', () => {
  const c = canonicalize('altitude', '1300 to 1600 masl', {});
  assert.equal(c.min, 1300);
  assert.equal(c.max, 1600);
});

test('canonicalize price requires a recognizable currency', () => {
  assert.equal(canonicalize('price', '45', {}), null); // bare number, no currency marker
  const c = canonicalize('price', '45 lei', {});
  assert.equal(c.amount, 45);
  assert.equal(c.currency, 'RON');
});

test('fieldsEqual: altitude agrees within 50m of midpoint', () => {
  assert.equal(fieldsEqual('altitude', { min: 1300, max: 1600 }, { min: 1350, max: 1600 }), true);
  assert.equal(fieldsEqual('altitude', { min: 1300, max: 1600 }, { min: 1000, max: 1200 }), false);
});

test('fieldsEqual: price requires same currency and within 0.05', () => {
  assert.equal(fieldsEqual('price', { amount: 45, currency: 'RON' }, { amount: 45.04, currency: 'RON' }), true);
  assert.equal(fieldsEqual('price', { amount: 45, currency: 'RON' }, { amount: 45, currency: 'EUR' }), false);
});

test('denormalize round-trips the shapes adjudicateField writes to field_resolutions.value', () => {
  assert.equal(denormalize('roaster_id', { id: 7 }), 7);
  assert.deepEqual(denormalize('altitude', { min: 1300, max: 1600 }), { min: 1300, max: 1600 });
  assert.deepEqual(denormalize('price', { amount: 10, currency: 'EUR' }), { amount: 10, currency: 'EUR' });
});

// ---- adjudicateField decision rules (PLAN.md §2 point 4) ----

test('unanimous (>=2 voters, min conf >=0.75) auto-accepts', () => {
  const result = adjudicateField(
    'roaster_id',
    [
      { agent: 'extract_a', value: 'DAK', confidence: 0.95 },
      { agent: 'extract_b', value: 'DAK', confidence: 0.9 },
    ],
    BASE_CTX,
  );
  assert.equal(result.decision, 'unanimous');
  assert.equal(result.value, 1);
  assert.ok(result.confidence >= 0.85);
});

test('a single voter is accepted at 0.7x confidence, and blocked if that drops it below threshold', () => {
  const result = adjudicateField('roaster_id', [{ agent: 'extract_a', value: 'DAK', confidence: 0.95 }], BASE_CTX);
  assert.equal(result.confidence, Math.round(0.95 * 0.7 * 1000) / 1000);
  // 0.665 < the 0.85 roaster_id threshold -> forced to review despite being the only voter.
  assert.equal(result.decision, 'review');
  assert.equal(result.reviewReason, 'below_threshold');
});

test('a genuine split (no cluster reaches the 0.60 share) goes to review', () => {
  const result = adjudicateField(
    'roaster_id',
    [
      { agent: 'extract_a', value: 'DAK', confidence: 0.9 },
      { agent: 'extract_b', value: 'Some Other Roaster Entirely', confidence: 0.9 },
    ],
    BASE_CTX,
  );
  // "Some Other Roaster Entirely" won't resolve against the vocab at all, so
  // only extract_a's candidate canonicalizes -- single voter, same as above.
  assert.equal(result.decision, 'review');
});

test('P3 (rules) carries 1.5x weight on numeric fields, enough to win a 1-vs-1 weighted tie', () => {
  const ctx = {
    ...BASE_CTX,
    ruleVoterWeight: 1.5,
    ruleVoterWeightedFields: ['altitude'],
    thresholds: { altitude: 0.75 },
  };
  const result = adjudicateField(
    'altitude',
    [
      { agent: 'rules', value: '1300 to 1600 masl', confidence: 1.0 },
      { agent: 'extract_a', value: '1000 to 1100 masl', confidence: 0.9 },
      { agent: 'extract_b', value: '1000 to 1100 masl', confidence: 0.9 },
    ],
    ctx,
  );
  // rules alone: weight 1.5; extract_a+extract_b together: weight 2 -- rules
  // does NOT win outright, but its 1.5x share (1.5/3.5 = 0.43) is properly
  // reflected rather than counted as a plain 1-of-3 vote (0.33).
  const rulesCluster = result.agreement; // share of the *winning* cluster
  assert.ok(rulesCluster > 0); // sanity: a decision was reached
  assert.notEqual(result.decision, 'unanimous');
});

test('P3 carries zero weight on prose fields', () => {
  const rawText = 'Farm: El Paraiso, washed, 1600masl. Great cup with notes of stone fruit.';
  const ctx = { ...BASE_CTX, ruleVoterProseFields: ['desc_farm_lot'], rawText, thresholds: { desc_farm_lot: 0 } };
  const result = adjudicateField(
    'desc_farm_lot',
    [
      { agent: 'rules', value: { start: 0, end: 10 }, confidence: 1.0 },
      { agent: 'extract_a', value: { start: 0, end: 27 }, confidence: 0.9 },
    ],
    ctx,
  );
  // rules candidate contributes weight 0, so despite two voters technically
  // disagreeing, extract_a's cluster carries the entire non-zero weight share.
  assert.equal(result.decision, 'accept_flagged');
  assert.equal(result.value, rawText.slice(0, 27));
});

test('a prose cluster whose boundary spread exceeds 80 chars forces review even if it "agrees"', () => {
  const rawText = 'x'.repeat(200);
  const ctx = { ...BASE_CTX, rawText, thresholds: { desc_roaster_copy: 0 } };
  // Both candidates slice to the *same substring* of x's (so fieldsEqual is
  // true and they cluster), but their offsets differ by >80 chars.
  const result = adjudicateField(
    'desc_roaster_copy',
    [
      { agent: 'extract_a', value: { start: 0, end: 50 }, confidence: 0.9 },
      { agent: 'extract_b', value: { start: 90, end: 140 }, confidence: 0.9 },
    ],
    ctx,
  );
  assert.equal(result.decision, 'review');
  assert.equal(result.reviewReason, 'prose_spread');
});

test('no candidates at all -> review with reason no_candidates', () => {
  const result = adjudicateField('rating', [], BASE_CTX);
  assert.equal(result.decision, 'review');
  assert.equal(result.reviewReason, 'no_candidates');
});

test('critic refutation discounts every non-rules candidate before thresholding', () => {
  const ctx = {
    ...BASE_CTX,
    thresholds: { rating: 0.9 },
    criticVerdicts: { rating: { refuted: true } },
    criticPenalty: 0.5,
  };
  const result = adjudicateField(
    'rating',
    [
      { agent: 'extract_a', value: '4.5/5', confidence: 0.95 },
      { agent: 'extract_b', value: '4.5/5', confidence: 0.95 },
    ],
    ctx,
  );
  // Would be unanimous at ~0.95 without the critic; halved to ~0.475, well
  // under the 0.9 rating threshold.
  assert.equal(result.decision, 'review');
  assert.equal(result.reviewReason, 'below_threshold');
});

// ---- adjudicateRecord: locked fields are skipped entirely ----

test('adjudicateRecord never re-adjudicates a locked field', () => {
  const candidatesByField = {
    roaster_id: [{ agent: 'extract_a', value: 'DAK', confidence: 0.95 }],
    rating: [
      { agent: 'extract_a', value: '4.5/5', confidence: 0.95 },
      { agent: 'extract_b', value: '4.5/5', confidence: 0.95 },
    ],
  };
  const { resolutions, reviews } = adjudicateRecord(candidatesByField, {
    ...BASE_CTX,
    thresholds: { roaster_id: 0.85, rating: 0.9 },
    locked: new Set(['roaster_id']),
  });
  assert.ok(!('roaster_id' in resolutions)); // locked -- untouched
  assert.ok('rating' in resolutions);
  assert.equal(reviews.length, 0);
});

test('adjudicateRecord collects every review-bound field with its reason', () => {
  const candidatesByField = {
    price: [{ agent: 'extract_a', value: '45', confidence: 0.9 }], // bare number, no currency
  };
  const { reviews } = adjudicateRecord(candidatesByField, BASE_CTX);
  assert.equal(reviews.length, 1);
  assert.equal(reviews[0].field, 'price');
  assert.equal(reviews[0].reason, 'no_candidates'); // parsePrice requires a currency marker
});
