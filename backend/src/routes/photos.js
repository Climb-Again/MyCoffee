// Photo ingestion: two-phase upload from the Mac exporter (PLAN.md §3).
//
//   POST /api/photos/manifest        <=200 entries, decides what's needed
//   PUT  /api/photos/:sourceId/image raw image/jpeg body, content-addressed
//
// Both require INGEST_TOKEN — this is the write path the exporter script uses.
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, rename, unlink, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

import { requireIngestToken } from '../auth.js';
import { query, withTransaction } from '../db.js';
import { config } from '../config.js';
import { derivativeAbsPath, derivativeRelPath } from '../media.js';

const MANIFEST_MAX_ENTRIES = 200;
const TEXT_WAIT_DAYS = 10;

const DERIVATIVES = [
  { variant: 'ocr', maxDim: 2048, quality: 85 },
  { variant: 'display', maxDim: 1290, quality: 82 },
  { variant: 'thumb', maxDim: 320, quality: 75, cover: true },
];

function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

function isHex64(s) {
  return typeof s === 'string' && /^[0-9a-f]{64}$/i.test(s);
}

function newPublicId() {
  return randomBytes(16).toString('base64url');
}

function textShaOf({ title, caption, description }) {
  const norm = (s) => (typeof s === 'string' ? s.trim() : '');
  return sha256Hex(JSON.stringify([norm(title), norm(caption), norm(description)]));
}

function capturedOnFrom(capturedAt, capturedOn) {
  if (typeof capturedOn === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(capturedOn)) return capturedOn;
  if (capturedAt instanceof Date && !Number.isNaN(capturedAt.getTime())) {
    return capturedAt.toISOString().slice(0, 10);
  }
  return null;
}

