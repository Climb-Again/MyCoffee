// The rated-corpus aggregates every "how does this bag fit?" score is built
// from (#106's `POST /api/coffees/evaluate`, #160's `POST /api/score`).
//
// Extracted here for one reason: both endpoints must score the same bag the
// same way. #159 flagged the risk directly -- the browsing-score spec and
// #106's evaluate spec were written four days apart, neither referencing the
// other, over nearly the same factor list. Two copies of these aggregates
// would be two scorers, and the app and the extension would eventually
// disagree about the same coffee in front of Radu. One loader, one answer.
//
// The pure math stays in `scoring.js`; this module only fetches and shapes.
import { query } from '../db.js';
import { blendAffinity } from './scoring.js';

// Aggregates change only when a coffee is rated, added or repriced -- none of
// which happens between two page views. A short TTL keeps a browsing session
// (where the extension may score a dozen tabs in a minute) from re-running
// three full-corpus queries per page, without ever serving state stale enough
// to notice.
const CACHE_TTL_MS = 60_000;
let _cache = null;

export function clearCorpusCache() {
  _cache = null;
}

// Per-signal {n, mean} over the rated corpus, one pass per key.
function groupStats(rows, key) {
  const buckets = new Map();
  for (const row of rows) {
    const v = row[key];
    if (v == null) continue;
    const bucket = buckets.get(v) ?? { n: 0, sum: 0 };
    bucket.n += 1;
    bucket.sum += row.rating;
    buckets.set(v, bucket);
  }
  const stats = new Map();
  for (const [v, { n, sum }] of buckets) stats.set(v, { n, mean: sum / n });
  return stats;
}

async function fetchCorpus() {
  const [{ rows: globalRows }, { rows: signalRows }, { rows: pricedRows }] = await Promise.all([
    query(`SELECT AVG(rating)::float AS mean FROM coffees WHERE rating IS NOT NULL AND deleted_at IS NULL`),
    query(
      `SELECT origin_country_id AS "originCountryId", roaster_id AS "roasterId", profile_id AS "profileId",
              roaster_country_id AS "roasterCountryId", rating::float AS rating
         FROM coffees WHERE rating IS NOT NULL AND deleted_at IS NULL`,
    ),
    query(
      `SELECT price_per_100g_eur::float AS "pricePer100gEur", rating::float AS rating
         FROM coffees WHERE rating IS NOT NULL AND price_per_100g_eur IS NOT NULL AND deleted_at IS NULL`,
    ),
  ]);

  const globalMean = globalRows[0]?.mean ?? 4;
  const stats = {
    origin: groupStats(signalRows, 'originCountryId'),
    roaster: groupStats(signalRows, 'roasterId'),
    process: groupStats(signalRows, 'profileId'),
    roasterCountry: groupStats(signalRows, 'roasterCountryId'),
  };

  const groupsForRow = (row) => ({
    origin: row.originCountryId != null ? stats.origin.get(row.originCountryId) : undefined,
    roaster: row.roasterId != null ? stats.roaster.get(row.roasterId) : undefined,
    process: row.profileId != null ? stats.process.get(row.profileId) : undefined,
    roasterCountry: row.roasterCountryId != null ? stats.roasterCountry.get(row.roasterCountryId) : undefined,
  });

  // Non-LOO on purpose: this ranks a draft against the corpus as it stands
  // today, it is not a predictive-accuracy claim (that validation -- LOO
  // r=0.39 -- happened at design time, see status/backend.md).
  const affinitySamples = signalRows.map((row) => blendAffinity(groupsForRow(row), globalMean)).sort((a, b) => a - b);

  return { globalMean, signalRows, pricedRows, stats, affinitySamples };
}

export async function loadScoringCorpus({ maxAgeMs = CACHE_TTL_MS } = {}) {
  const now = Date.now();
  if (_cache && now - _cache.at < maxAgeMs) return _cache.value;
  const value = await fetchCorpus();
  _cache = { at: now, value };
  return value;
}

// Shapes one candidate coffee's four signals against the corpus, ready for
// `blendAffinity`/`evaluateCoffee`.
export function groupsForCandidate(stats, { roasterId, originCountryId, profileId, roasterCountryId }) {
  return {
    origin: originCountryId != null ? stats.origin.get(originCountryId) : undefined,
    roaster: roasterId != null ? stats.roaster.get(roasterId) : undefined,
    process: profileId != null ? stats.process.get(profileId) : undefined,
    roasterCountry: roasterCountryId != null ? stats.roasterCountry.get(roasterCountryId) : undefined,
  };
}

// "Has Radu ever bought from this roaster / this origin?" -- novelty is an
// any-coffee question, not a rated-only one, so it can't be read off the
// aggregates above.
//
// Returns **null**, not `true`, when the field was never extracted. "We could
// not read the origin" and "this origin is new to you" are different facts,
// and conflating them produces a confident falsehood: the first live test of
// /api/score was a Congo coffee whose origin the vocab cannot resolve at all
// (backlog #165), and it came back flagged as a new origin. `evaluateCoffee`
// coerces null to false, so an unknown field counts as NOT novel -- the
// conservative direction, since novelty is surfaced to the user as a claim.
const NOVELTY_COLUMNS = new Set(['roaster_id', 'origin_country_id']);

async function everBought(column, id) {
  // The column name is interpolated, not parameterised -- Postgres has no
  // placeholder for identifiers. Both call sites pass a literal, and this
  // allowlist keeps it that way if someone later reaches for this helper with
  // something a request controls.
  if (!NOVELTY_COLUMNS.has(column)) throw new Error(`everBought: unsupported column ${column}`);
  if (id == null) return null;
  const { rows } = await query(
    `SELECT EXISTS(SELECT 1 FROM coffees WHERE ${column} = $1 AND deleted_at IS NULL) AS exists`,
    [id],
  );
  return Boolean(rows[0]?.exists);
}

export async function loadNovelty({ roasterId, originCountryId }) {
  const [roasterSeen, originSeen] = await Promise.all([
    everBought('roaster_id', roasterId),
    everBought('origin_country_id', originCountryId),
  ]);
  return {
    isNewRoaster: roasterSeen == null ? null : !roasterSeen,
    isNewOrigin: originSeen == null ? null : !originSeen,
  };
}
