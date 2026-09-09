// #160 POST /api/score -- the browsing score. Covers the two pieces that are
// new rather than reused: the roast-recency curve (#159's one unvalidated
// factor, so its bounds matter) and the explanation text, which must never
// contradict the numbers beside it.
//
// The route's scoring path is deliberately NOT re-tested here: it is
// `evaluateCoffee` from lib/scoring.js, already covered by scoring.test.js,
// reached through lib/corpus.js. That is the point of the shared loader --
// there is one scorer to test, not two.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  daysSinceRoast,
  roastRecencyScore,
  applyRoastRecency,
  ROAST_FRESH_DAYS,
  ROAST_STALE_DAYS,
  ROAST_RECENCY_WEIGHT,
} from '../src/lib/scoring.js';
import { explain } from '../src/routes/score.js';

const DAY = 86_400_000;

test('daysSinceRoast: whole days back from now', () => {
  const now = Date.UTC(2026, 8, 9);
  assert.equal(daysSinceRoast('2026-09-09', now), 0);
  assert.equal(daysSinceRoast('2026-09-02', now), 7);
  assert.equal(daysSinceRoast(new Date(now - 30 * DAY), now), 30);
});

test('daysSinceRoast: unknown or unparseable is null, never a number', () => {
  assert.equal(daysSinceRoast(null), null);
  assert.equal(daysSinceRoast(undefined), null);
  assert.equal(daysSinceRoast(''), null);
  assert.equal(daysSinceRoast('not a date'), null);
});

test('daysSinceRoast: a future roast date clamps to 0, not negative', () => {
  const now = Date.UTC(2026, 8, 9);
  // Shop pre-orders really do carry these.
  assert.equal(daysSinceRoast('2026-09-20', now), 0);
});

test('roastRecencyScore: full marks through the fresh window, zero at stale', () => {
  assert.equal(roastRecencyScore(0), 100);
  assert.equal(roastRecencyScore(ROAST_FRESH_DAYS), 100);
  assert.equal(roastRecencyScore(ROAST_STALE_DAYS), 0);
  assert.equal(roastRecencyScore(ROAST_STALE_DAYS + 500), 0);
});

test('roastRecencyScore: monotonic decay between fresh and stale (Radu: closer to today is better)', () => {
  let prev = 101;
  for (let d = ROAST_FRESH_DAYS; d <= ROAST_STALE_DAYS; d += 7) {
    const score = roastRecencyScore(d);
    assert.ok(score <= prev, `score rose at ${d} days: ${score} > ${prev}`);
    assert.ok(score >= 0 && score <= 100);
    prev = score;
  }
});

test('roastRecencyScore: no roast date scores null, so it is dropped rather than penalised', () => {
  assert.equal(roastRecencyScore(null), null);
  assert.equal(roastRecencyScore(undefined), null);
  assert.equal(roastRecencyScore(NaN), null);
});

test('applyRoastRecency: unknown recency leaves the headline exactly as it was', () => {
  // The whole point of "neutral, not penalised" (#159).
  assert.equal(applyRoastRecency(72, null), 72);
});

test('applyRoastRecency: a suppressed headline stays suppressed', () => {
  assert.equal(applyRoastRecency(null, 100), null);
  assert.equal(applyRoastRecency(null, 0), null);
});

test('applyRoastRecency: influence is bounded by ROAST_RECENCY_WEIGHT', () => {
  // #159 requires this factor stay small: it is the one signal with no
  // leave-one-out validation behind it.
  const base = 50;
  const best = applyRoastRecency(base, 100);
  const worst = applyRoastRecency(base, 0);
  assert.equal(best - worst, Math.round(100 * ROAST_RECENCY_WEIGHT));
  assert.ok(best <= base + 100 * ROAST_RECENCY_WEIGHT);
  assert.ok(worst >= base - 100 * ROAST_RECENCY_WEIGHT);
});

test('applyRoastRecency: a fresh bag is nudged up, a stale one down', () => {
  assert.ok(applyRoastRecency(60, roastRecencyScore(3)) > 60);
  assert.ok(applyRoastRecency(60, roastRecencyScore(175)) < 60);
});

// ---- explanation ----

