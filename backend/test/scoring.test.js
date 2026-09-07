// scoring.js: pure math for "Evaluate this coffee" (#106). The blend weights
// and price-band bucketing are checked against the real production corpus
// (fetched live via GET /api/snapshot, per CLAUDE.md §7) in status/backend.md
// — this file covers the pure functions in isolation with small synthetic
// fixtures, same convention as fx.test.js.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  shrunkMean,
  blendAffinity,
  confidenceFor,
  percentileRank,
  priceBandFor,
  pillCountFromDelta,
  evaluateCoffee,
  typicalGapDays,
  rotationScoreFor,
  rankRotationCandidates,
  rotationReason,
  ROTATION_MIN_N,
  ROTATION_GAP_FLOOR_DAYS,
  ROTATION_OVERDUE_CAP,
} from '../src/lib/scoring.js';

test('shrunkMean pulls toward the global mean, harder at low n', () => {
  assert.equal(shrunkMean(0, 5, 4), 4); // no evidence -> global mean outright
  assert.equal(shrunkMean(5, 5, 4), 4.5); // n == k -> halfway
  const largeN = shrunkMean(500, 5, 4);
  assert.ok(largeN > 4.9); // huge n barely shrinks at all
});

test('blendAffinity falls back to global mean when every signal is unseen', () => {
  assert.equal(blendAffinity({}, 4.03), 4.03);
});

test('blendAffinity weights a well-evidenced signal over a thin one', () => {
  const wellEvidenced = blendAffinity(
    { roaster: { n: 40, mean: 4.5 } }, // one strong signal, well above the mean
    4.0,
  );
  const thin = blendAffinity(
    { roasterCountry: { n: 1, mean: 4.5 } }, // same raw mean, barely any evidence
    4.0,
  );
  assert.ok(wellEvidenced > thin, 'more evidence should pull the estimate further from the mean');
  assert.ok(wellEvidenced > 4.0 && wellEvidenced < 4.5);
});

test('confidenceFor: low only when origin, roaster AND process are all thin', () => {
  assert.equal(confidenceFor({}), 'low');
  assert.equal(confidenceFor({ origin: { n: 2 }, roaster: { n: 3 }, process: { n: 4 } }), 'low');
  // roasterCountry is well-evidenced but doesn't count toward the gate
  assert.equal(confidenceFor({ origin: { n: 1 }, roasterCountry: { n: 100 } }), 'low');
  assert.equal(confidenceFor({ roaster: { n: 5 } }), 'normal'); // one signal clears the ~5 threshold
});

test('percentileRank uses the full range, not a compressed tail', () => {
  const samples = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  assert.equal(percentileRank(1, samples), 10);
  assert.equal(percentileRank(10, samples), 100);
  assert.equal(percentileRank(5, samples), 50);
  assert.equal(percentileRank(0, []), 50); // no corpus at all -> neutral
});

test('priceBandFor buckets ascending by price, band 1 cheapest', () => {
  const priced = Array.from({ length: 20 }, (_, i) => ({ pricePer100gEur: i + 1, rating: 4 }));
  assert.equal(priceBandFor(1, priced).index, 1);
  assert.equal(priceBandFor(20, priced).index, 5);
  assert.equal(priceBandFor(null, priced), null);
  assert.equal(priceBandFor(5, []), null);
});

test('priceBandFor: cheap band mean vs a pricier band mean, real-shaped fixture', () => {
  // Mirrors the corpus's own real shape (status/backend.md): cheap bags rate
  // lower on average than the mid-price bands.
  const cheap = Array.from({ length: 10 }, () => ({ pricePer100gEur: 5, rating: 3.9 }));
  const mid = Array.from({ length: 10 }, () => ({ pricePer100gEur: 10, rating: 4.3 }));
  const priced = [...cheap, ...mid];
  assert.ok(priceBandFor(5, priced).mean < priceBandFor(10, priced).mean);
});

