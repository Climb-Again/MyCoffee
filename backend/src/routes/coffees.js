// The read API for the app's actual domain data (PLAN.md §4).
//
//   GET  /api/snapshot            full delta-syncable dataset + vocab dictionary
//   GET  /api/snapshot/text       folded search blobs, keyed by coffee public id
//   GET  /api/coffees             paged/faceted parity route (debug + review tooling)
//   GET  /api/coffees/:publicId   detail
//   GET  /api/coffees/top-filters up to 7 server-ordered cards (PLAN.md §6.1)
//   POST /api/coffees/:publicId/favorite
//   POST /api/coffees/:publicId/rotation persisted photo rotation (#73)
//   POST /api/coffees/:publicId/edit     generic per-field edit (PLAN.md §12 #40)
//   POST /api/coffees/extract     Add Coffee wizard: synchronous light-ensemble draft (PLAN.md §6.8, #75)
//   POST /api/coffees             Add Coffee wizard: persist the confirmed draft (PLAN.md §6.8, #75)
//   POST /api/coffees/quick-create Add Coffee: create instantly, extract in the background (#118)
//   POST /api/coffees/evaluate    "Evaluate this coffee" -- fit score for a bag not yet owned (#106)
//
// Reads use requireAnyToken; the favorite/edit writes use requireIngestToken,
// same as every other write path — the iOS app holds INGEST_TOKEN in the
// Keychain for exactly this (CLAUDE.md §9), not just the Mac exporter.
import { requireAnyToken, requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { buildMediaUrl } from '../media.js';
import {
  loadCountryVocab,
  loadRoasterVocab,
  loadFarmVocab,
} from '../lib/vocab.js';
import {
  loadSharedContext,
  applyResolutionsToCoffee,
  upsertCoffeeBase,
  fetchLatestText,
  fetchImageBuffer,
  buildRawText,
  runLightExtraction,
  pickRawExtractedValue,
  defaultVoters,
  processPhoto,
} from '../lib/worker.js';
import { toEur } from '../lib/fx.js';
import { evaluateCoffee } from '../lib/scoring.js';
import { loadScoringCorpus, groupsForCandidate, loadNovelty } from '../lib/corpus.js';
import { EDIT_FIELD_TO_CLIENT, resolveField } from '../lib/resolveField.js';
import { cleanCandidates } from './review.js';

// Inverted once at module load: client field name (camelCase, from the iOS
// edit sheet) -> DB field name. A client field with no entry here is unknown
// to the edit endpoint, not merely un-reviewable (unlike FIELD_TO_CLIENT's
// narrower review-feed set).
const CLIENT_TO_FIELD = Object.fromEntries(
  Object.entries(EDIT_FIELD_TO_CLIENT).map(([dbField, clientField]) => [clientField, dbField]),
);

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

// Fires the full-ensemble extraction for one just-created photo without
// making the request wait on it (#118). Deliberately not `await`ed by the
// caller -- errors are caught right here, never left to become an unhandled
// rejection that would crash the whole process out from under an unrelated
// request. On failure this releases the photo's lease and counts it as a
// normal extraction failure (same fields `runWorker`'s own per-photo catch
// updates), so a photo that fails here is retried by the daily batch worker
// exactly as if the batch had claimed and failed it itself, up to the same
// `extraction_failures` cutoff (#64).
function kickBackgroundExtraction(photo, log) {
  (async () => {
    const voters = await defaultVoters();
    const sharedCtx = await loadSharedContext();
    await processPhoto(photo, voters, sharedCtx, { includeImages: true });
  })().catch((err) => {
    log?.error?.(`[quick-create] background extraction failed for photo ${photo.id}: ${err.message}`);
    return query(
      `UPDATE photos SET extraction_failures = extraction_failures + 1,
              extraction_leased_until = NULL, extraction_leased_by = NULL
       WHERE id = $1`,
      [photo.id],
    ).catch(() => {});
  });
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
    rotationQuarterTurns: row.rotation_quarter_turns,
    reviewState: row.review_state,
    updatedAt: row.updated_at,
  };
}

