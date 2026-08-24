// The human side of adjudication (PLAN.md §2/§4): whatever adjudicate.js
// couldn't decide alone lands in `review_items`; resolving one here writes a
// `locked` field_resolutions row so no later pass -- including the monthly
// incremental run -- ever silently undoes the decision (PLAN.md §1).
//
//   GET  /api/review        open items, oldest first
//   POST /api/review/:id    resolve (value) or dismiss (dismiss: true)
//   POST /api/review/bulk   the same, for many ids at once
//   POST /api/review/rules  persist a roaster/country/farm alias -- the
//                           highest-leverage endpoint in the system: every
//                           future import inherits the correction for free.
import { requireAnyToken, requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { buildMediaUrl } from '../media.js';
import { normalizeVocabString } from '../lib/normalize.js';
import { loadSharedContext, applyResolutionsToCoffee } from '../lib/worker.js';
import { FIELD_TO_CLIENT, resolveField, slugify } from '../lib/resolveField.js';

export { slugify };

const ALIAS_TABLES = {
  roaster: { table: 'roaster_aliases', fk: 'roaster_id' },
  country: { table: 'country_aliases', fk: 'country_id' },
  farm: { table: 'farm_aliases', fk: 'farm_id' },
};

// Signed review thumbnails are one-shot deep links the reviewer taps within a
// session, so a long TTL only avoids a needless mid-review 403; mirror the
// detail route's 30-day window.
const REVIEW_URL_TTL_SECONDS = 30 * 24 * 60 * 60;

// FIELD_TO_CLIENT (imported above, from `lib/resolveField.js`) maps the DB
// fields the review UI knows how to render onto the client enum's raw value.
// DB fields with no client equivalent (rating, roasted_on, roaster_country_id,
// the desc_* prose spans) are filtered out of the feed rather than sent as
// un-actionable cards -- see that module for why `roaster_country_id`
// specifically is a review-feed exclusion but not an edit-endpoint one.

const REASON_LABELS = {
  split: 'voters disagreed',
  prose_spread: 'ambiguous text selection',
  // Legacy — pre-#35 review items could carry these; a re-adjudication pass
  // closes them, but a stale open row from before that pass should still
  // render a sane label rather than the raw reason string.
  below_threshold: 'low confidence',
  no_candidates: 'no clear value found',
};

// The stored `candidates` are raw voter outputs: some are objects (prose
// `{start,end}` spans), some are whole-caption dumps from the rules voter.
// Keep only short, single-line, human-pickable strings, de-duplicated and
// order-preserving (the extractor/reconciler values lead), capped at six.
export function cleanCandidates(raw) {
  const seen = new Set();
  const out = [];
  for (const c of raw ?? []) {
    let v = c?.value;
    if (v == null || typeof v === 'object') continue;
    v = String(v).trim();
    if (!v || v.length > 80 || v.includes('\n')) continue;
    const key = v.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ value: v });
    if (out.length >= 6) break;
  }
  return out;
}

function baseUrlFor(req) {
  return `${req.protocol}://${req.hostname}`;
}