test('pillCountFromDelta: the ±0.10 / ±0.30 cutoffs #105 measured', () => {
  assert.equal(pillCountFromDelta(-0.5), 1);
  assert.equal(pillCountFromDelta(-0.3), 1);
  assert.equal(pillCountFromDelta(-0.2), 2);
  assert.equal(pillCountFromDelta(0), 3);
  assert.equal(pillCountFromDelta(0.2), 4);
  assert.equal(pillCountFromDelta(0.3), 5);
  assert.equal(pillCountFromDelta(0.5), 5);
});

test('evaluateCoffee suppresses the headline number under low confidence', () => {
  const priced = Array.from({ length: 25 }, (_, i) => ({ pricePer100gEur: i + 1, rating: 4 }));
  const result = evaluateCoffee({
    groups: {}, // everything unseen
    globalMean: 4,
    priced,
    affinitySamples: [3.8, 4.0, 4.2],
    pricePer100gEur: 6,
    isNewRoaster: true,
    isNewOrigin: true,
  });
  assert.equal(result.confidence, 'low');
  assert.equal(result.score, null);
  assert.ok(result.components.affinity); // components still shown per #106's spec
  assert.ok(result.components.value);
});

test('evaluateCoffee suppresses the headline number with no price at all', () => {
  const result = evaluateCoffee({
    groups: { roaster: { n: 40, mean: 4.4 } },
    globalMean: 4,
    priced: [{ pricePer100gEur: 6, rating: 4 }],
    affinitySamples: [3.8, 4.0, 4.2],
    pricePer100gEur: null,
    isNewRoaster: false,
    isNewOrigin: false,
  });
  assert.equal(result.score, null);
  assert.equal(result.components.value, null);
});

test('evaluateCoffee: well-evidenced + priced draft gets a headline number in range', () => {
  const priced = Array.from({ length: 25 }, (_, i) => ({ pricePer100gEur: (i + 1) * 2, rating: 3.8 + (i % 5) * 0.1 }));
  const affinitySamples = Array.from({ length: 50 }, (_, i) => 3.5 + (i / 49) * 1.0).sort((a, b) => a - b);
  const result = evaluateCoffee({
    groups: {
      origin: { n: 30, mean: 4.3 },
      roaster: { n: 40, mean: 4.4 },
      process: { n: 100, mean: 4.1 },
    },
    globalMean: 4.0,
    priced,
    affinitySamples,
    pricePer100gEur: 8,
    isNewRoaster: false,
    isNewOrigin: false,
  });
  assert.equal(result.confidence, 'normal');
  assert.ok(Number.isInteger(result.score));
  assert.ok(result.score >= 0 && result.score <= 100);
  assert.equal(result.components.novelty.isNewRoaster, false);
  assert.equal(result.components.novelty.isNewOrigin, false);
});

// "What to buy next" rotation recommendation (#107). Pure math only, same
// synthetic-fixture convention as the #106 tests above.
const DAY_MS = 86_400_000;

test('typicalGapDays: large n barely shrinks toward the global cadence', () => {
  const dates = Array.from({ length: 51 }, (_, i) => i * 30 * DAY_MS); // 50 gaps of 30 days
  const gap = typicalGapDays(dates, 4.5);
  assert.ok(gap > 25 && gap < 30, `expected close to 30, got ${gap}`);
});

test('typicalGapDays: a single gap floors at ROTATION_GAP_FLOOR_DAYS rather than trusting it outright', () => {
  const dates = [0, 14 * DAY_MS];
  assert.equal(typicalGapDays(dates, 4.5), ROTATION_GAP_FLOOR_DAYS);
});

test('typicalGapDays: a single purchase (no gap at all) falls back to the global cadence, floored', () => {
  assert.equal(typicalGapDays([0], 4.5), ROTATION_GAP_FLOOR_DAYS);
});

