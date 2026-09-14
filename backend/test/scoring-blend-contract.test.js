// #199 — the guard that `extension/scoring-blend.js` never drifts from
// `backend/src/lib/scoring.js`.
//
// These two compute the same headline number on two sides of a network, and
// they have already been reweighted twice in two days (#188 -> #189). They
// cannot be one module: the Railway service deploys only `backend/`, so backend
// code cannot reach `extension/`, and a browser cannot import backend code. So
// the constants are mirrored and pinned here — the same arrangement
// `history-lib.test.js` uses for #194.
//
// CLAUDE.md §12's public-contract rule is the reason this matters: the backend
// redeploys on every push to `main`; an extension sitting in someone's browser
// does not. A weight changed on one side only is silent — every installed copy
// just starts showing a different number from the server's.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FINAL_WEIGHTS,
  STALE_ROAST_DAYS,
  STALE_ROAST_PENALTY,
  ROAST_FRESH_DAYS,
  ROAST_STALE_DAYS,
  roastRecencyScore as serverRoastRecency,
  daysSinceRoast,
} from '../src/lib/scoring.js';
import {
  WEIGHTS,
  STALE_ROAST_DAYS as CLIENT_STALE_DAYS,
  STALE_ROAST_PENALTY as CLIENT_STALE_PENALTY,
  ROAST_FRESH_DAYS as CLIENT_FRESH_DAYS,
  ROAST_STALE_DAYS as CLIENT_STALE_ROAST_DAYS,
  roastRecencyScore as clientRoastRecency,
  daysSinceISO,
  blendScore,
} from '../../extension/scoring-blend.js';

test('the blend weights are identical on both sides', () => {
  assert.deepEqual(WEIGHTS, FINAL_WEIGHTS, 'extension/scoring-blend.js drifted from backend/src/lib/scoring.js');
});

test('the stale-roast rule is identical on both sides', () => {
  assert.equal(CLIENT_STALE_DAYS, STALE_ROAST_DAYS);
  assert.equal(CLIENT_STALE_PENALTY, STALE_ROAST_PENALTY);
  assert.equal(CLIENT_FRESH_DAYS, ROAST_FRESH_DAYS);
  assert.equal(CLIENT_STALE_ROAST_DAYS, ROAST_STALE_DAYS);
});

test('roastRecencyScore agrees across the whole curve, including the edges', () => {
  for (const d of [0, 1, 13, 14, 15, 39, 40, 41, 90, 179, 180, 400, null]) {
    assert.equal(clientRoastRecency(d), serverRoastRecency(d), `disagreed at ${d} days`);
  }
});

test('day arithmetic agrees, including a future-dated roast', () => {
  const now = Date.UTC(2026, 8, 14);
  for (const iso of ['2026-09-14', '2026-09-01', '2026-01-01', '2027-01-01', null, 'garbage']) {
    assert.equal(daysSinceISO(iso, now), daysSinceRoast(iso, now), `disagreed for ${iso}`);
  }
});

// The real parity check: the same component scores must blend to the same
// number on both sides. `evaluateCoffee` is not callable here without a corpus,
// so this reimplements only its final blend step from the SERVER's constants
// and asserts the client's `blendScore` matches — if either side's weights or
// penalty move, this fails.
function serverBlend(parts, days) {
  const present = [
    [FINAL_WEIGHTS.affinity, parts.affinity],
    [FINAL_WEIGHTS.value, parts.value],
    [FINAL_WEIGHTS.roast, parts.roast],
    [FINAL_WEIGHTS.novelty, parts.novelty],
  ].filter(([, v]) => typeof v === 'number');
  const totalWeight = present.reduce((s, [w]) => s + w, 0);
  if (totalWeight <= 0) return null;
  const blended = present.reduce((s, [w, v]) => s + w * v, 0) / totalWeight;
  const penalty = days != null && days > STALE_ROAST_DAYS ? STALE_ROAST_PENALTY : 0;
  return Math.max(0, Math.min(100, Math.round(blended - penalty)));
}

test('blendScore produces identical numbers to the server on a fixed fixture', () => {
  const fixtures = [
    [{ affinity: 70, value: 50, roast: 100, novelty: 100 }, 5],
    [{ affinity: 70, value: 50, roast: 62, novelty: 0 }, 45],   // past the stale cliff
    [{ affinity: 45, value: null, roast: null, novelty: 50 }, null], // renormalises
    [{ affinity: 0, value: 0, roast: 0, novelty: 0 }, 400],
    [{ affinity: 100, value: 100, roast: 100, novelty: 100 }, 0],
  ];
  for (const [parts, days] of fixtures) {
    assert.equal(blendScore(parts, days), serverBlend(parts, days), `disagreed on ${JSON.stringify(parts)} @ ${days}d`);
  }
});

test('a missing roast term renormalises rather than scoring zero', () => {
  const withRoast = blendScore({ affinity: 80, value: 80, roast: 0, novelty: 80 }, 200);
  const withoutRoast = blendScore({ affinity: 80, value: 80, roast: null, novelty: 80 }, null);
  assert.equal(withoutRoast, 80, 'an unknown roast date must not read as a penalty');
  assert.ok(withRoast < withoutRoast);
});