async function upsertPhoto(client, entry) {
  const sourceId = String(entry.sourceId);
  const contentSha256 = isHex64(entry.contentSha256) ? entry.contentSha256.toLowerCase() : null;
  const capturedAt = entry.capturedAt ? new Date(entry.capturedAt) : null;
  const capturedOn = capturedOnFrom(capturedAt, entry.capturedOn);
  const favorite = Boolean(entry.favorite);
  const title = typeof entry.title === 'string' ? entry.title : null;

  const { rows: existingRows } = await client.query(
    `SELECT * FROM photos WHERE source = 'photos_library' AND source_id = $1`,
    [sourceId],
  );
  const existing = existingRows[0];

  if (!existing) {
    // Check proactively rather than catching a unique-violation on INSERT --
    // a caught error mid-transaction aborts every later statement in the
    // same withTransaction() block (Postgres error 25P02), which would break
    // the photo_texts upsert that follows in the same transaction.
    let duplicateContentSha256 = false;
    let insertSha = contentSha256;
    if (contentSha256) {
      const { rows: clashRows } = await client.query(
        `SELECT 1 FROM photos WHERE content_sha256 = $1`,
        [contentSha256],
      );
      if (clashRows.length > 0) {
        // Same bag re-imported under a new Photos-library UUID. Still create
        // the row (a human resolves the duplicate later) but leave
        // content_sha256 unset so the unique index isn't violated.
        duplicateContentSha256 = true;
        insertSha = null;
      }
    }

    const { rows } = await client.query(
      `INSERT INTO photos (public_id, source, source_id, content_sha256, captured_at, captured_on, title, favorite)
       VALUES ($1, 'photos_library', $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [newPublicId(), sourceId, insertSha, capturedAt, capturedOn, title, favorite],
    );
    return { row: rows[0], duplicateContentSha256 };
  }

  const contentChanged = Boolean(
    contentSha256 && existing.content_sha256 && contentSha256 !== existing.content_sha256,
  );
  let duplicateContentSha256 = false;
  let newContentSha256 = existing.content_sha256;

  if (contentChanged || (!existing.content_sha256 && contentSha256)) {
    const { rows: clashRows } = await client.query(
      `SELECT 1 FROM photos WHERE content_sha256 = $1 AND id <> $2`,
      [contentSha256, existing.id],
    );
    if (clashRows.length > 0) {
      duplicateContentSha256 = true;
      newContentSha256 = null;
    } else {
      newContentSha256 = contentSha256;
    }
  }

  const { rows } = await client.query(
    `UPDATE photos SET
       content_sha256 = $1,
       captured_at    = COALESCE($2, captured_at),
       captured_on    = COALESCE($3, captured_on),
       title          = COALESCE($4, title),
       favorite       = $5,
       has_image      = CASE WHEN $6 THEN false ELSE has_image END,
       updated_at     = now()
     WHERE id = $7
     RETURNING *`,
    [newContentSha256, capturedAt, capturedOn, title, favorite, contentChanged, existing.id],
  );
  return { row: rows[0], duplicateContentSha256 };
}

async function upsertText(client, photo, entry) {
  const caption = typeof entry.caption === 'string' ? entry.caption : null;
  const description = typeof entry.description === 'string' ? entry.description : null;
  const title = typeof entry.title === 'string' ? entry.title : null;
  const hasText = Boolean((caption && caption.trim()) || (description && description.trim()));
  const sha = textShaOf({ title, caption, description });

  const { rows: latestRows } = await client.query(
    `SELECT version, text_sha256 FROM photo_texts WHERE photo_id = $1 ORDER BY version DESC LIMIT 1`,
    [photo.id],
  );
  const latest = latestRows[0];
  const textChanged = !latest || latest.text_sha256 !== sha;
  let version = latest?.version ?? 0;

  if (textChanged) {
    // Check proactively rather than catching a unique-violation on INSERT --
    // a caught error mid-transaction aborts every later statement in the
    // same withTransaction() block (Postgres error 25P02).
    const { rows: seenRows } = await client.query(
      `SELECT version FROM photo_texts WHERE photo_id = $1 AND text_sha256 = $2`,
      [photo.id, sha],
    );
    if (seenRows.length === 0) {
      const { rows } = await client.query(
        `INSERT INTO photo_texts (photo_id, version, title, caption, description, text_sha256)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING version`,
        [photo.id, version + 1, title, caption, description, sha],
      );
      version = rows[0].version;
    } else {
      // This exact text already exists at an earlier version (e.g. a caption
      // reverted) -- report that version rather than the latest one, and
      // don't insert a duplicate row.
      version = seenRows[0].version;
    }
  }

  const nextState = hasText ? 'text_received' : photo.state === 'processed' ? photo.state : 'awaiting_text';
  const textWaitUntil = hasText
    ? null
    : photo.text_wait_until ||
      new Date((photo.captured_at ? new Date(photo.captured_at) : new Date()).getTime() + TEXT_WAIT_DAYS * 86_400_000);

  const { rows: updated } = await client.query(
    `UPDATE photos SET state = $1, text_wait_until = $2, updated_at = now() WHERE id = $3 RETURNING *`,
    [nextState, textWaitUntil, photo.id],
  );

  return { photo: updated[0], textChanged, textVersion: version };
}

export default async function photosRoutes(app) {
  app.post('/api/photos/manifest', { preHandler: requireIngestToken }, async (req, reply) => {
    const entries = Array.isArray(req.body?.entries) ? req.body.entries : null;
    if (!entries) return reply.code(400).send({ error: 'missing_entries' });
    if (entries.length === 0 || entries.length > MANIFEST_MAX_ENTRIES) {
      return reply.code(400).send({ error: 'invalid_entries_length', max: MANIFEST_MAX_ENTRIES });
    }
    for (const e of entries) {
      if (!e || typeof e.sourceId !== 'string' || !e.sourceId) {
        return reply.code(400).send({ error: 'missing_sourceId' });
      }
    }

    const results = [];
    for (const entry of entries) {
      const result = await withTransaction(async (client) => {
        const { row: photoAfterUpsert, duplicateContentSha256 } = await upsertPhoto(client, entry);
        const { photo, textChanged, textVersion } = await upsertText(client, photoAfterUpsert, entry);
        return { photo, duplicateContentSha256, textChanged, textVersion };
      });

      results.push({
        sourceId: entry.sourceId,
        photoId: result.photo.public_id,
        need: result.photo.has_image ? 'none' : 'image',
        textChanged: result.textChanged,
        textVersion: result.textVersion,
        state: result.photo.state,
        ...(result.duplicateContentSha256 ? { duplicateContentSha256: true } : {}),
      });
    }

    return { ok: true, results };
  });

  app.put(
    '/api/photos/:sourceId/image',
    {
      preHandler: requireIngestToken,
      config: { rateLimit: { max: config.ingestRateLimitMax, timeWindow: 60_000 } },
    },
    async (req, reply) => {
      const { sourceId } = req.params;
      const declaredSha = typeof req.query?.sha256 === 'string' ? req.query.sha256.toLowerCase() : null;
      if (!isHex64(declaredSha)) return reply.code(400).send({ error: 'missing_or_invalid_sha256' });

      const body = req.body;
      if (!Buffer.isBuffer(body) || body.length === 0) {
        return reply.code(400).send({ error: 'missing_image_body' });
      }

      const actualSha = sha256Hex(body);
      if (actualSha !== declaredSha) {
        return reply.code(409).send({ error: 'sha256_mismatch' });
      }

      const { rows } = await query(
        `SELECT * FROM photos WHERE source = 'photos_library' AND source_id = $1`,
        [sourceId],
      );
      const photo = rows[0];
      if (!photo) return reply.code(404).send({ error: 'photo_not_found' });

      if (photo.content_sha256 && photo.content_sha256 !== actualSha) {
        return reply.code(409).send({ error: 'sha256_mismatch' });
      }

      // Dedup against the *original upload's* identity, not a derivative's --
      // sharp re-encodes on every pass, so a derivative's own hash never
      // equals the raw body's hash even when the source bytes are identical.
      if (photo.has_image && photo.content_sha256 === actualSha) {
        return reply.code(200).send({ deduped: true, photoId: photo.public_id });
      }

      const tmpPath = path.join(config.dataDir, 'tmp', `${randomBytes(12).toString('hex')}.jpg`);
      await mkdir(path.dirname(tmpPath), { recursive: true });
      await writeFile(tmpPath, body);

      try {
        const variants = {};
        for (const spec of DERIVATIVES) {
          // .rotate() bakes in EXIF orientation before we discard the EXIF
          // block entirely -- sharp strips metadata by default (no
          // withMetadata() call), which is exactly the "no GPS on a coffee
          // bag photo" requirement.
          let pipeline = sharp(tmpPath).rotate();
          pipeline = spec.cover
            ? pipeline.resize(spec.maxDim, spec.maxDim, { fit: 'cover' })
            : pipeline.resize(spec.maxDim, spec.maxDim, { fit: 'inside', withoutEnlargement: true });
          const buf = await pipeline.jpeg({ quality: spec.quality }).toBuffer();
          const meta = await sharp(buf).metadata();
          const sha = sha256Hex(buf);
          const absPath = derivativeAbsPath(sha, spec.variant);

          let exists = true;
          try {
            await access(absPath);
          } catch {
            exists = false;
          }
          if (!exists) {
            await mkdir(path.dirname(absPath), { recursive: true });
            const tmpDerivative = `${absPath}.tmp-${randomBytes(6).toString('hex')}`;
            await writeFile(tmpDerivative, buf);
            await rename(tmpDerivative, absPath);
          }

          await query(
            `INSERT INTO assets (photo_id, variant, sha256, width, height, bytes, storage_path)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (photo_id, variant) DO UPDATE SET
               sha256 = EXCLUDED.sha256, width = EXCLUDED.width, height = EXCLUDED.height,
               bytes = EXCLUDED.bytes, storage_path = EXCLUDED.storage_path`,
            [photo.id, spec.variant, sha, meta.width, meta.height, buf.length, derivativeRelPath(sha, spec.variant)],
          );

          variants[spec.variant] = { sha256: sha, width: meta.width, height: meta.height, bytes: buf.length };
        }

        await query(
          `UPDATE photos SET has_image = true, image_uploaded_at = now(), updated_at = now(), content_sha256 = COALESCE(content_sha256, $1) WHERE id = $2`,
          [actualSha, photo.id],
        );

        return reply.code(201).send({ created: true, photoId: photo.public_id, variants });
      } finally {
        await unlink(tmpPath).catch(() => {});
      }
    },
  );
}