test('rotationScoreFor returns null below ROTATION_MIN_N', () => {
  const result = rotationScoreFor({
    n: ROTATION_MIN_N - 1,
    mean: 4.5,
    globalMean: 4.0,
    purchaseDatesAscending: [0],
    lastPurchaseAt: 0,
    globalGapDays: 30,
    now: 100 * DAY_MS,
  });
  assert.equal(result, null);
});

test('rotationScoreFor: affinity can go negative, so staleness alone never rescues a below-average entity', () => {
  const n = 20;
  const gapDays = 40;
  const purchaseDatesAscending = Array.from({ length: n }, (_, i) => i * gapDays * DAY_MS);
  const lastPurchaseAt = purchaseDatesAscending[n - 1];
  const result = rotationScoreFor({
    n,
    mean: 3.78, // below the global mean -- #107's own "April" example
    globalMean: 4.03,
    purchaseDatesAscending,
    lastPurchaseAt,
    globalGapDays: 4.5,
    now: lastPurchaseAt + 25 * gapDays * DAY_MS, // heavily overdue
  });
  assert.ok(result.affinity < 4.03);
  assert.ok(result.z < 0);
  assert.ok(result.overdue > 1, 'should read as overdue');
  assert.ok(result.score < 0, 'a merely stale, below-average entity must not score positively');
});

test('rotationScoreFor caps overdue at ROTATION_OVERDUE_CAP', () => {
  const n = 10;
  const gapDays = 20;
  const purchaseDatesAscending = Array.from({ length: n }, (_, i) => i * gapDays * DAY_MS);
  const lastPurchaseAt = purchaseDatesAscending[n - 1];
  const result = rotationScoreFor({
    n,
    mean: 4.5,
    globalMean: 4.0,
    purchaseDatesAscending,
    lastPurchaseAt,
    globalGapDays: 4.5,
    now: lastPurchaseAt + 100 * gapDays * DAY_MS, // absurdly overdue
  });
  assert.equal(result.overdue, ROTATION_OVERDUE_CAP);
});

test('rankRotationCandidates: ranks across entity kinds descending, excludes thin entities, respects limit', () => {
  const now = 2000 * DAY_MS;
  const makeCandidate = (entity, id, name, n, mean, gapDays, daysSinceLast) => {
    const lastPurchaseAt = now - daysSinceLast * DAY_MS;
    const purchaseDatesAscending = Array.from(
      { length: n },
      (_, i) => lastPurchaseAt - (n - 1 - i) * gapDays * DAY_MS,
    );
    return { entity, id, name, n, mean, purchaseDatesAscending, lastPurchaseAt };
  };
  const candidates = [
    makeCandidate('roaster', 1, 'Well-liked and overdue', 10, 4.8, 30, 300),
    makeCandidate('originCountry', 2, 'Too few rated bags', 3, 5.0, 10, 500),
    makeCandidate('process', 3, 'Below average and stale', 10, 3.5, 30, 300),
    makeCandidate('roaster', 4, 'Well-liked but recent', 10, 4.8, 30, 5),
  ];
  const ranked = rankRotationCandidates(candidates, { globalMean: 4.0, globalGapDays: 4.5, limit: 2, now });
  assert.equal(ranked.length, 2);
  assert.equal(ranked[0].name, 'Well-liked and overdue');
  assert.ok(ranked.every((r) => r.name !== 'Too few rated bags'), 'n < ROTATION_MIN_N must be excluded');
  assert.ok(ranked[0].score > ranked[1].score);
});

test('rotationReason formats the worked example from #107', () => {
  const reason = rotationReason({ affinity: 4.21, n: 11, daysSinceLast: 92, typicalGapDays: 38 });
  assert.equal(reason, '4.21 over 11 bags, 92 days since the last one vs your usual 38');
});

test('rotationReason: singular "bag" for n=1', () => {
  const reason = rotationReason({ affinity: 4.0, n: 1, daysSinceLast: 10, typicalGapDays: 14 });
  assert.match(reason, /1 bag,/);
});