// Builds the Add Coffee wizard's per-field draft payload from one adjudication
// pass (#75) -- pure over `resolutions`/`candidatesByField`, so #121's "does an
// unresolved roaster still surface a draft" behaviour is unit-testable without
// a live voter ensemble or DB.
//
// #121 (Radu, 2026-09-03): a brand-new roaster name (not yet in vocab, e.g.
// "Spojka") canonicalizes to `null` in adjudicate.js's `canonicalize()` --
// unlike `origin_farm_id`, `roaster_id` carries no raw name through an
// unresolved match (see adjudicate.js's own comment on why farms and roasters
// differ there). `adjudicateField` then reports `decision: 'absent', value:
// null` even though a real raw candidate string exists, and the old loop here
// dropped the field entirely rather than showing it -- so a genuinely new
// roaster saved with `roaster_id: NULL` instead of being offered as a
// confirm-and-create draft. `POST /api/coffees` already get-or-creates an
// unresolved roaster name on save (`resolveField.js`/`getOrCreateVocabEntry`),
// so surfacing the raw string here as `decision: 'draft'` just lets the wizard
// reach that same existing path instead of silently omitting the field.
export function buildExtractFields(resolutions, candidatesByField) {
  const fields = {};
  for (const [dbField, clientField] of Object.entries(EDIT_FIELD_TO_CLIENT)) {
    const resolution = resolutions[dbField];
    const rawValue = pickRawExtractedValue(dbField, candidatesByField);
    const unresolved = !resolution || resolution.value == null;
    const isUnresolvedRoasterDraft = dbField === 'roaster_id' && unresolved && rawValue != null;
    if (unresolved && !isUnresolvedRoasterDraft) continue;
    fields[clientField] = {
      value: rawValue,
      confidence: isUnresolvedRoasterDraft ? 0 : resolution.confidence,
      decision: isUnresolvedRoasterDraft ? 'draft' : resolution.decision,
      candidates: cleanCandidates(candidatesByField[dbField]),
      evidence: candidatesByField[dbField]?.find((c) => c.evidence)?.evidence ?? null,
    };
  }
  return fields;
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
      // #79: flavour notes are a coffee-page (detail) field, deliberately kept
      // out of the compact snapshot row to spare per-row snapshot budget. '' or
      // null both mean "none" — the client shows the section only when non-empty.
      flavorNotes: row.flavor_notes,
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

  // Persisted photo rotation (#73/#57). A human display correction, not an
  // extracted field, so it deliberately skips the resolveField/review
  // machinery entirely and mirrors /favorite instead. The updated_at bump is
  // what carries the correction to every device via the delta sync.
  app.post('/api/coffees/:publicId/rotation', { preHandler: requireIngestToken }, async (req, reply) => {
    const quarterTurns = req.body?.quarterTurns;
    if (!Number.isInteger(quarterTurns) || quarterTurns < 0 || quarterTurns > 3) {
      return reply.code(400).send({ error: 'invalid_quarter_turns', value: quarterTurns ?? null });
    }
    const { rows } = await query(
      `UPDATE coffees
       SET rotation_quarter_turns = $1, updated_at = now()
       WHERE public_id = $2 AND deleted_at IS NULL
       RETURNING public_id, rotation_quarter_turns`,
      [quarterTurns, req.params.publicId],
    );
    const row = rows[0];
    if (!row) return reply.code(404).send({ error: 'coffee_not_found' });
    return { id: row.public_id, rotationQuarterTurns: row.rotation_quarter_turns };
  });

  // Generic per-field edit (PLAN.md §12 #40): the review queue only surfaces
  // extraction-flagged fields, but Radu wants any core field of any coffee
  // editable on demand, with the exact same locked/human-decided/get-or-create
  // machinery the review resolve route uses (`resolveField`, `lib/resolveField.js`)
  // so an edit can never be silently undone by a later adjudication pass.
  app.post('/api/coffees/:publicId/edit', { preHandler: requireIngestToken }, async (req, reply) => {
    const edits = Array.isArray(req.body?.edits)
      ? req.body.edits
      : [{ field: req.body?.field, value: req.body?.value }];
    if (edits.length === 0 || edits.some((e) => !e?.field || !('value' in (e ?? {})))) {
      return reply.code(400).send({ error: 'missing_field_or_value' });
    }

    const { rows } = await query(
      `SELECT co.id AS coffee_id, co.photo_id, p.captured_on
       FROM coffees co JOIN photos p ON p.id = co.photo_id
       WHERE co.public_id = $1 AND co.deleted_at IS NULL`,
      [req.params.publicId],
    );
    const row = rows[0];
    if (!row) return reply.code(404).send({ error: 'coffee_not_found' });

    const dbFields = edits.map((e) => CLIENT_TO_FIELD[e.field]);
    const unknown = edits.find((e, i) => !dbFields[i]);
    if (unknown) return reply.code(400).send({ error: 'unknown_field', field: unknown.field });

    const sharedCtx = await loadSharedContext();
    const ctx = { ...sharedCtx, photoDate: row.captured_on };

    // Applied one at a time (each `resolveField` call is its own DB write),
    // but every resolution is batched into one `applyResolutionsToCoffee` at
    // the end so a multi-field save (e.g. roaster + roaster country together
    // from #42's edit sheet) writes the coffees row once, not once per field.
    const resolutions = {};
    const results = [];
    for (let i = 0; i < edits.length; i++) {
      const dbField = dbFields[i];
      const outcome = await resolveField(row.photo_id, dbField, edits[i].value, ctx);
      if (outcome.error) {
        return reply.code(422).send({ error: outcome.error, field: edits[i].field, value: edits[i].value });
      }
      await query(
        `UPDATE review_items SET status = 'resolved', resolved_value = $3, resolved_at = now()
         WHERE photo_id = $1 AND field = $2 AND status = 'open'`,
        [row.photo_id, dbField, JSON.stringify(outcome.value)],
      );
      resolutions[dbField] = { decision: 'accepted', value: outcome.value };
      // Echo the RAW string the client sent, not `outcome.value` (the
      // denormalized shape). denormalize() returns an OBJECT for price
      // ({amount,currency}), altitude ({min,max}) and profile — and the iOS
      // response DTOs decode `value` as a String, so an object there threw
      // "Decoding failed / not in the correct format" AFTER the write had
      // already succeeded, making a saved coffee/edit look like a failure.
      results.push({ field: edits[i].field, value: edits[i].value });
    }

    await applyResolutionsToCoffee(row.coffee_id, row.photo_id, resolutions, ctx);

    // Roaster country is a property of the ROASTER, not the individual coffee.
    // When it's edited, write it onto the roaster's vocab row and every other
    // coffee of that roaster — so the same roaster can never carry two
    // different countries across coffees, and future coffees of this roaster
    // inherit it automatically (worker.js derives roaster_country_id from
    // roasters.country_id at adjudication time). Read the roaster_id AFTER the
    // apply so a same-save roaster change is reflected. Skip when the coffee
    // has no roaster — there's nothing to cascade through.
    let cascadedCoffees = 0;
    if ('roaster_country_id' in resolutions) {
      const { rows: rc } = await query(`SELECT roaster_id FROM coffees WHERE id = $1`, [row.coffee_id]);
      const roasterId = rc[0]?.roaster_id ?? null;
      const countryId = resolutions.roaster_country_id.value ?? null;
      if (roasterId != null) {
        await query(`UPDATE roasters SET country_id = $1 WHERE id = $2`, [countryId, roasterId]);
        const { rowCount } = await query(
          `UPDATE coffees SET roaster_country_id = $1, updated_at = now()
           WHERE roaster_id = $2 AND deleted_at IS NULL AND roaster_country_id IS DISTINCT FROM $1`,
          [countryId, roasterId],
        );
        cascadedCoffees = rowCount ?? 0;
      }
    }

    return { id: req.params.publicId, edits: results, roasterCountryCascadedTo: cascadedCoffees };
  });

  // Add Coffee wizard, backend half (PLAN.md §6.8, #75). Reuses the photo
  // upload path (#19) rather than inventing a second one: the client uploads
  // each bag photo via POST /api/photos/manifest + PUT .../image first (the
  // pasted "full text" step goes into that manifest call's caption/description,
  // exactly like a normal ingested photo), then hands the resulting photoIds
  // here. `photoIds[0]` is the primary/front photo -- its stored text is what
  // gets extracted from and, on save, becomes the coffee's photo_id; any other
  // photoIds (e.g. a back-of-bag shot) only contribute extra images to the
  // vision voters.
  //
  // Synchronous and read-only: no `extractions`/`field_candidates` rows are
  // written, since a draft the human hasn't confirmed yet has nothing worth
  // caching -- unlike the batch worker, this call is never repeated with an
  // unchanged input_sha.
  app.post('/api/coffees/extract', { preHandler: requireIngestToken }, async (req, reply) => {
    const photoIds = Array.isArray(req.body?.photoIds) ? req.body.photoIds : [];
    if (photoIds.length === 0) return reply.code(400).send({ error: 'missing_photo_ids' });

    const { rows: photoRows } = await query(`SELECT * FROM photos WHERE public_id = ANY($1)`, [photoIds]);
    const byPublicId = new Map(photoRows.map((p) => [p.public_id, p]));
    const missing = photoIds.find((id) => !byPublicId.has(id));
    if (missing) return reply.code(404).send({ error: 'photo_not_found', photoId: missing });

    const orderedPhotos = photoIds.map((id) => byPublicId.get(id));
    const primaryPhoto = orderedPhotos[0];

    const images = (await Promise.all(orderedPhotos.map((p) => fetchImageBuffer(p)))).filter(Boolean);
    if (images.length === 0) return reply.code(422).send({ error: 'no_images_uploaded' });

    const photoText = await fetchLatestText(primaryPhoto.id);
    const rawText = buildRawText(primaryPhoto, photoText);

    const sharedCtx = await loadSharedContext();
    const vocabShortlist = (sharedCtx.vocab.roasters.candidates ?? []).slice(0, 50).map((r) => r.name);

    const { resolutions, candidatesByField, spentUsd } = await runLightExtraction({
      rawText,
      images,
      vocabShortlist,
      vocab: sharedCtx.vocab,
      photoDate: primaryPhoto.captured_on,
    });

    // Same client field set the generic edit endpoint (#40) accepts, so the
    // confirm screen can reuse the review-queue field component (#27) and
    // SAVE can feed its edits straight back into POST /api/coffees below.
    const fields = buildExtractFields(resolutions, candidatesByField);

    return { fields, spentUsd };
  });

  // Add Coffee: create instantly, extract in the background (#118). Radu:
  // "takes a looong time to extract... should happen in the background, not
  // even sure if i need to keep app on and for how long" -- /extract above
  // makes the wizard wait on a live LLM ensemble before it can even show a
  // confirm screen. This route skips that wait entirely: it creates the
  // coffee from the photo alone (upsertCoffeeBase, no LLM call) and returns
  // immediately with `reviewState: 'unextracted'` -- the same value a coffee
  // already carries before any extraction has ever run (008_coffees.sql's
  // column default), so the client already has everything it needs to render
  // an "extracting..." state with no new field. The actual extraction runs
  // after the response is sent, reusing the exact full-ensemble pipeline the
  // daily batch worker uses for every other photo (`defaultVoters()` +
  // `processPhoto()`) -- so the result the review queue and snapshot sync see
  // is indistinguishable from one the batch worker produced. `photoIds[0]` is
  // the only one the background pass ever extracts from (matches the batch
  // worker's own one-photo-in, one-coffee-out shape); any other photoIds
  // (e.g. a back-of-bag shot) attach for display only, same as SAVE below.
  app.post('/api/coffees/quick-create', { preHandler: requireIngestToken }, async (req, reply) => {
    const photoIds = Array.isArray(req.body?.photoIds) ? req.body.photoIds : [];
    if (photoIds.length === 0) return reply.code(400).send({ error: 'missing_photo_ids' });

    const { rows: photoRows } = await query(`SELECT * FROM photos WHERE public_id = ANY($1)`, [photoIds]);
    const byPublicId = new Map(photoRows.map((p) => [p.public_id, p]));
    const missing = photoIds.find((id) => !byPublicId.has(id));
    if (missing) return reply.code(404).send({ error: 'photo_not_found', photoId: missing });

    const primaryPhoto = byPublicId.get(photoIds[0]);
    if (!primaryPhoto.has_image) return reply.code(422).send({ error: 'photo_missing_image', photoId: photoIds[0] });

    const photoText = await fetchLatestText(primaryPhoto.id);
    const coffee = await upsertCoffeeBase(primaryPhoto, photoText);

    // Any photo beyond the primary (e.g. a second, back-of-bag shot) never
    // reaches a voter here -- the async pipeline is one-photo-in like the
    // batch worker's own claimBatch. Mark them processed right away so they
    // can't later be claimed past their `awaiting_text` deadline and spawn a
    // duplicate coffee row (upsertCoffeeBase keys off photo_id) -- same fix
    // #75's SAVE route already applies to its own photoIds.
    const secondaryIds = photoRows.filter((p) => p.id !== primaryPhoto.id).map((p) => p.id);
    if (secondaryIds.length > 0) {
      await query(`UPDATE photos SET state = 'processed', updated_at = now() WHERE id = ANY($1)`, [secondaryIds]);
    }

    // Lease the primary photo before the background pass starts so the daily
    // batch's `claimBatch` (which only checks `extraction_leased_until IS
    // NULL`) can't also grab it while this run is in flight -- the same
    // mutual-exclusion field the batch worker uses for itself.
    // `processPhoto()` clears this lease itself once it finishes.
    await query(
      `UPDATE photos SET extraction_leased_until = now() + interval '10 minutes', extraction_leased_by = 'quick-create'
       WHERE id = $1`,
      [primaryPhoto.id],
    );

    kickBackgroundExtraction(primaryPhoto, req.log);

    return reply.code(201).send({ id: coffee.public_id, reviewState: coffee.review_state });
  });

  // "Evaluate this coffee" (#106): score a bag Radu doesn't own yet for fit
  // with what he actually buys. Reuses the exact same photo -> OCR -> light-
  // extraction path as /extract above -- no new extraction work, just
  // canonicalized-value lookups against the rated corpus plus
  // backend/src/lib/scoring.js's blend. Read-only: nothing is written, same
  // as /extract.
  //
  // IMPORTANT, per #106's own pre-design validation (full numbers in
  // status/backend.md): this is a "fit with what you buy" number, not a
  // predicted rating. Flavour notes and altitude carry no usable signal
  // (LOO r=-0.01 / -0.02) and 58% of the corpus is rated exactly 4.0, so this
  // deliberately does NOT try to predict a rating -- it blends only the four
  // signals that measurably do (origin/roaster/process/roaster-country) and
  // suppresses the headline number under `scoring.js`'s confidence gate
  // rather than inventing one. Building this endpoint is not "shipping" the
  // feature -- #106 explicitly gates the on-device rollout on Radu reviewing
  // a sample of real evaluations first.
  app.post('/api/coffees/evaluate', { preHandler: requireIngestToken }, async (req, reply) => {
    const photoIds = Array.isArray(req.body?.photoIds) ? req.body.photoIds : [];
    if (photoIds.length === 0) return reply.code(400).send({ error: 'missing_photo_ids' });

    const { rows: photoRows } = await query(`SELECT * FROM photos WHERE public_id = ANY($1)`, [photoIds]);
    const byPublicId = new Map(photoRows.map((p) => [p.public_id, p]));
    const missing = photoIds.find((id) => !byPublicId.has(id));
    if (missing) return reply.code(404).send({ error: 'photo_not_found', photoId: missing });

    const orderedPhotos = photoIds.map((id) => byPublicId.get(id));
    const primaryPhoto = orderedPhotos[0];

    const images = (await Promise.all(orderedPhotos.map((p) => fetchImageBuffer(p)))).filter(Boolean);
    if (images.length === 0) return reply.code(422).send({ error: 'no_images_uploaded' });

    const photoText = await fetchLatestText(primaryPhoto.id);
    const rawText = buildRawText(primaryPhoto, photoText);

    const sharedCtx = await loadSharedContext();
    const vocabShortlist = (sharedCtx.vocab.roasters.candidates ?? []).slice(0, 50).map((r) => r.name);

    const { resolutions, spentUsd } = await runLightExtraction({
      rawText,
      images,
      vocabShortlist,
      vocab: sharedCtx.vocab,
      photoDate: primaryPhoto.captured_on,
    });

    const roasterId = resolutions.roaster_id?.value ?? null;
    const originCountryIds = resolutions.origin_country_ids?.value ?? [];
    const originCountryId = originCountryIds[0] ?? null;
    // `parseProfile` returns a SLUG string ("washed", "co_fermented") -- #136
    // documents this for the iOS DTO -- but `coffees.profile_id` is a SMALLINT
    // FK to `profiles(id)`, so the corpus stats are keyed numerically. The
    // persist path maps between them (`worker.js:159`); this route did not, so
    // `processStats.get("washed")` was ALWAYS undefined and the process signal
    // (r=0.30, one of only four) contributed nothing to any score this endpoint
    // has ever returned -- while also holding the confidence gate down, since
    // `CONFIDENCE_GATE_SIGNALS` counts process as unseen. Fixed 2026-09-09 while
    // building #160, which reuses this scoring path. The response keeps the slug:
    // #136's `EvaluateFieldsDTO` decodes `fields.profileId` as a String.
    const profileId = resolutions.profile?.value?.profileId ?? null;
    const profileDbId = profileId != null ? (sharedCtx.profileIdBySlug?.get(profileId) ?? null) : null;

    let roasterCountryId = null;
    if (roasterId != null) {
      const { rows } = await query(`SELECT country_id FROM roasters WHERE id = $1`, [roasterId]);
      roasterCountryId = rows[0]?.country_id ?? null;
    }

    // FX conversion isn't wired into canonicalize()/adjudicateField() (it only
    // happens on persist, in applyResolutionsToCoffee) -- a draft that's never
    // saved has to do it here, the same way worker.js's buildCoffeeColumnUpdates
    // does for the real save path.
    let pricePer100gEur = null;
    const priceValue = resolutions.price?.value;
    const weightG = resolutions.weight_g?.value ?? null;
    if (priceValue?.amount != null && priceValue?.currency && weightG > 0) {
      const conv = toEur(
        { amount: priceValue.amount, currency: priceValue.currency, date: primaryPhoto.captured_on },
        sharedCtx.fxRates,
      );
      if (conv?.priceEur != null) {
        pricePer100gEur = Math.round((conv.priceEur / weightG) * 100 * 100) / 100;
      }
    }

    // Shared with #160's POST /api/score -- one loader so the app and the
    // browser extension can never score the same bag differently (lib/corpus.js).
    const { globalMean, pricedRows, stats, affinitySamples } = await loadScoringCorpus();

    const draftGroups = groupsForCandidate(stats, { roasterId, originCountryId, profileId: profileDbId, roasterCountryId });
    const { isNewRoaster, isNewOrigin } = await loadNovelty({ roasterId, originCountryId });

    const evaluation = evaluateCoffee({
      groups: draftGroups,
      globalMean,
      priced: pricedRows,
      affinitySamples,
      pricePer100gEur,
      isNewRoaster,
      isNewOrigin,
    });

    return {
      fields: { roasterId, originCountryIds, profileId, roasterCountryId, pricePer100gEur },
      evaluation,
      spentUsd,
    };
  });

  // SAVE (PLAN.md §6.8, #75): persists the coffee the wizard just built. Every
  // field goes through the exact same `resolveField`/`applyResolutionsToCoffee`
  // machinery the generic edit endpoint (#40) uses, so a human-confirmed field
  // lands `locked=true`/`decided_by='human'` -- the monthly incremental
  // extraction pass can never silently overwrite it (PLAN.md §1).
  //
  // Idempotent on `photoIds[0]`: `upsertCoffeeBase` returns the existing row
  // if a coffee for that photo already exists (a retried SAVE after a dropped
  // connection just re-applies the same fields rather than erroring).
  app.post('/api/coffees', { preHandler: requireIngestToken }, async (req, reply) => {
    const photoIds = Array.isArray(req.body?.photoIds) ? req.body.photoIds : [];
    const edits = Array.isArray(req.body?.fields) ? req.body.fields : [];
    if (photoIds.length === 0) return reply.code(400).send({ error: 'missing_photo_ids' });

    const { rows: photoRows } = await query(`SELECT * FROM photos WHERE public_id = ANY($1)`, [photoIds]);
    const byPublicId = new Map(photoRows.map((p) => [p.public_id, p]));
    const missing = photoIds.find((id) => !byPublicId.has(id));
    if (missing) return reply.code(404).send({ error: 'photo_not_found', photoId: missing });

    const primaryPhoto = byPublicId.get(photoIds[0]);
    if (!primaryPhoto.has_image) return reply.code(422).send({ error: 'photo_missing_image', photoId: photoIds[0] });

    const dbFields = edits.map((e) => CLIENT_TO_FIELD[e?.field]);
    const unknown = edits.find((e, i) => !dbFields[i]);
    if (unknown) return reply.code(400).send({ error: 'unknown_field', field: unknown.field });

    const photoText = await fetchLatestText(primaryPhoto.id);
    const coffee = await upsertCoffeeBase(primaryPhoto, photoText);

    const sharedCtx = await loadSharedContext();
    const ctx = { ...sharedCtx, photoDate: primaryPhoto.captured_on, rawText: buildRawText(primaryPhoto, photoText) };

    const resolutions = {};
    const results = [];
    for (let i = 0; i < edits.length; i++) {
      const dbField = dbFields[i];
      const outcome = await resolveField(primaryPhoto.id, dbField, edits[i].value, ctx);
      if (outcome.error) {
        return reply.code(422).send({ error: outcome.error, field: edits[i].field, value: edits[i].value });
      }
      resolutions[dbField] = { decision: 'accepted', value: outcome.value };
      // Echo the RAW string the client sent, not `outcome.value` (the
      // denormalized shape). denormalize() returns an OBJECT for price
      // ({amount,currency}), altitude ({min,max}) and profile — and the iOS
      // response DTOs decode `value` as a String, so an object there threw
      // "Decoding failed / not in the correct format" AFTER the write had
      // already succeeded, making a saved coffee/edit look like a failure.
      results.push({ field: edits[i].field, value: edits[i].value });
    }

    await applyResolutionsToCoffee(coffee.id, primaryPhoto.id, resolutions, ctx);

    // Every photo behind this coffee (front + any back/detail shots) is
    // marked processed so the daily worker's claimBatch eligibility predicate
    // excludes them -- without this a back-of-bag photo with no caption of
    // its own would sit `awaiting_text`, get claimed once its 10-day deadline
    // passed, and spawn its own duplicate coffee row (upsertCoffeeBase keys
    // off photo_id).
    await query(`UPDATE photos SET state = 'processed', updated_at = now() WHERE id = ANY($1)`, [
      photoRows.map((p) => p.id),
    ]);

    return reply.code(201).send({ id: coffee.public_id, fields: results });
  });
}
