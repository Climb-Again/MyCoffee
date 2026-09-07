// GET /api/brief — the app pulls its daily brief (a read). Requires either
// token: the app only ever holds INGEST_TOKEN in its Keychain today, so
// gating a read on APP_TOKEN alone made this endpoint unreachable from the
// app (PLAN.md "pre-existing defects to fix first", #1).
//
// `brief` itself is still a skeleton — wire it to Vertex generation once the
// product brief defines what a "brief" is for MyCoffee. `rotationSuggestions`
// (#107) is real: computed live from `coffees` on every call, independent of
// whether a stored `brief` row exists — this is the "what should I know
// today" surface #107 asked to reuse rather than a new screen.
import { requireAnyToken } from '../auth.js';
import { query } from '../db.js';
import { rankRotationCandidates, rotationReason } from '../lib/scoring.js';

const ROTATION_LIMIT = 5;

// One row per entity kind, each shrunk into `rankRotationCandidates`'
// candidate shape. `lastPurchaseAt`/`purchaseDatesAscending` come from every
// purchase of the entity (not just rated ones — cadence is about buying, not
// opinion); `n`/`mean` come from the rated subset only (affinity's input).
async function loadRotationCandidates() {
  const entityQueries = [
    {
      entity: 'roaster',
      sql: `SELECT c.roaster_id AS id, r.name AS name,
                   COUNT(*) FILTER (WHERE c.rating IS NOT NULL) AS n,
                   AVG(c.rating) FILTER (WHERE c.rating IS NOT NULL)::float AS mean,
                   array_agg(c.purchased_on ORDER BY c.purchased_on) FILTER (WHERE c.purchased_on IS NOT NULL) AS dates
              FROM coffees c
              JOIN roasters r ON r.id = c.roaster_id
             WHERE c.deleted_at IS NULL AND c.roaster_id IS NOT NULL
             GROUP BY c.roaster_id, r.name`,
    },
    {
      entity: 'originCountry',
      sql: `SELECT c.origin_country_id AS id, co.name AS name,
                   COUNT(*) FILTER (WHERE c.rating IS NOT NULL) AS n,
                   AVG(c.rating) FILTER (WHERE c.rating IS NOT NULL)::float AS mean,
                   array_agg(c.purchased_on ORDER BY c.purchased_on) FILTER (WHERE c.purchased_on IS NOT NULL) AS dates
              FROM coffees c
              JOIN countries co ON co.id = c.origin_country_id
             WHERE c.deleted_at IS NULL AND c.origin_country_id IS NOT NULL
             GROUP BY c.origin_country_id, co.name`,
    },
    {
      entity: 'process',
      sql: `SELECT c.profile_id AS id, p.name AS name,
                   COUNT(*) FILTER (WHERE c.rating IS NOT NULL) AS n,
                   AVG(c.rating) FILTER (WHERE c.rating IS NOT NULL)::float AS mean,
                   array_agg(c.purchased_on ORDER BY c.purchased_on) FILTER (WHERE c.purchased_on IS NOT NULL) AS dates
              FROM coffees c
              JOIN profiles p ON p.id = c.profile_id
             WHERE c.deleted_at IS NULL AND c.profile_id IS NOT NULL
             GROUP BY c.profile_id, p.name`,
    },
  ];

  const [{ rows: globalRows }, { rows: cadenceRows }, ...entityResults] = await Promise.all([
    query(`SELECT AVG(rating)::float AS mean FROM coffees WHERE rating IS NOT NULL AND deleted_at IS NULL`),
    query(
      `SELECT MIN(purchased_on) AS "minDate", MAX(purchased_on) AS "maxDate", COUNT(*) AS n
         FROM coffees WHERE purchased_on IS NOT NULL AND deleted_at IS NULL`,
    ),
    ...entityQueries.map((q) => query(q.sql)),
  ]);

  const globalMean = globalRows[0]?.mean ?? 4;
  const cadence = cadenceRows[0];
  const spanDays = cadence?.minDate && cadence?.maxDate
    ? (new Date(cadence.maxDate) - new Date(cadence.minDate)) / 86_400_000
    : 0;
  const cadenceN = Number(cadence?.n ?? 0);
  // Radu's overall purchase cadence -- the shrinkage target for an
  // individual entity's typicalGapDays at low purchase counts (#107's own
  // "shrink typicalGap toward his overall cadence for small n" fix).
  const globalGapDays = cadenceN > 1 ? spanDays / (cadenceN - 1) : 14;

  const candidates = [];
  entityQueries.forEach((q, i) => {
    for (const row of entityResults[i].rows) {
      const dates = (row.dates ?? []).map((d) => new Date(d).getTime());
      if (dates.length === 0) continue;
      candidates.push({
        entity: q.entity,
        id: row.id,
        name: row.name,
        n: Number(row.n),
        mean: row.mean,
        purchaseDatesAscending: dates,
        lastPurchaseAt: dates[dates.length - 1],
      });
    }
  });

  return rankRotationCandidates(candidates, { globalMean, globalGapDays, limit: ROTATION_LIMIT });
}

export default async function briefRoutes(app) {
  app.get('/api/brief', { preHandler: requireAnyToken }, async () => {
    let latest = null;
    try {
      const { rows } = await query(
        `SELECT id, title, body, generated_at
           FROM briefs
          ORDER BY generated_at DESC
          LIMIT 1`,
      );
      latest = rows[0] || null;
    } catch {
      latest = null; // table may not exist yet
    }

    let rotationSuggestions = [];
    try {
      const ranked = await loadRotationCandidates();
      rotationSuggestions = ranked.map((c) => ({
        entity: c.entity,
        id: c.id,
        name: c.name,
        rating: c.affinity,
        n: c.n,
        daysSinceLast: c.daysSinceLast,
        typicalGapDays: c.typicalGapDays,
        overdue: c.overdue,
        score: Math.round(c.score * 100) / 100,
        reason: rotationReason(c),
      }));
    } catch {
      rotationSuggestions = []; // coffees table may not exist yet, or DB unreachable
    }

    if (!latest) {
      return {
        ok: true,
        brief: null,
        message: 'No brief generated yet.',
        rotationSuggestions,
      };
    }

    return {
      ok: true,
      brief: {
        id: latest.id,
        title: latest.title,
        body: latest.body,
        generatedAt: latest.generated_at,
      },
      rotationSuggestions,
    };
  });
}
