// "Evaluate this coffee" scoring (#106) -- how well a bag Radu doesn't own
// yet fits what he actually buys, built from a leave-one-out validation
// against the real 363 rated coffees (status/backend.md has the full
// numbers): origin/roaster/process each carry r~0.30 on their own, roaster
// country r~0.26, altitude and decaf carry none, and flavour notes -- the
// obvious candidate -- carry NO usable signal once aggregated (LOO r=-0.01).
// So this module blends only the four signals that actually predict
// anything, shrunk hard toward the mean, and pairs the result with a
// confidence badge rather than presenting a number precise to two digits.
//
// Pure functions only -- no DB access. The route wires these to real
// aggregate queries (backend/src/routes/coffees.js).

export const SHRINK_K = 5;

// Correlation-squared reliability weights measured by the row's own LOO
// study. Re-measure (status/backend.md) before changing these -- they are
// not guesses.
export const AFFINITY_SIGNALS = [
  { key: 'origin', r: 0.31 },
  { key: 'roaster', r: 0.30 },
  { key: 'process', r: 0.30 },
  { key: 'roasterCountry', r: 0.26 },
];

// Only these three gate the confidence badge (Radu's own wording in #106:
// "roaster, origin and process are all unseen or under ~5 rated bags") --
// roaster country is deliberately excluded from the gate, though it still
// contributes to the blend above.
const CONFIDENCE_GATE_SIGNALS = ['origin', 'roaster', 'process'];
const CONFIDENCE_MIN_N = 5;

// The row's suggested blend is "50 value / 35 affinity / 15 novelty", but
// also insists novelty is "neither good nor bad" and belongs on the card as
// a tag, not a score. Contributing it as a fixed neutral midpoint (50)
// keeps the literal 3-way weighting the row asked for without smuggling an
// unrequested directional bias into the headline number. Flag for Radu once
// he's seen real samples -- he may prefer dropping it from the blend
// entirely (see status/backend.md).
export const FINAL_WEIGHTS = { value: 0.50, affinity: 0.35, novelty: 0.15 };
const NEUTRAL_NOVELTY_SCORE = 50;

export function shrunkMean(n, mean, globalMean, k = SHRINK_K) {
  if (!n || n <= 0) return globalMean;
  return (n * mean + k * globalMean) / (n + k);
}

// groups: { origin: {n, mean} | undefined, roaster, process, roasterCountry }
// (n/mean computed from RATED coffees sharing that signal's value).
// Returns a rating-scale (~0-5) point estimate -- shrunk toward globalMean,
// and equal to globalMean outright when every signal is unseen.
export function blendAffinity(groups, globalMean, k = SHRINK_K) {
  let weightedSum = 0;
  let totalWeight = 0;
  for (const { key, r } of AFFINITY_SIGNALS) {
    const g = groups[key];
    const n = g?.n ?? 0;
    if (n <= 0) continue;
    const reliability = n / (n + k);
    const weight = r * r * reliability;
    weightedSum += weight * shrunkMean(n, g.mean, globalMean, k);
    totalWeight += weight;
  }
  return totalWeight > 0 ? weightedSum / totalWeight : globalMean;
}

export function confidenceFor(groups) {
  const thin = CONFIDENCE_GATE_SIGNALS.every((key) => (groups[key]?.n ?? 0) < CONFIDENCE_MIN_N);
  return thin ? 'low' : 'normal';
}

// Percentile of `value` within `sortedAscending` (inclusive rank / n), 0-100.
// Uses the full range on purpose (#106: "so it uses the full range rather
// than compressing into 80-90%") -- a raw shrunk-mean blend clusters near
// the corpus mean, so it must be re-expressed as rank, not shown directly.
export function percentileRank(value, sortedAscending) {
  if (!sortedAscending.length) return 50;
  let below = 0;
  for (const v of sortedAscending) if (v <= value) below++;
  return Math.round((below / sortedAscending.length) * 100);
}