export default async function reviewRoutes(app) {
  app.get('/api/review', { preHandler: requireAnyToken }, async (req) => {
    const limit = Math.min(Math.max(Number.parseInt(req.query?.limit, 10) || 50, 1), 200);
    const offset = Math.max(Number.parseInt(req.query?.offset, 10) || 0, 0);

    // Only fields the app can review, and only rows offset..offset+limit of
    // that filtered set — the filtering happens in SQL so `total` and paging
    // both count client-reviewable items, not the raw open set.
    const clientFields = Object.keys(FIELD_TO_CLIENT);
    const [{ rows: items }, {
      rows: [{ count }],
    }] = await Promise.all([
      query(
        `SELECT ri.id, ri.field, ri.reason, ri.candidates, ri.created_at,
                co.public_id AS coffee_public_id,
                co.raw_title, co.raw_caption, co.raw_description,
                p.public_id AS photo_public_id
         FROM review_items ri
         JOIN photos p ON p.id = ri.photo_id
         LEFT JOIN coffees co ON co.photo_id = ri.photo_id
         WHERE ri.status = 'open' AND ri.field = ANY($3)
         ORDER BY ri.created_at ASC
         LIMIT $1 OFFSET $2`,
        [limit, offset, clientFields],
      ),
      query(`SELECT count(*) FROM review_items WHERE status = 'open' AND field = ANY($1)`, [clientFields]),
    ]);

    const baseUrl = baseUrlFor(req);
    const mapped = items
      .map((r) => {
        const candidates = cleanCandidates(r.candidates);
        // A row whose candidates were all dumps/spans has nothing pickable —
        // drop it rather than show an empty card (the human can still find the
        // coffee via the "needs review" badge and edit it there).
        if (candidates.length === 0) return null;
        return {
          id: String(r.id),
          coffeeId: r.coffee_public_id,
          photoId: r.photo_public_id,
          field: FIELD_TO_CLIENT[r.field],
          reason: REASON_LABELS[r.reason] ?? r.reason,
          candidates,
          // Full scraped context so the reviewer can adjudicate from the source
          // text, not just the extracted candidate values.
          rawTitle: r.raw_title,
          rawCaption: r.raw_caption,
          rawDescription: r.raw_description,
          // Signed thumbnail of the source photo (the OCR/caption came from it).
          thumbUrl: buildMediaUrl(baseUrl, r.photo_public_id, 'thumb', REVIEW_URL_TTL_SECONDS),
          createdAt: r.created_at,
        };
      })
      .filter(Boolean);

    return { total: Number(count), limit, offset, items: mapped };
  });

  app.post('/api/review/:id', { preHandler: requireIngestToken }, async (req, reply) => {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isInteger(id)) return reply.code(400).send({ error: 'invalid_id' });

    const { rows } = await query(`SELECT * FROM review_items WHERE id = $1 AND status = 'open'`, [id]);
    const item = rows[0];
    if (!item) return reply.code(404).send({ error: 'review_item_not_found' });

    if (req.body?.dismiss) {
      await query(`UPDATE review_items SET status = 'dismissed', resolved_at = now() WHERE id = $1`, [id]);
      return { id, status: 'dismissed' };
    }

    if (!('value' in (req.body ?? {}))) return reply.code(400).send({ error: 'missing_value' });

    // The app sends the human's raw picked/typed string. For id/structured
    // fields that string must be canonicalised into the exact shape the
    // extraction pipeline stores (roaster_id -> int, price -> {amount,currency},
    // ...) before it can be written -- storing the bare string would corrupt
    // the coffees row. Canonicalise with the SAME machinery adjudication uses
    // (`resolveField`, shared with the generic edit endpoint — #40).
    const { rows: photoRows } = await query(`SELECT captured_on FROM photos WHERE id = $1`, [item.photo_id]);
    const photoDate = photoRows[0]?.captured_on;
    const sharedCtx = await loadSharedContext();
    const canonicalCtx = { ...sharedCtx, photoDate };

    const outcome = await resolveField(item.photo_id, item.field, req.body.value, canonicalCtx);
    // Any unresolvable structured value (an unknown country, an unparseable
    // price/altitude/...) still refuses rather than writing a broken value.
    // The item stays open; the reviewer can pick a different candidate or
    // dismiss.
    if (outcome.error) {
      return reply.code(422).send({ error: outcome.error, field: item.field, value: req.body.value });
    }
    const value = outcome.value;

    await query(`UPDATE review_items SET status = 'resolved', resolved_value = $2, resolved_at = now() WHERE id = $1`, [
      id,
      JSON.stringify(value),
    ]);

    const { rows: coffeeRows } = await query(
      `SELECT id AS coffee_id FROM coffees WHERE photo_id = $1`,
      [item.photo_id],
    );
    const coffee = coffeeRows[0];
    if (coffee) {
      await applyResolutionsToCoffee(
        coffee.coffee_id,
        item.photo_id,
        { [item.field]: { decision: 'accepted', value } },
        canonicalCtx,
      );
    }

    return { id, status: 'resolved', field: item.field, value };
  });

  app.post('/api/review/bulk', { preHandler: requireIngestToken }, async (req, reply) => {
    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items || items.length === 0) return reply.code(400).send({ error: 'missing_items' });

    const results = [];
    for (const entry of items) {
      const res = await app.inject({
        method: 'POST',
        url: `/api/review/${entry.id}`,
        headers: { authorization: req.headers.authorization },
        payload: entry.dismiss ? { dismiss: true } : { value: entry.value },
      });
      results.push({ id: entry.id, statusCode: res.statusCode, ...(res.statusCode === 200 ? res.json() : {}) });
    }
    return { results };
  });

  app.post('/api/review/rules', { preHandler: requireIngestToken }, async (req, reply) => {
    const kind = req.body?.kind;
    const canonicalId = req.body?.canonicalId;
    const alias = req.body?.alias;
    const spec = ALIAS_TABLES[kind];
    if (!spec || canonicalId == null || !alias) return reply.code(400).send({ error: 'invalid_rule' });

    const aliasNorm = normalizeVocabString(alias);
    if (!aliasNorm) return reply.code(400).send({ error: 'invalid_rule' });

    await query(
      `INSERT INTO ${spec.table} (${spec.fk}, alias, alias_norm) VALUES ($1, $2, $3)
       ON CONFLICT (alias_norm) DO UPDATE SET ${spec.fk} = EXCLUDED.${spec.fk}, alias = EXCLUDED.alias`,
      [canonicalId, alias, aliasNorm],
    );

    return { ok: true, kind, canonicalId, aliasNorm };
  });
}
