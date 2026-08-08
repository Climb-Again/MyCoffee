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
    candidates: [
      { id: 1, name: 'DAK Coffee Roasters', country_id: 5 },
      { id: 2, name: 'Little Roasters', country_id: 6 },
    ],
    aliasIndex: new Map([
      ['dak', { id: 1, alias: 'DAK' }],
      ['little roasters', { id: 2, alias: 'Little Roasters' }],
    ]),
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

const BASE_CTX = { vocab: roasterVocab };

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

// ---- adjudicateField decision rules: accept-by-default (PLAN.md §11) ----

test('agreeing candidates (>=2 voters, single cluster) are accepted', () => {
  const result = adjudicateField(
    'roaster_id',
    [
      { agent: 'extract_a', value: 'DAK', confidence: 0.95 },
      { agent: 'extract_b', value: 'DAK', confidence: 0.9 },
    ],
    BASE_CTX,
  );
  assert.equal(result.decision, 'accepted');
  assert.equal(result.value, 1);
  assert.equal(result.reviewReason, null);
});

test('a single voter is accepted regardless of confidence -- no penalty, no threshold', () => {
  const result = adjudicateField('roaster_id', [{ agent: 'extract_a', value: 'DAK', confidence: 0.1 }], BASE_CTX);
  assert.equal(result.decision, 'accepted');
  assert.equal(result.value, 1);
  // Confidence is still reported (for display / min_field_confidence) but no
  // longer discounted or used to gate the decision.
  assert.equal(result.confidence, 0.1);
});

test('an unresolvable second candidate leaves a single resolvable one -- still accepted', () => {
  const result = adjudicateField(
    'roaster_id',
    [
      { agent: 'extract_a', value: 'DAK', confidence: 0.9 },
      { agent: 'extract_b', value: 'Some Other Roaster Entirely', confidence: 0.9 },
    ],
    BASE_CTX,
  );
  // "Some Other Roaster Entirely" won't resolve against the vocab at all, so
  // only extract_a's candidate canonicalizes -- single voter, accepted.
  assert.equal(result.decision, 'accepted');
  assert.equal(result.value, 1);
});

test('a genuine split -- two voters resolving to different real roasters -- goes to review, but still applies the top pick', () => {
  const result = adjudicateField(
    'roaster_id',
    [
      { agent: 'extract_a', value: 'DAK', confidence: 0.9 },
      { agent: 'extract_b', value: 'Little Roasters', confidence: 0.9 },
    ],
    BASE_CTX,
  );
  assert.equal(result.decision, 'split');
  assert.equal(result.reviewReason, 'split');
  // Provisional: the top-weighted (here, either -- a 1-vs-1 tie keeps
  // whichever cluster formed first) pick is still written, not left null.
  assert.ok([1, 2].includes(result.value));
});

test('P3 (rules) carries 1.5x weight on numeric fields -- a materially different value from 2 LLM voters is still a real split', () => {
  const ctx = {
    ...BASE_CTX,
    ruleVoterWeight: 1.5,
    ruleVoterWeightedFields: ['altitude'],
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
  // reflected rather than counted as a plain 1-of-3 vote (0.33). Two
  // materially different altitude ranges is a genuine split.
  assert.equal(result.decision, 'split');
  assert.ok(result.agreement > 0.5); // the extract_a/extract_b cluster (weight 2) wins the share
  assert.deepEqual(result.value, { min: 1000, max: 1100 });
});

test('P3 carries zero weight on prose fields -- a zero-weight disagreement is not a real split', () => {
  const rawText = 'Farm: El Paraiso, washed, 1600masl. Great cup with notes of stone fruit.';
  const ctx = { ...BASE_CTX, ruleVoterProseFields: ['desc_farm_lot'], rawText };
  const result = adjudicateField(
    'desc_farm_lot',
    [
      { agent: 'rules', value: { start: 0, end: 10 }, confidence: 1.0 },
      { agent: 'extract_a', value: { start: 0, end: 27 }, confidence: 0.9 },
    ],
    ctx,
  );
  // rules candidate contributes weight 0, so despite two voters technically
  // disagreeing, extract_a's cluster is the only one with real weight.
  assert.equal(result.decision, 'accepted');
  assert.equal(result.value, rawText.slice(0, 27));
});

test('a prose cluster whose boundary spread exceeds 80 chars forces review even if it "agrees"', () => {
  const rawText = 'x'.repeat(200);
  const ctx = { ...BASE_CTX, rawText };
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
  assert.equal(result.decision, 'split');
  assert.equal(result.reviewReason, 'prose_spread');
  assert.ok(result.value); // still applied provisionally, not left null
});

test('no candidates at all -> "absent", not a review item', () => {
  const result = adjudicateField('rating', [], BASE_CTX);
  assert.equal(result.decision, 'absent');
  assert.equal(result.reviewReason, null);
  assert.equal(result.value, null);
});

test('critic refutation discounts confidence but does not force review for an agreeing cluster', () => {
  const ctx = {
    ...BASE_CTX,
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
  // Halved to ~0.475 by the critic, but confidence no longer gates the
  // decision -- both voters still agree, so it's accepted.
  assert.equal(result.decision, 'accepted');
  assert.ok(result.confidence < 0.5);
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
    locked: new Set(['roaster_id']),
  });
  assert.ok(!('roaster_id' in resolutions)); // locked -- untouched
  assert.ok('rating' in resolutions);
  assert.equal(reviews.length, 0);
});

test('adjudicateRecord collects only genuinely split fields, with a reason', () => {
  const candidatesByField = {
    price: [{ agent: 'extract_a', value: '45', confidence: 0.9 }], // bare number, no currency -> absent, not a review
    roaster_id: [
      { agent: 'extract_a', value: 'DAK', confidence: 0.9 },
      { agent: 'extract_b', value: 'Little Roasters', confidence: 0.9 },
    ],
  };
  const { resolutions, reviews } = adjudicateRecord(candidatesByField, BASE_CTX);
  assert.equal(resolutions.price.decision, 'absent');
  assert.equal(reviews.length, 1);
  assert.equal(reviews[0].field, 'roaster_id');
  assert.equal(reviews[0].reason, 'split');
});
