// GET/POST /api/history — #194: backend-backed shortlist so the extension's
// Top-coffees list (#187) syncs across browsers and can be read from iOS later
// (#195). See migration 037 for the table and the token-hash rationale.
//
// Auth: INGEST_TOKEN on both verbs. The shortlist is a single, private list;
// keying it on the presented bearer's hash means a read and a write from the
// same token land on the same rows. Requiring the write token for the read too
// is deliberate — otherwise a browser presenting APP_TOKEN would hash to a
// different key and see an empty list, which reads as data loss.
import { createHash } from 'node:crypto';
import { requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { historyKey, RETENTION_DAYS, MAX_ENTRIES } from '../lib/history.js';

// One row's JSON. entryFromScore renders ~15 short scalar fields plus an image
// URL; 8 KB is generous and stops a runaway client from storing a page's text.
const MAX_PAYLOAD_BYTES = 8192;

// The bearer is already validated by requireIngestToken; hash it so the DB key
// never carries the plaintext token.
function tokenHash(req) {
  const header = req.headers['authorization'] || req.headers['Authorization'] || '';
  const m = /^Bearer\s+(.+)$/i.exec(String(header).trim());
  return m ? createHash('sha256').update(m[1]).digest('hex') : null;
}

// The list every response returns: this token's live rows, newest first.
// Retention is filtered here too (not only deleted on write) so a row that has
// just crossed the cutoff never surfaces, even before the next prune deletes it.
async function liveEntries(hash) {
  const { rows } = await query(
    `SELECT payload FROM history
       WHERE token_hash = $1
         AND saved_at > NOW() - ($2 || ' days')::interval
       ORDER BY saved_at DESC
       LIMIT $3`,
    [hash, String(RETENTION_DAYS), MAX_ENTRIES],
  );
  return rows.map((r) => r.payload);
}

// Prune-on-write (#187): drop rows past the retention window and any beyond the
// per-token cap, so a client closed for 10 days cannot un-prune on next sync.
async function pruneToken(hash) {
  await query(
    `DELETE FROM history
       WHERE token_hash = $1
         AND saved_at <= NOW() - ($2 || ' days')::interval`,
    [hash, String(RETENTION_DAYS)],
  );
  await query(
    `DELETE FROM history
       WHERE token_hash = $1
         AND url_key NOT IN (
           SELECT url_key FROM history
             WHERE token_hash = $1
             ORDER BY saved_at DESC
             LIMIT $2
         )`,
    [hash, MAX_ENTRIES],
  );
}

export default async function historyRoutes(app) {
  app.get('/api/history', { preHandler: requireIngestToken }, async (req) => {
    const hash = tokenHash(req);
    await pruneToken(hash);
    return { entries: await liveEntries(hash) };
  });

  // Body: one entry in entryFromScore's shape, which must carry `url`. The
  // server derives url_key, stamps saved_at with its own clock (so retention
  // and the client's savedAt agree on one authority), upserts by
  // (token_hash, url_key) — a revisit replaces, never duplicates — prunes, and
  // returns the fresh list so the client reconciles in one round-trip.
  app.post('/api/history', { preHandler: requireIngestToken }, async (req, reply) => {
    const entry = req.body;
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      return reply.code(400).send({ error: 'bad_entry' });
    }
    const url = typeof entry.url === 'string' ? entry.url : null;
    const urlKey = url ? historyKey(url) : '';
    if (!urlKey) {
      return reply.code(400).send({ error: 'bad_url' });
    }

    const now = Date.now();
    const payload = { ...entry, savedAt: now };
    if (Buffer.byteLength(JSON.stringify(payload), 'utf8') > MAX_PAYLOAD_BYTES) {
      return reply.code(400).send({ error: 'payload_too_large' });
    }

    const hash = tokenHash(req);
    await query(
      `INSERT INTO history (token_hash, url_key, saved_at, payload)
         VALUES ($1, $2, to_timestamp($3::double precision / 1000.0), $4::jsonb)
         ON CONFLICT (token_hash, url_key)
         DO UPDATE SET saved_at = EXCLUDED.saved_at, payload = EXCLUDED.payload`,
      [hash, urlKey, now, JSON.stringify(payload)],
    );
    await pruneToken(hash);
    return { entries: await liveEntries(hash) };
  });

  // The popup's "Clear" button. Without this, clearing only the browser's
  // local cache would be undone by the next sync pulling the list back.
  app.delete('/api/history', { preHandler: requireIngestToken }, async (req) => {
    await query(`DELETE FROM history WHERE token_hash = $1`, [tokenHash(req)]);
    return { entries: [] };
  });
}
