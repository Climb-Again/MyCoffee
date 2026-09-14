// #152 (option A) — the roaster content WRITE path: blurb + logo from the app.
//
// Read path has existed since #132/#133/#134 (`loadRoasterVocab` selects
// `blurb, logo_url`, the snapshot carries both, Swift decodes them). Until now
// content could only enter through the `ops/roaster-assets/` chat + GitHub
// flow, which the phone cannot use: the app cannot commit to a git repo. That
// is the whole reason this row existed, and why "keep serving from
// raw.githubusercontent.com" was never an option for an in-app upload.
//
// Auth: INGEST_TOKEN on both verbs — these are writes, and the app already
// holds that token in the Keychain for the edit endpoints.
//
// Keyed on `slug`, the stable public key the snapshot already carries, so the
// client needs no id it doesn't have.
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';

import { requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { config } from '../config.js';
import { storeRoasterLogo, logoRelPath, LOGO_MAX_UPLOAD_BYTES } from '../lib/roasterAssets.js';

// A blurb is 2-4 sentences of prose (the shipped 64 average ~300 chars). 4 KB
// is generous and stops a paste of a whole About page.
const MAX_BLURB_BYTES = 4096;

// The public URL the snapshot hands to the app. Stable and unsigned — see the
// header comment in lib/roasterAssets.js for why that differs from /media.
export function roasterLogoUrl(baseUrl, slug) {
  return `${baseUrl}/roaster-logos/${slug}.webp`;
}

export default async function roasterRoutes(app) {
  // Unauthenticated, like /media — SwiftUI's AsyncImage cannot attach a bearer
  // header. Unlike /media there is no signature: a brand mark served publicly
  // from GitHub raw since #133 gains nothing from one, and an expiring URL
  // would break logos cached in the snapshot vocab between syncs.
  app.get('/roaster-logos/:slugFile', async (req, reply) => {
    const m = /^([a-z0-9][a-z0-9-]{0,98})\.webp$/.exec(req.params.slugFile || '');
    if (!m) return reply.code(404).send({ error: 'not_found' });

    const { rows } = await query(
      `SELECT l.storage_path
         FROM roaster_logos l JOIN roasters r ON r.id = l.roaster_id
        WHERE r.slug = $1`,
      [m[1]],
    );
    if (!rows[0]) return reply.code(404).send({ error: 'not_found' });

    const abs = path.join(config.dataDir, rows[0].storage_path);
    let size;
    try {
      size = (await stat(abs)).size;
    } catch {
      return reply.code(404).send({ error: 'not_found' });
    }

    return reply
      .header('Content-Type', 'image/webp')
      .header('Content-Length', size)
      // Content-addressed on disk, so the bytes behind one URL only change
      // when the logo itself does — and then the row's `updated_at` moves and
      // the app re-syncs. Long cache, revalidate cheaply.
      .header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800')
      .send(createReadStream(abs));
  });

  // PATCH /api/roasters/:slug { blurb } — the text half.
  app.patch('/api/roasters/:slug', { preHandler: requireIngestToken }, async (req, reply) => {
    const blurb = typeof req.body?.blurb === 'string' ? req.body.blurb.trim() : null;
    if (blurb == null) return reply.code(400).send({ error: 'missing_blurb' });
    if (Buffer.byteLength(blurb, 'utf8') > MAX_BLURB_BYTES) {
      return reply.code(400).send({ error: 'blurb_too_large' });
    }

    // Empty string clears it — the editor (#153) needs a way to undo a bad
    // paste, and NULL is what "no blurb" means everywhere else.
    const value = blurb.length > 0 ? blurb : null;
    const { rows } = await query(
      `UPDATE roasters
          SET blurb = $1, content_source = 'app'
        WHERE slug = $2
        RETURNING id, slug, name, blurb`,
      [value, req.params.slug],
    );
    if (!rows[0]) return reply.code(404).send({ error: 'roaster_not_found' });
    return { roaster: rows[0] };
  });

  // PUT /api/roasters/:slug/logo — raw image body, same shape as
  // PUT /api/photos/:sourceId/image. Normalized to <=512px WebP server-side
  // (matching ops/normalize-logos.py) so a phone photo of a shop sign cannot
  // land as a 4 MB original.
  app.put(
    '/api/roasters/:slug/logo',
    { preHandler: requireIngestToken, bodyLimit: LOGO_MAX_UPLOAD_BYTES },
    async (req, reply) => {
      const body = req.body;
      if (!Buffer.isBuffer(body) || body.length === 0) {
        return reply.code(400).send({ error: 'missing_image_body' });
      }

      const { rows: rr } = await query(`SELECT id, slug FROM roasters WHERE slug = $1`, [req.params.slug]);
      const roaster = rr[0];
      if (!roaster) return reply.code(404).send({ error: 'roaster_not_found' });

      let stored;
      try {
        stored = await storeRoasterLogo(body);
      } catch {
        // sharp throws on anything that isn't a decodable image. A 400 says
        // "that file isn't a picture", which is the user's problem to fix;
        // a 500 would say it's ours.
        return reply.code(400).send({ error: 'unreadable_image' });
      }

      await query(
        `INSERT INTO roaster_logos (roaster_id, sha256, bytes, width, height, storage_path, updated_at)
              VALUES ($1, $2, $3, $4, $5, $6, now())
         ON CONFLICT (roaster_id) DO UPDATE
            SET sha256 = EXCLUDED.sha256, bytes = EXCLUDED.bytes, width = EXCLUDED.width,
                height = EXCLUDED.height, storage_path = EXCLUDED.storage_path, updated_at = now()`,
        [roaster.id, stored.sha256, stored.bytes, stored.width, stored.height, stored.storagePath],
      );

      // Point the vocab at our own host. This is what supersedes the
      // raw.githubusercontent.com URL for this roaster — #152's "does an
      // in-app write become source of truth over ops/" decision, answered yes.
      const baseUrl = `${req.protocol}://${req.hostname}`;
      const url = roasterLogoUrl(baseUrl, roaster.slug);
      await query(`UPDATE roasters SET logo_url = $1, content_source = 'app' WHERE id = $2`, [url, roaster.id]);

      return reply.code(stored.deduped ? 200 : 201).send({
        slug: roaster.slug,
        logoUrl: url,
        bytes: stored.bytes,
        width: stored.width,
        height: stored.height,
        deduped: stored.deduped,
      });
    },
  );
}
