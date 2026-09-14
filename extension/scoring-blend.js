// #199 — the ONE definition of how component scores become a headline number.
//
// Why this file exists: `/api/score` returns per-component scores and a blended
// total, and the extension needs to RE-blend that total at render time (see
// below). Two copies of the weights is how the server and a browser build drift
// apart, and this pair has already been reweighted twice in two days (#188 →
// #189). The third time will not be the last.
//
// It is a MIRROR of `backend/src/lib/scoring.js`, not an import of it: the
// Railway service deploys only `backend/`, so backend code cannot reach
// `extension/`, and a browser cannot import backend code either. So the
// constants are duplicated deliberately and pinned by a contract test
// (`backend/test/scoring-blend-contract.test.js`) that fails the build if the
// two ever disagree — the same arrangement `backend/src/lib/history.js` and
// `extension/history.js` already use for #194.
//
// ⚠ Change these numbers in BOTH files, in the same commit.

// Radu's weights, set 2026-09-10 (#189): "If affinity is the best predictor -
// give it 50%. Than roast recency 20%, value 15%, novelty 10%", then #140
// (2026-09-14, "want 65:35") re-split the affinity:value pair to exactly 65:35.
//
// `roast` and `novelty` are untouched #189 numbers — the pair keeps the same
// share of the whole (0.65 of 0.95) and only its internal split moved. Writing
// `{affinity: 0.65, value: 0.35}` flat would have demoted roast recency from
// 21% of the blend to 15%, changing a weight nobody asked about.
//
// They sum to 0.95, not 1, on purpose: the blend renormalises over whichever
// terms are actually present, so only the RATIO matters.
const AFFINITY_VALUE_BUDGET = 0.65;
const AFFINITY_SHARE = 0.65;
export const WEIGHTS = {
  affinity: AFFINITY_VALUE_BUDGET * AFFINITY_SHARE,   // 0.4225
  roast: 0.2,
  value: AFFINITY_VALUE_BUDGET * (1 - AFFINITY_SHARE), // 0.2275
  novelty: 0.1,
};

export const STALE_ROAST_DAYS = 40;
export const STALE_ROAST_PENALTY = 10;

const DAY_MS = 86_400_000;

// Clamps a future-dated roast (shop pre-orders really do produce them) to 0
// rather than scoring above full marks — same as the server's `daysSinceRoast`.
export function daysSinceISO(iso, now = Date.now()) {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  return Math.max(0, Math.floor((now - t) / DAY_MS));
}

// Mirrors `backend/src/lib/scoring.js`'s `roastRecencyScore`: 100 at 0 days,
// decaying to 0 at ROAST_STALE_DAYS, flat 100 inside the fresh window.
export const ROAST_FRESH_DAYS = 14;
export const ROAST_STALE_DAYS = 180;

export function roastRecencyScore(days) {
  if (days == null || !Number.isFinite(days)) return null;
  if (days <= ROAST_FRESH_DAYS) return 100;
  if (days >= ROAST_STALE_DAYS) return 0;
  const span = ROAST_STALE_DAYS - ROAST_FRESH_DAYS;
  return Math.round(((ROAST_STALE_DAYS - days) / span) * 100);
}

/**
 * Blend present components into 0-100, renormalising over the terms that exist
 * (a missing roast date must not read as a penalty — #188), then applying
 * Radu's flat stale penalty on top when a date IS known and is past 40 days.
 *
 * `parts` is `{ affinity, roast, value, novelty }`; any of them may be null.
 * `days` is the CURRENT age in days, or null.
 */
export function blendScore(parts, days) {
  const present = Object.entries(WEIGHTS)
    .map(([key, weight]) => [weight, parts?.[key]])
    .filter(([, v]) => typeof v === 'number');
  const totalWeight = present.reduce((sum, [w]) => sum + w, 0);
  if (totalWeight <= 0) return null;
  const blended = present.reduce((sum, [w, v]) => sum + w * v, 0) / totalWeight;
  const penalty = days != null && days > STALE_ROAST_DAYS ? STALE_ROAST_PENALTY : 0;
  return Math.max(0, Math.min(100, Math.round(blended - penalty)));
}
