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
import { readFileSync } from 'node:fs';
import {
  daysSinceRoast,
  roastRecencyScore,
  ROAST_FRESH_DAYS,
  ROAST_STALE_DAYS,
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

// ---- #188: the reweighted blend and the stale-roast penalty ----
//
// Radu, 2026-09-10: "weight more on the roaster, origin country, process,
// roasting date. If roasting date older than 40d penalize with extra 10
// points." This deliberately overrides what the corpus measurement suggests
// (#106 found value the only reliable component); it is his call, and these
// tests exist so nobody quietly reverts it to the r-values.
import { evaluateCoffee, noveltyScore, FINAL_WEIGHTS, STALE_ROAST_DAYS, STALE_ROAST_PENALTY } from '../src/lib/scoring.js';

const NOW = Date.UTC(2026, 8, 10);
const ago = (d) => new Date(NOW - d * 86_400_000).toISOString().slice(0, 10);

// A fixture that reliably produces a headline: enough rated bags per signal
// for `normal` confidence, and a price band with enough members to be trusted.
const priced = Array.from({ length: 40 }, (_, i) => ({ pricePer100gEur: 4 + i * 0.4, rating: 3.5 + (i % 5) * 0.2 }));
const fixture = (over = {}) => ({
  groups: { roaster: { n: 10, mean: 4.2 }, origin: { n: 10, mean: 4.1 }, process: { n: 10, mean: 4.0 } },
  globalMean: 4,
  priced,
  affinitySamples: Array.from({ length: 100 }, (_, i) => 3.5 + i / 100),
  pricePer100gEur: 8,
  isNewRoaster: false,
  isNewOrigin: false,
  now: NOW,
  ...over,
});

test('the weights are Radu\'s ratios (#189): affinity 50 / roast 20 / value 15 / novelty 10', () => {
  assert.equal(FINAL_WEIGHTS.affinity, 0.5);
  assert.equal(FINAL_WEIGHTS.roast, 0.2);
  assert.equal(FINAL_WEIGHTS.value, 0.15);
  assert.equal(FINAL_WEIGHTS.novelty, 0.1);
  // They sum to 0.95 on purpose -- the blend renormalises, so the RATIO is
  // what carries, and rounding to 1 would mean inventing a digit he didn't give.
  assert.ok(Math.abs(Object.values(FINAL_WEIGHTS).reduce((a, b) => a + b, 0) - 0.95) < 1e-9);
  assert.ok(FINAL_WEIGHTS.affinity > FINAL_WEIGHTS.roast);
  assert.ok(FINAL_WEIGHTS.roast > FINAL_WEIGHTS.value);
  assert.ok(FINAL_WEIGHTS.value > FINAL_WEIGHTS.novelty);
});

test('novelty is directional now: new scores higher than familiar', () => {
  // #189 reverses #106's "neither good nor bad". A weighted term has to point
  // somewhere, and for a what-do-I-buy-next tool it points at the unfamiliar.
  const familiar = evaluateCoffee(fixture({ isNewRoaster: false, isNewOrigin: false, roastedOn: ago(5) }));
  const oneNew = evaluateCoffee(fixture({ isNewRoaster: true, isNewOrigin: false, roastedOn: ago(5) }));
  const bothNew = evaluateCoffee(fixture({ isNewRoaster: true, isNewOrigin: true, roastedOn: ago(5) }));

  assert.ok(bothNew.score > oneNew.score, `${bothNew.score} should beat ${oneNew.score}`);
  assert.ok(oneNew.score > familiar.score, `${oneNew.score} should beat ${familiar.score}`);
  // Bounded by its weight: a tenth of the blend cannot swing the headline more
  // than about ten points.
  assert.ok(bothNew.score - familiar.score <= 12, `swing was ${bothNew.score - familiar.score}`);
});

test('noveltyScore is the plain 0 / 50 / 100 it claims to be', () => {
  assert.equal(noveltyScore({ isNewRoaster: true, isNewOrigin: true }), 100);
  assert.equal(noveltyScore({ isNewRoaster: true, isNewOrigin: false }), 50);
  assert.equal(noveltyScore({ isNewRoaster: false, isNewOrigin: true }), 50);
  assert.equal(noveltyScore({}), 0);
  assert.equal(noveltyScore(), 0);
});

test('affinity moves the headline more than any other component', () => {
  // The whole point of #189: affinity is the measured predictor (r≈0.39), so
  // it should dominate. Swinging each component end to end, affinity wins.
  const lowAff = { groups: { roaster: { n: 30, mean: 3.0 }, origin: { n: 30, mean: 3.0 }, process: { n: 30, mean: 3.0 } } };
  const highAff = { groups: { roaster: { n: 30, mean: 4.9 }, origin: { n: 30, mean: 4.9 }, process: { n: 30, mean: 4.9 } } };
  const affSwing =
    evaluateCoffee(fixture({ ...highAff, roastedOn: ago(5) })).score -
    evaluateCoffee(fixture({ ...lowAff, roastedOn: ago(5) })).score;

  const roastSwing =
    evaluateCoffee(fixture({ roastedOn: ago(0) })).score - evaluateCoffee(fixture({ roastedOn: ago(180) })).score;
  const noveltySwing =
    evaluateCoffee(fixture({ isNewRoaster: true, isNewOrigin: true, roastedOn: ago(5) })).score -
    evaluateCoffee(fixture({ roastedOn: ago(5) })).score;

  assert.ok(affSwing > roastSwing, `affinity ${affSwing} must outweigh roast ${roastSwing}`);
  assert.ok(affSwing > noveltySwing, `affinity ${affSwing} must outweigh novelty ${noveltySwing}`);
});

test('a fresh roast scores higher than a middle-aged one', () => {
  const fresh = evaluateCoffee(fixture({ roastedOn: ago(3) })).score;
  const older = evaluateCoffee(fixture({ roastedOn: ago(35) })).score;
  assert.ok(fresh > older, `${fresh} should beat ${older}`);
});

test('crossing 40 days costs the flat penalty on top of the decay', () => {
  const before = evaluateCoffee(fixture({ roastedOn: ago(STALE_ROAST_DAYS - 1) }));
  const after = evaluateCoffee(fixture({ roastedOn: ago(STALE_ROAST_DAYS + 1) }));
  assert.equal(before.components.roast.penalty, 0);
  assert.equal(after.components.roast.penalty, STALE_ROAST_PENALTY);
  assert.equal(after.components.roast.stale, true);
  // The drop is the penalty plus the two days of ordinary decay, so it is
  // strictly bigger than the penalty alone.
  assert.ok(before.score - after.score >= STALE_ROAST_PENALTY, `${before.score} -> ${after.score}`);
});

test('exactly 40 days is not yet stale — the rule is "older than 40d"', () => {
  const at = evaluateCoffee(fixture({ roastedOn: ago(STALE_ROAST_DAYS) }));
  assert.equal(at.components.roast.stale, false);
  assert.equal(at.components.roast.penalty, 0);
});

test('no roast date is neutral: no bonus, no penalty, no roast component', () => {
  // "We don't know when it was roasted" and "it is stale" are different facts.
  const undated = evaluateCoffee(fixture({ roastedOn: null }));
  assert.equal(undated.components.roast, null);
  assert.ok(undated.score > 0);

  // Renormalising matters here: without it an undated coffee could never score
  // above 80, which would make a missing date a silent penalty.
  const perfect = evaluateCoffee(
    fixture({ roastedOn: null, groups: { roaster: { n: 50, mean: 5 }, origin: { n: 50, mean: 5 }, process: { n: 50, mean: 5 } } }),
  );
  assert.ok(perfect.score > 80, `an undated coffee must be able to score high, got ${perfect.score}`);
});

test('the score stays inside 0-100 even when the penalty bites hardest', () => {
  const awful = evaluateCoffee(
    fixture({
      roastedOn: ago(400),
      groups: { roaster: { n: 30, mean: 1 }, origin: { n: 30, mean: 1 }, process: { n: 30, mean: 1 } },
      pricePer100gEur: 40,
    }),
  );
  assert.ok(awful.score >= 0 && awful.score <= 100, `got ${awful.score}`);
});

test('a suppressed headline stays suppressed regardless of roast date', () => {
  const thin = evaluateCoffee(fixture({ groups: {}, roastedOn: ago(1) }));
  assert.equal(thin.confidence, 'low');
  assert.equal(thin.score, null);
  // The roast component is still reported, so the UI can show the chip.
  assert.equal(thin.components.roast.daysSinceRoast, 1);
});

test('the route must not drop fields the scorer puts on a component', () => {
  // Twice now a route-level reshape has silently dropped a field the scorer
  // produced: `roastRecency` -> `roast` (the Freshness bar vanished) and then
  // novelty's new `score` (#189, the Novelty bar rendered empty). Both were
  // invisible -- a missing key is just undefined. This asserts the one
  // reshape /api/score still performs is a SPREAD, not a replacement.
  const src = readFileSync(new URL('../src/routes/score.js', import.meta.url), 'utf8');
  const line = src.split('\n').find((l) => /^\s*novelty:/.test(l));
  assert.ok(line, 'the novelty reshape should still exist');
  assert.match(line, /\.\.\.evaluation\.components\.novelty/, 'must spread the scorer output, not replace it');
});