const baseEval = {
  score: 64,
  confidence: 'normal',
  components: {
    affinity: { score: 80, raw: 4.12 },
    value: { score: 60, pillCount: 3, band: 2, bandN: 9 },
    novelty: { isNewRoaster: false, isNewOrigin: false },
  },
};

test('explain: says the value half is missing when there was no price', () => {
  const text = explain({
    evaluation: { ...baseEval, score: null, components: { ...baseEval.components, value: null } },
    recency: null,
    days: null,
    fields: { pricePer100gEur: null, isNewRoaster: false, isNewOrigin: false },
    names: { roaster: 'Gardelli', origin: 'Ethiopia' },
  });
  assert.match(text, /no usable price/i);
  // Must not claim a number it did not produce.
  assert.doesNotMatch(text, /\b\d{1,3}%\s*fit/i);
});

test('explain: low confidence explains the suppressed headline', () => {
  const text = explain({
    evaluation: { ...baseEval, score: null, confidence: 'low' },
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: true, isNewOrigin: true },
    names: { roaster: 'Some Roaster', origin: 'Peru' },
  });
  assert.match(text, /too little history/i);
});

test('explain: names a new roaster as new and a known one as known', () => {
  const known = explain({
    evaluation: baseEval,
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: false, isNewOrigin: false },
    names: { roaster: 'Gardelli', origin: 'Ethiopia' },
  });
  assert.match(known, /bought Gardelli before/i);

  const fresh = explain({
    evaluation: baseEval,
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: true, isNewOrigin: true },
    names: { roaster: 'DAK', origin: 'Peru' },
  });
  assert.match(fresh, /haven't bought from/i);
  assert.match(fresh, /new origin/i);
});

test('explain: mentions roast age only when the page carried a date', () => {
  const dated = explain({
    evaluation: baseEval,
    recency: 100,
    days: 5,
    fields: { pricePer100gEur: 8.5, isNewRoaster: false, isNewOrigin: false },
    names: { roaster: 'Gardelli', origin: 'Ethiopia' },
  });
  assert.match(dated, /roasted 5 days ago/i);

  const undated = explain({
    evaluation: baseEval,
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: false, isNewOrigin: false },
    names: { roaster: 'Gardelli', origin: 'Ethiopia' },
  });
  assert.doesNotMatch(undated, /roasted/i);
});

test('explain: singular day, because "roasted 1 days ago" is what tells you nobody read it', () => {
  const text = explain({
    evaluation: baseEval,
    recency: 100,
    days: 1,
    fields: { pricePer100gEur: 8.5, isNewRoaster: false, isNewOrigin: false },
    names: { roaster: 'Gardelli', origin: 'Ethiopia' },
  });
  assert.match(text, /roasted 1 day ago/);
});

test('explain: never returns an empty string, even with nothing recognised', () => {
  const text = explain({
    evaluation: { score: null, confidence: 'low', components: { affinity: { score: 50, raw: 4 }, value: null, novelty: {} } },
    recency: null,
    days: null,
    fields: { pricePer100gEur: null, isNewRoaster: true, isNewOrigin: true },
    names: { roaster: null, origin: null },
  });
  assert.ok(text.length > 0);
  assert.match(text, /\.$/);
});

test('explain: stays silent about novelty the page never established', () => {
  // Regression: the first live /api/score call was a Congo coffee whose origin
  // the vocab cannot resolve (#165). Novelty came back `true` and the sentence
  // would have called an unreadable origin "new". Unknown must say nothing.
  const text = explain({
    evaluation: baseEval,
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: false, isNewOrigin: null },
    names: { roaster: 'Gardelli', origin: 'Congo' },
  });
  assert.doesNotMatch(text, /new origin/i);
  assert.doesNotMatch(text, /familiar ground/i);
  // The roaster half is known, so it still speaks.
  assert.match(text, /bought Gardelli before/i);
});

test('explain: stays silent about an unknown roaster too', () => {
  const text = explain({
    evaluation: baseEval,
    recency: null,
    days: null,
    fields: { pricePer100gEur: 8.5, isNewRoaster: null, isNewOrigin: false },
    names: { roaster: null, origin: 'Ethiopia' },
  });
  assert.doesNotMatch(text, /roaster you haven't bought/i);
  assert.match(text, /Ethiopia is familiar ground/i);
});
