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
import { normalizeVocabString } from '../lib/normalize.js';
import { loadSharedContext, applyResolutionsToCoffee } from '../lib/worker.js';

const ALIAS_TABLES = {
  roaster: { table: 'roaster_aliases', fk: 'roaster_id' },
  country: { table: 'country_aliases', fk: 'country_id' },
  farm: { table: 'farm_aliases', fk: 'farm_id' },
};

export default async function reviewRoutes(app) {
  app.get('/api/review', { preHandler: requireAnyToken }, async (req) => {
    const limit = Math.min(Math.max(Number.parseInt(req.query?.limit, 10) || 50, 1), 200);
    const offset = Math.max(Number.parseInt(req.query?.offset, 10) || 0, 0);

    const [{ rows: items }, {
      rows: [{ count }],
    }] = await Promise.all([
      query(
        `SELECT ri.id, ri.field, ri.reason, ri.candidates, ri.created_at,
                co.public_id AS coffee_public_id, p.public_id AS photo_public_id
         FROM review_items ri
         JOIN photos p ON p.id = ri.photo_id
         LEFT JOIN coffees co ON co.photo_id = ri.photo_id
         WHERE ri.status = 'open'
         ORDER BY ri.created_at ASC
         LIMIT $1 OFFSET $2`,
        [limit, offset],
      ),
      query(`SELECT count(*) FROM review_items WHERE status = 'open'`),
    ]);

    return {
      total: Number(count),
      limit,
      offset,
      items: items.map((r) => ({
        id: r.id,
        coffeeId: r.coffee_public_id,
        photoId: r.photo_public_id,
        field: r.field,
        reason: r.reason,
        candidates: r.candidates,
        createdAt: r.created_at,
      })),
    };
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
    const value = req.body.value;

    // `locked = true`, `decided_by = 'human'` -- PLAN.md §1's single most
    // important invariant: no later adjudication pass touches this field again.
    await query(
      `INSERT INTO field_resolutions (photo_id, field, value, confidence, agreement, voters, decided_by, locked)
       VALUES ($1, $2, $3, 1, 1, '{human}', 'human', true)
       ON CONFLICT (photo_id, field) DO UPDATE SET
         value = EXCLUDED.value, confidence = 1, agreement = 1, voters = '{human}',
         decided_by = 'human', locked = true, decided_at = now()`,
      [item.photo_id, item.field, JSON.stringify(value)],
    );
    await query(`UPDATE review_items SET status = 'resolved', resolved_value = $2, resolved_at = now() WHERE id = $1`, [
      id,
      JSON.stringify(value),
    ]);

    const { rows: coffeeRows } = await query(
      `SELECT co.id AS coffee_id, p.captured_on FROM coffees co JOIN photos p ON p.id = co.photo_id WHERE co.photo_id = $1`,
      [item.photo_id],
    );
    const coffee = coffeeRows[0];
    if (coffee) {
      const sharedCtx = await loadSharedContext();
      await applyResolutionsToCoffee(
        coffee.coffee_id,
        item.photo_id,
        { [item.field]: { decision: 'accepted', value } },
        { ...sharedCtx, photoDate: coffee.captured_on },
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
