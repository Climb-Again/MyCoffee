// GET /media/:publicId/:variant.jpg?exp=&sig= — unauthenticated, signature-
// guarded image serving. No bearer token: SwiftUI's AsyncImage can't attach
// an Authorization header, so the URL itself carries a time-limited HMAC
// signature instead (PLAN.md §3, src/media.js).
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';

import { query } from '../db.js';
import { config } from '../config.js';
import { verifyMediaSignature, VARIANTS } from '../media.js';

export default async function mediaRoutes(app) {
  app.get('/media/:publicId/:variantFile', async (req, reply) => {
    const { publicId, variantFile } = req.params;
    const m = /^([a-z]+)\.jpg$/.exec(variantFile);
    if (!m || !VARIANTS.includes(m[1])) {
      return reply.code(404).send({ error: 'not_found' });
    }
    const variant = m[1];
    const { exp, sig } = req.query || {};

    if (!verifyMediaSignature(publicId, variant, exp, sig)) {
      return reply.code(403).send({ error: 'invalid_or_expired_signature' });
    }

    const { rows } = await query(
      `SELECT a.storage_path, a.sha256
       FROM assets a JOIN photos p ON p.id = a.photo_id
       WHERE p.public_id = $1 AND a.variant = $2`,
      [publicId, variant],
    );
    const asset = rows[0];
    if (!asset) return reply.code(404).send({ error: 'not_found' });

    const absPath = path.join(config.dataDir, asset.storage_path);
    let size;
    try {
      size = (await stat(absPath)).size;
    } catch {
      return reply.code(404).send({ error: 'not_found' });
    }

    reply
      .header('Content-Type', 'image/jpeg')
      .header('Content-Length', size)
      .header('ETag', `"${asset.sha256}"`)
      .header('Cache-Control', 'public, max-age=31536000, immutable');
    return reply.send(createReadStream(absPath));
  });
}
