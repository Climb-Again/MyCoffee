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
