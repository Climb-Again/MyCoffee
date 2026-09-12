// GET /api/whatsnew — curated "what's live / what's planned" content for the
// in-app What's New screen (PLAN.md §13). Content lives in the committed
// backend/src/data/whatsnew.json, not a live backlog dump — keep it in sync
// with status/BACKLOG.md by hand whenever a row flips.
//
// GET/POST /api/whatsnew/seen — #201: per-user checked-off state, shared
// across Radu's devices (phone ↔ iPad). One shared token today means one
// shared seen set; the key is a client-side hash of title+detail (see
// migration 036 for why), so the server treats keys as opaque strings.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { requireAnyToken, requireIngestToken } from '../auth.js';
import { query } from '../db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_PATH = path.join(__dirname, '..', 'data', 'whatsnew.json');
const content = JSON.parse(readFileSync(DATA_PATH, 'utf8'));

// Bound the payload so a runaway client that keeps POSTing garbage cannot
// grow the table indefinitely. 4 KB per key is comically generous for what
// is meant to be an 8-char hex hash.
const MAX_KEY_LENGTH = 4096;

export default async function whatsnewRoutes(app) {
  app.get('/api/whatsnew', { preHandler: requireAnyToken }, async () => content);

  app.get('/api/whatsnew/seen', { preHandler: requireAnyToken }, async () => {
    const { rows } = await query(`SELECT entry_key FROM whatsnew_seen`);
    return { seen: rows.map((r) => r.entry_key) };
  });

  // { key: string, seen?: boolean } — seen defaults to true. A missing key or
  // one over the size cap is a 400; anything else is a 200 with the fresh set
  // so the client can reconcile in one round-trip. Idempotent by ON CONFLICT
  // so a retry after a network flake never doubles anything.
  app.post('/api/whatsnew/seen', { preHandler: requireIngestToken }, async (req, reply) => {
    const key = typeof req.body?.key === 'string' ? req.body.key : null;
    const seen = req.body?.seen !== false;
    if (!key || key.length === 0 || key.length > MAX_KEY_LENGTH) {
      return reply.code(400).send({ error: 'bad_key' });
    }

    if (seen) {
      await query(
        `INSERT INTO whatsnew_seen (entry_key, seen_at) VALUES ($1, NOW())
           ON CONFLICT (entry_key) DO UPDATE SET seen_at = EXCLUDED.seen_at`,
        [key],
      );
    } else {
      await query(`DELETE FROM whatsnew_seen WHERE entry_key = $1`, [key]);
    }

    const { rows } = await query(`SELECT entry_key FROM whatsnew_seen`);
    return { seen: rows.map((r) => r.entry_key) };
  });
}