// Quintile-bucket `priced` (ascending by pricePer100gEur) into 5 bands, same
// bucketing #95 used for the on-device value meter (ceil-sized bands, band 1
// cheapest). Returns which band `pricePer100gEur` falls in plus that band's
// n and mean rating, or null if there's no priced-and-rated corpus at all.
export function priceBandFor(pricePer100gEur, priced) {
  if (pricePer100gEur == null || !priced.length) return null;
  const sorted = [...priced].sort((a, b) => a.pricePer100gEur - b.pricePer100gEur);
  const bandSize = Math.ceil(sorted.length / 5);
  const bands = [];
  for (let i = 0; i < 5; i++) {
    const slice = sorted.slice(i * bandSize, (i + 1) * bandSize);
    if (slice.length) bands.push(slice);
  }
  let chosen = bands[bands.length - 1];
  let index = bands.length;
  for (let i = 0; i < bands.length; i++) {
    if (pricePer100gEur <= bands[i][bands[i].length - 1].pricePer100gEur) {
      chosen = bands[i];
      index = i + 1;
      break;
    }
  }
  const mean = chosen.reduce((s, c) => s + c.rating, 0) / chosen.length;
  return { index, n: chosen.length, mean };
}

// Same two cutoffs #105 measured against the real corpus (±0.10 / ±0.30,
// the most even split of the five pill counts it tried) -- reused here so
// this feature and the on-device value meter never disagree on what
// "fair" means for the same delta.
export function pillCountFromDelta(delta) {
  if (delta <= -0.3) return 1;
  if (delta <= -0.1) return 2;
  if (delta < 0.1) return 3;
  if (delta < 0.3) return 4;
  return 5;
}

// `groups`/`globalMean`: as blendAffinity above.
// `priced`: [{ pricePer100gEur, rating }] over the rated+priced corpus.
// `affinitySamples`: sorted-ascending array of every rated coffee's own
//   blendAffinity() result, for percentile ranking.
// `pricePer100gEur`: the draft's own price, or null if unknown.
// `isNewRoaster`/`isNewOrigin`: booleans, any-coffee (not just rated) counts.
// Minimum rated+priced band size before the value component is trusted
// (below this, #95's own meter suppresses the verdict too).
const MIN_BAND_N = 5;

export function evaluateCoffee({
  groups,
  globalMean,
  priced,
  affinitySamples,
  pricePer100gEur,
  isNewRoaster,
  isNewOrigin,
}) {
  const affinityRaw = blendAffinity(groups, globalMean);
  const affinityScore = percentileRank(affinityRaw, affinitySamples);
  const confidence = confidenceFor(groups);

  const band = priceBandFor(pricePer100gEur, priced);
  const bandReliable = Boolean(band && band.n >= MIN_BAND_N);
  const delta = bandReliable ? affinityRaw - band.mean : null;
  const pillCount = bandReliable ? pillCountFromDelta(delta) : null;
  const valueScore = bandReliable ? pillCount * 20 : null;

  const novelty = { isNewRoaster: Boolean(isNewRoaster), isNewOrigin: Boolean(isNewOrigin) };

  const canShowHeadline = confidence === 'normal' && valueScore != null;
  const score = canShowHeadline
    ? Math.round(
        FINAL_WEIGHTS.value * valueScore +
          FINAL_WEIGHTS.affinity * affinityScore +
          FINAL_WEIGHTS.novelty * NEUTRAL_NOVELTY_SCORE,
      )
    : null;

  return {
    score,
    confidence,
    components: {
      affinity: { score: affinityScore, raw: Math.round(affinityRaw * 100) / 100 },
      value: valueScore == null ? null : { score: valueScore, pillCount, band: band.index, bandN: band.n },
      novelty,
    },
  };
}

// "What to buy next" rotation recommendation (#107) -- ranks entities
// (roaster / origin country / process) Radu already buys by how much he
// likes them times how overdue he is for a repeat purchase. Reuses
// `shrunkMean` from #106 above on purpose (#107's own row: "they should
// share one vocabulary of affinity so the two never contradict each
// other"). Unlike #106, this never predicts an unseen rating -- affinity
// here is deliberately allowed to go negative (see `MIN_ENTITY_N` below),
// so a merely-stale entity a bag away from wear-out doesn't get
// recommended just for being old.

const DAY_MS = 86_400_000;

// Prototype leak (status/backend.md): a ~5-bag floor was intended from the
// start but a softer check let `Sumo Coffee Roasters` (4 bags, one 14-day
// gap) through with a 33.9x "overdue" the cap merely hid rather than fixed.
// Hard floor now: an entity needs 5+ rated bags before it's ranked at all.
export const ROTATION_MIN_N = 5;

