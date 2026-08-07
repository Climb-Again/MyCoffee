// The read API for the app's actual domain data (PLAN.md §4).
//
//   GET  /api/snapshot            full delta-syncable dataset + vocab dictionary
//   GET  /api/snapshot/text       folded search blobs, keyed by coffee public id
//   GET  /api/coffees             paged/faceted parity route (debug + review tooling)
//   GET  /api/coffees/:publicId   detail
//   GET  /api/coffees/top-filters up to 7 server-ordered cards (PLAN.md §6.1)
//   POST /api/coffees/:publicId/favorite
//
// Reads use requireAnyToken; the favorite write uses requireIngestToken, same
// as every other write path — the iOS app holds INGEST_TOKEN in the Keychain
// for exactly this (CLAUDE.md §9), not just the Mac exporter.
import { requireAnyToken, requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { buildMediaUrl } from '../media.js';
import {
  loadCountryVocab,
  loadRoasterVocab,
  loadFarmVocab,
} from '../lib/vocab.js';

// Snapshot payload shape version — bump only when the *shape* of a coffee row
// or the vocab dictionary changes, so the client knows to drop a cached file
// rather than mis-decode it (PLAN.md §5: "schemaVersion mismatch -> drop and
// full-resync").
export const SNAPSHOT_VERSION = 2;

// Long-lived: the client caches thumbnails for a ten-year archive, not for one
// session (PLAN.md §5), so a 1-hour default (media.js's default, meant for an
// on-demand single fetch) would go stale before the next sync. 30 days matches
// the plan's own thumbnail-eviction window.
const THUMB_URL_TTL_SECONDS = 30 * 24 * 60 * 60;

function baseUrlFor(req) {
  return `${req.protocol}://${req.hostname}`;
}

// Compact row for the snapshot: ids only, no resolved names (those live once
// in `vocab{}`). It DOES carry a signed `thumbUrl` so the listing can show
// photos without an N-fetch detail round-trip per visible row — and, crucially,
// so a background re-sync (which overwrites each coffee wholesale) doesn't wipe
// a thumbnail that a detail visit had merged in. The URL is ~120 B/row; at the
// current corpus that's a few KB, well within the snapshot budget.
function toCompactCoffee(row, baseUrl) {
  return {
    id: row.public_id,
    photoId: row.photo_public_id,
    thumbUrl: buildMediaUrl(baseUrl, row.photo_public_id, 'thumb', THUMB_URL_TTL_SECONDS),
    purchasedOn: row.purchased_on,
    purchasedYear: row.purchased_year,
    purchasedMonth: row.purchased_month,
    roasterId: row.roaster_id,
    roasterCountryId: row.roaster_country_id,
    originCountryIds: row.origin_country_ids ?? [],
    originCountryId: row.origin_country_id,
    isBlend: row.is_blend,
    originFarmId: row.origin_farm_id,
    altitudeMinM: row.altitude_min_m,
    altitudeMaxM: row.altitude_max_m,
    altitudeMidM: row.altitude_mid_m,
    profileId: row.profile_id,
    profileDetail: row.profile_detail,
    isDecaf: row.is_decaf,
    roastedOn: row.roasted_on,
    priceOriginalAmount: row.price_original_amount,
    priceOriginalCurrency: row.price_original_currency,
    priceEur: row.price_eur,
    pricePer100gEur: row.price_per_100g_eur,
    weightG: row.weight_g,
    rating: row.rating,
    isFavorite: row.is_favorite,
    reviewState: row.review_state,
    updatedAt: row.updated_at,
  };
}

async function loadVocabDictionary() {
  const [countries, roasters, farms, profilesResult] = await Promise.all([
    loadCountryVocab(query),
    loadRoasterVocab(query),
    loadFarmVocab(query),
    query('SELECT id, slug, name FROM profiles ORDER BY id'),
  ]);
  return {
    countries: countries.candidates,
    roasters: roasters.candidates,
    farms: farms.candidates,
    profiles: profilesResult.rows,
  };
}

export default async function coffeesRoutes(app) {
  app.get('/api/snapshot', { preHandler: requireAnyToken }, async (req) => {
    const since = typeof req.query?.since === 'string' ? new Date(req.query.since) : null;
    const sinceValid = since && !Number.isNaN(since.getTime());

    const [vocab, coffeesResult, deletedResult] = await Promise.all([
      loadVocabDictionary(),
      query(
        `SELECT co.*, p.public_id AS photo_public_id
         FROM coffees co JOIN photos p ON p.id = co.photo_id
         WHERE co.deleted_at IS NULL ${sinceValid ? 'AND co.updated_at > $1' : ''}
         ORDER BY co.purchased_on DESC NULLS LAST, co.id DESC`,
        sinceValid ? [since.toISOString()] : [],
      ),
      sinceValid
        ? query(`SELECT public_id FROM coffees WHERE deleted_at IS NOT NULL AND deleted_at > $1`, [
            since.toISOString(),
          ])
        : { rows: [] },
    ]);

    const baseUrl = baseUrlFor(req);
    return {
      version: SNAPSHOT_VERSION,
      generatedAt: new Date().toISOString(),
      vocab,
      coffees: coffeesResult.rows.map((row) => toCompactCoffee(row, baseUrl)),
      deleted: deletedResult.rows.map((r) => r.public_id),
    };
  });

  app.get('/api/snapshot/text', { preHandler: requireAnyToken }, async () => {
    const { rows } = await query(
      `SELECT public_id, search_labels_blob, search_prose_blob
       FROM coffees WHERE deleted_at IS NULL`,
    );
    const texts = {};
    for (const row of rows) {
      texts[row.public_id] = [row.search_labels_blob, row.search_prose_blob]
        .filter(Boolean)
        .join('\n');
    }
    return { texts };
  });

  // Denormalized, human-readable shape (unlike the compact snapshot row) --
  // this route is debug + review tooling, not the app's hot path.
  app.get('/api/coffees', { preHandler: requireAnyToken }, async (req) => {
    const limit = Math.min(Math.max(Number.parseInt(req.query?.limit, 10) || 50, 1), 200);
    const offset = Math.max(Number.parseInt(req.query?.offset, 10) || 0, 0);

    const [{ rows: items }, {
      rows: [{ count }],
    }] = await Promise.all([
      query(
        `SELECT co.public_id, co.purchased_on, co.rating, co.is_favorite, co.review_state,
                p.public_id AS photo_public_id,
                r.name AS roaster_name, r.slug AS roaster_slug,
                f.name AS origin_farm_name,
                pr.name AS profile_name
         FROM coffees co
         JOIN photos p ON p.id = co.photo_id
         LEFT JOIN roasters r ON r.id = co.roaster_id
         LEFT JOIN farms f ON f.id = co.origin_farm_id
         LEFT JOIN profiles pr ON pr.id = co.profile_id
         WHERE co.deleted_at IS NULL
         ORDER BY co.purchased_on DESC NULLS LAST, co.id DESC
         LIMIT $1 OFFSET $2`,
        [limit, offset],
      ),
      query(`SELECT count(*) FROM coffees WHERE deleted_at IS NULL`),
    ]);

    return {
      total: Number(count),
      limit,
      offset,
      items: items.map((row) => ({
        id: row.public_id,
        photoId: row.photo_public_id,
        purchasedOn: row.purchased_on,
        rating: row.rating,
        isFavorite: row.is_favorite,
        reviewState: row.review_state,
        roaster: row.roaster_name ? { name: row.roaster_name, slug: row.roaster_slug } : null,
        originFarmName: row.origin_farm_name,
        profileName: row.profile_name,
      })),
    };
  });

  app.get('/api/coffees/:publicId', { preHandler: requireAnyToken }, async (req, reply) => {
    const { rows } = await query(
      `SELECT co.*, p.public_id AS photo_public_id
       FROM coffees co
       JOIN photos p ON p.id = co.photo_id
       WHERE co.public_id = $1 AND co.deleted_at IS NULL`,
      [req.params.publicId],
    );
    const row = rows[0];
    if (!row) return reply.code(404).send({ error: 'coffee_not_found' });

    const baseUrl = baseUrlFor(req);
    return {
      ...toCompactCoffee(row),
      descFarmLot: row.desc_farm_lot,
      descBrewGuide: row.desc_brew_guide,
      descRoasterCopy: row.desc_roaster_copy,
      rawTitle: row.raw_title,
      rawCaption: row.raw_caption,
      rawDescription: row.raw_description,
      minFieldConfidence: row.min_field_confidence,
      thumbUrl: buildMediaUrl(baseUrl, row.photo_public_id, 'thumb', THUMB_URL_TTL_SECONDS),
      displayUrl: buildMediaUrl(baseUrl, row.photo_public_id, 'display', THUMB_URL_TTL_SECONDS),
      // Rails (roaster/origin "more like this") need extraction data that
      // doesn't exist until #23/#24 land -- always empty until then.
      rails: [],
    };
  });

  // PLAN.md §6.1's "8-into-7" resolution: two pinned cards, one single most-
  // represented "interesting" process (Natural/Washed excluded -- at ~70% of
  // the library they aren't a shortcut), then up to 4 origin-country cards.
  app.get('/api/coffees/top-filters', { preHandler: requireAnyToken }, async () => {
    const [{ rows: [totals] }, { rows: [processRow] }, { rows: originRows }] = await Promise.all([
      query(
        `SELECT count(*) FILTER (WHERE deleted_at IS NULL) AS total,
                count(*) FILTER (WHERE deleted_at IS NULL AND is_favorite) AS favorites,
                count(*) FILTER (WHERE deleted_at IS NULL AND rating >= 4.5) AS high_rated
         FROM coffees`,
      ),
      query(
        `SELECT pr.id, pr.slug, pr.name, count(*) AS cnt
         FROM coffees co JOIN profiles pr ON pr.id = co.profile_id
         WHERE co.deleted_at IS NULL AND pr.slug NOT IN ('washed', 'natural')
         GROUP BY pr.id, pr.slug, pr.name
         ORDER BY cnt DESC, pr.name ASC
         LIMIT 1`,
      ),
      query(
        `SELECT c.id, c.name, count(*) AS cnt
         FROM coffees co, unnest(co.origin_country_ids) AS oc(country_id)
         JOIN countries c ON c.id = oc.country_id
         WHERE co.deleted_at IS NULL AND co.rating >= 4.0
         GROUP BY c.id, c.name
         HAVING count(*) >= 5
         ORDER BY cnt DESC, c.name ASC
         LIMIT 4`,
      ),
    ]);

    const total = Number(totals.total);
    const cards = [
      { type: 'favorites', label: 'Favourites', count: Number(totals.favorites) },
      { type: 'rating', label: '4.5+', count: Number(totals.high_rated), minRating: 4.5 },
    ];
    if (processRow) {
      cards.push({
        type: 'profile',
        label: processRow.name,
        count: Number(processRow.cnt),
        profileId: processRow.id,
      });
    }
    for (const r of originRows) {
      const cnt = Number(r.cnt);
      if (cnt >= total) continue; // wouldn't narrow anything -- not a useful shortcut
      cards.push({ type: 'origin', label: r.name, count: cnt, countryId: r.id });
    }

    return { cards: cards.slice(0, 7) };
  });

  app.post('/api/coffees/:publicId/favorite', { preHandler: requireIngestToken }, async (req, reply) => {
    const favorite = Boolean(req.body?.favorite);
    const { rows } = await query(
      `UPDATE coffees
       SET is_favorite = $1, favorite_set_by = 'human', updated_at = now()
       WHERE public_id = $2 AND deleted_at IS NULL
       RETURNING public_id, is_favorite`,
      [favorite, req.params.publicId],
    );
    const row = rows[0];
    if (!row) return reply.code(404).send({ error: 'coffee_not_found' });
    return { id: row.public_id, isFavorite: row.is_favorite };
  });
}