// Std-dev of per-entity shrunk-mean affinity across the real corpus
// (status/backend.md) -- turns the raw affinity into a z-score so entities
// can be compared on one scale regardless of how tight ratings cluster.
export const ROTATION_AFFINITY_STD_DEV = 0.44;

export const ROTATION_OVERDUE_CAP = 3.0;

// A typical-gap estimate can't go below this even after shrinkage -- guards
// against a same-week double purchase reading as a wildly short cadence.
export const ROTATION_GAP_FLOOR_DAYS = 14;

// Shrinkage strength for typicalGapDays, same k as shrunkMean by convention.
const ROTATION_GAP_SHRINK_K = 5;

// `purchaseDatesAscending`: every purchase of this entity (not just rated
// ones -- cadence is about buying, not opinion), sorted ascending, as
// epoch millis. `globalGapDays`: Radu's overall purchase cadence, used to
// pull an unstable few-purchase median toward something sane rather than
// trusting e.g. a single 14-day gap outright (the fix for the Sumo leak
// above: a hard n>=5 floor on the *rated* count still lets a thinly-
// purchased entity through on the gap side, so the gap itself is shrunk).
export function typicalGapDays(purchaseDatesAscending, globalGapDays, k = ROTATION_GAP_SHRINK_K) {
  const gaps = [];
  for (let i = 1; i < purchaseDatesAscending.length; i++) {
    gaps.push((purchaseDatesAscending[i] - purchaseDatesAscending[i - 1]) / DAY_MS);
  }
  const n = gaps.length;
  const median = n === 0 ? globalGapDays : medianOf(gaps);
  const shrunk = (n * median + k * globalGapDays) / (n + k);
  return Math.max(shrunk, ROTATION_GAP_FLOOR_DAYS);
}

function medianOf(sortedOrNot) {
  const s = [...sortedOrNot].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

// One entity's rotation score, or null if it doesn't clear ROTATION_MIN_N.
// `n`/`mean`: rated-bag count and mean rating for this entity.
// `purchaseDatesAscending`/`lastPurchaseAt`: this entity's own purchase
// history (all purchases, not just rated) -- `lastPurchaseAt` as epoch
// millis, `now` defaulting to the real clock so tests can pin it.
export function rotationScoreFor({
  n,
  mean,
  globalMean,
  purchaseDatesAscending,
  lastPurchaseAt,
  globalGapDays,
  now = Date.now(),
}) {
  if (!n || n < ROTATION_MIN_N) return null;
  const affinity = shrunkMean(n, mean, globalMean);
  const z = (affinity - globalMean) / ROTATION_AFFINITY_STD_DEV;
  const gap = typicalGapDays(purchaseDatesAscending, globalGapDays);
  const daysSinceLast = (now - lastPurchaseAt) / DAY_MS;
  const overdue = Math.min(daysSinceLast / gap, ROTATION_OVERDUE_CAP);
  const score = z * overdue;
  return {
    affinity: Math.round(affinity * 100) / 100,
    z: Math.round(z * 100) / 100,
    typicalGapDays: Math.round(gap),
    daysSinceLast: Math.round(daysSinceLast),
    overdue: Math.round(overdue * 100) / 100,
    score,
  };
}

// candidates: [{ entity, id, name, n, mean, purchaseDatesAscending, lastPurchaseAt }, ...]
// across all three kinds at once -- ranking is cross-kind by design (#107:
// "rank descending"), the caller doesn't pre-split by entity type.
export function rankRotationCandidates(candidates, { globalMean, globalGapDays, limit = 5, now = Date.now() }) {
  const scored = [];
  for (const c of candidates) {
    const result = rotationScoreFor({ ...c, globalMean, globalGapDays, now });
    if (!result) continue;
    scored.push({ entity: c.entity, id: c.id, name: c.name, n: c.n, ...result });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit);
}

// The reason string from #107's own worked example: "4.21 over 11 bags, 92
// days since the last one vs your usual 38".
export function rotationReason(candidate) {
  return `${candidate.affinity.toFixed(2)} over ${candidate.n} bag${candidate.n === 1 ? '' : 's'}, ` +
    `${candidate.daysSinceLast} days since the last one vs your usual ${candidate.typicalGapDays}`;
}
