// Operator controls for the extraction pipeline (PLAN.md §2/§4).
//
//   GET  /api/admin/jobs             progress + spendUsd (PLAN.md §9's curl)
//   POST /api/admin/jobs             start a worker run in the background
//   POST /api/admin/jobs/:id/pause   stop a runaway run without a redeploy
//   POST /api/admin/jobs/:id/resume
//   POST /api/admin/adjudicate       re-run adjudication over stored
//                                    field_candidates -- $0, no voter runs
//   GET  /api/admin/vertex-check     one minimal text-only Vertex call, to tell
//                                    "the model provider is unreachable" apart
//                                    from "the worker is broken" without needing
//                                    platform log access
//   POST /api/admin/rederive-photos  re-run the display/thumb derivative
//                                    pipeline against already-stored photos
//                                    (PLAN.md §11 #43) -- e.g. after shrinking
//                                    DISPLAY_DERIVATIVES's `display` spec, so
//                                    photos uploaded before the change also
//                                    shrink, not just new ones
//   POST /api/admin/rebuild-search-blobs  one-time backfill (#56) --
//                                    recomputes search_labels_blob/
//                                    search_prose_blob for every coffee
//   POST /api/admin/backfill-ocr-text     targeted re-OCR (#67) -- appends
//                                    the "OCR text" block to image-only
//                                    coffees OCR'd before that feature landed
//                                    (includeCaptioned:true covers all, #79/#80)
//   POST /api/admin/backfill-flavor-notes extracts flavor_notes from each
//                                    coffee's assembled text (#79/#80)
//
// All ingest-token-gated: these are write/spend-triggering operations, same
// tier as every other mutation in the API.
import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { requireIngestToken } from '../auth.js';
import { config } from '../config.js';
import { query } from '../db.js';
import { runWorker, defaultVoters, readjudicateAll, rebuildAllSearchBlobs, backfillOcrText, backfillFlavorNotes } from '../lib/worker.js';
import { DISPLAY_DERIVATIVES, deriveAll } from '../lib/imageDerivatives.js';
import { generateContent } from '../vertex.js';
import { EXTRACT_RESPONSE_SCHEMA } from '../lib/agents.js';

function toJobJson(r) {
  return {
    id: r.id,
    status: r.status,
    voterSet: r.voter_set,
    spendCapUsd: r.spend_cap_usd != null ? Number(r.spend_cap_usd) : null,
    spentUsd: Number(r.spent_usd),
    photosDone: r.photos_done,
    startedAt: r.started_at,
    pausedAt: r.paused_at,
    finishedAt: r.finished_at,
    lastError: r.last_error,
  };
}

async function markJobFailed(jobId, err) {
  await query(`UPDATE extraction_jobs SET status = 'done', finished_at = now(), last_error = $2 WHERE id = $1`, [
    jobId,
    err.message,
  ]).catch(() => {});
}

export default async function adminRoutes(app) {
  // Smallest possible real Vertex round-trip: no image, tiny token budget, an
  // explicit short timeout. Exists because a stalled extraction run is
  // indistinguishable from a broken one through the rest of this API, and the
  // platform log stream is not reachable from a lane session. Reports the
  // failure shape (message/code/status) rather than a bare 500 so the caller
  // learns *why* -- unreachable host, bad credentials, wrong model name.
  app.get('/api/admin/vertex-check', { preHandler: requireIngestToken }, async (req, reply) => {
    const timeoutMs = req.query?.timeoutMs != null ? Math.max(1000, Math.min(120000, Number(req.query.timeoutMs))) : 20000;
    // Diagnostic toggles (default off): `?thinking=0` forces thinkingBudget:0,
    // `?schema=1` attaches the real EXTRACT_RESPONSE_SCHEMA. Lets us isolate
    // which request feature a model 400s on, without a live extraction job.
    const thinking = req.query?.thinking;
    const withSchema = req.query?.schema === '1' || req.query?.schema === 'true';
    const startedAt = Date.now();
    try {
      const res = await generateContent({
        prompt: 'Reply with the single word: pong',
        maxOutputTokens: 8192,
        timeoutMs,
        ...(thinking !== undefined && thinking !== '' ? { thinkingBudget: Number(thinking) } : {}),
        ...(withSchema ? { json: true, responseSchema: EXTRACT_RESPONSE_SCHEMA } : {}),
      });
      return { ok: true, ms: Date.now() - startedAt, model: config.vertex.model, thinking: thinking ?? 'default', schema: withSchema, text: res?.text ?? null, usage: res?.usage ?? null };
    } catch (err) {
      return reply.code(200).send({
        ok: false,
        ms: Date.now() - startedAt,
        model: config.vertex.model,
        region: config.vertex.region,
        error: err?.message ?? String(err),
        code: err?.code ?? null,
        httpStatus: err?.response?.status ?? err?.status ?? null,
        // Vertex puts the useful detail in the response body, not the message.
        detail: typeof err?.response?.data === 'object' ? JSON.stringify(err.response.data).slice(0, 800) : null,
      });
    }
  });

  app.get('/api/admin/jobs', { preHandler: requireIngestToken }, async (req) => {
    const id = req.query?.id != null ? Number.parseInt(req.query.id, 10) : null;
    const { rows } = await query(
      id ? `SELECT * FROM extraction_jobs WHERE id = $1` : `SELECT * FROM extraction_jobs ORDER BY id DESC LIMIT 20`,
      id ? [id] : [],
    );
    return { jobs: rows.map(toJobJson) };
  });

  app.post('/api/admin/jobs', { preHandler: requireIngestToken }, async (req, reply) => {
    const spendCapUsd = req.body?.spendCapUsd != null ? Number(req.body.spendCapUsd) : null;
    const limit = req.body?.limit != null ? Math.max(1, Math.min(1000, Number(req.body.limit))) : 20;
    const voterSet = req.body?.voterSet === 'rules_only' ? 'rules_only' : 'full';
    // Text-only pass: skip the image part entirely and extract from the caption.
    // Defaults to including images, so this only happens when asked for.
    const includeImages = req.body?.includeImages === false ? false : true;

    const { rows } = await query(
      `INSERT INTO extraction_jobs (status, voter_set, spend_cap_usd) VALUES ('running', $1, $2) RETURNING *`,
      [voterSet, spendCapUsd],
    );
    const job = rows[0];

    const voters = voterSet === 'rules_only' ? (await defaultVoters()).filter((v) => v.agent === 'rules') : undefined;

    // Fire-and-forget: a full run is up to ~5 hours (PLAN.md §2). The route
    // returns immediately; poll GET /api/admin/jobs for progress.
    runWorker({ voters, limit, spendCapUsd, jobId: job.id, includeImages, log: req.log }).catch((err) => markJobFailed(job.id, err));

    return reply.code(202).send(toJobJson(job));
  });

  app.post('/api/admin/jobs/:id/pause', { preHandler: requireIngestToken }, async (req, reply) => {
    const id = Number.parseInt(req.params.id, 10);
    const { rows } = await query(
      `UPDATE extraction_jobs SET status = 'paused', paused_at = now() WHERE id = $1 AND status = 'running' RETURNING *`,
      [id],
    );
    if (rows.length === 0) return reply.code(404).send({ error: 'job_not_found_or_not_running' });
    return toJobJson(rows[0]);
  });

  app.post('/api/admin/jobs/:id/resume', { preHandler: requireIngestToken }, async (req, reply) => {
    const id = Number.parseInt(req.params.id, 10);
    const { rows } = await query(
      `UPDATE extraction_jobs SET status = 'running', paused_at = NULL WHERE id = $1 AND status = 'paused' RETURNING *`,
      [id],
    );
    const job = rows[0];
    if (!job) return reply.code(404).send({ error: 'job_not_found_or_not_paused' });

    const spendCapUsd = job.spend_cap_usd != null ? Number(job.spend_cap_usd) : null;
    runWorker({ jobId: job.id, spendCapUsd, log: req.log }).catch((err) => markJobFailed(job.id, err));

    return toJobJson(job);
  });

  app.post('/api/admin/adjudicate', { preHandler: requireIngestToken }, async (req, reply) => {
    const photoIdParam = req.body?.photoId;
    let photoId = null;
    if (photoIdParam != null) {
      const { rows } = await query(`SELECT id FROM photos WHERE public_id = $1`, [String(photoIdParam)]);
      if (!rows[0]) return reply.code(404).send({ error: 'photo_not_found' });
      photoId = rows[0].id;
    }
    const result = await readjudicateAll({ photoId });
    return result;
  });

  // One-time backfill for #56: every coffee that predates the search-blob
  // feature still has `search_labels_blob`/`search_prose_blob` at their `''`
  // default (009_search.sql) since nothing ever wrote them. $0, no LLM spend
  // -- re-derives from whatever the row already holds.
  app.post('/api/admin/rebuild-search-blobs', { preHandler: requireIngestToken }, async () => {
    return rebuildAllSearchBlobs();
  });

  // #67: image-only coffees OCR'd before the OCR-text-append feature landed
  // (jobs 22/23, per BACKLOG.md) still have no "OCR text" block. Bounded by
  // `limit`/`spendCapUsd` (both optional) so it can be re-run across several
  // days against the flash-lite daily quota rather than needing one huge run.
  app.post('/api/admin/backfill-ocr-text', { preHandler: requireIngestToken }, async (req) => {
    const limit = req.body?.limit != null ? Math.max(1, Math.min(1000, Number(req.body.limit))) : 200;
    const spendCapUsd = req.body?.spendCapUsd != null ? Number(req.body.spendCapUsd) : null;
    // `includeCaptioned: true` OCRs captioned coffees too, not just image-only
    // ones (Radu 2026-08-25, "append OCR text to all coffees").
    const includeCaptioned = req.body?.includeCaptioned === true;
    return backfillOcrText({ limit, spendCapUsd, includeCaptioned });
  });

  // #79/#80: extract flavour notes for coffees that predate the feature. Reads
  // each coffee's assembled text (caption + any appended "OCR text" block) —
  // no image, no voters — one focused call each. Bounded by limit/spendCapUsd
  // for the free-tier quota; `force: true` re-scans rows that already have a
  // value (use sparingly — it can overwrite a prior extraction/edit).
  app.post('/api/admin/backfill-flavor-notes', { preHandler: requireIngestToken }, async (req) => {
    const limit = req.body?.limit != null ? Math.max(1, Math.min(1000, Number(req.body.limit))) : 200;
    const spendCapUsd = req.body?.spendCapUsd != null ? Number(req.body.spendCapUsd) : null;
    const force = req.body?.force === true;
    return backfillFlavorNotes({ limit, spendCapUsd, force });
  });

  // Re-derives `display`/`thumb` (never `ocr` -- it's the source, and it's
  // extraction-only, never cached on-device) from each photo's already-
  // stored `ocr` asset. The raw upload itself isn't retained past the
  // original PUT (routes/photos.js), so `ocr` -- the highest-fidelity
  // derivative kept -- is the only available source for a later re-derive.
  app.post('/api/admin/rederive-photos', { preHandler: requireIngestToken }, async (req, reply) => {
    const requested = Array.isArray(req.body?.variants) ? req.body.variants : ['display', 'thumb'];
    const specs = DISPLAY_DERIVATIVES.filter((s) => s.variant !== 'ocr' && requested.includes(s.variant));
    if (specs.length === 0) return reply.code(400).send({ error: 'no_variants_to_rederive' });

    const { rows: sources } = await query(
      `SELECT a.photo_id, a.storage_path FROM assets a WHERE a.variant = 'ocr'`,
    );

    let updated = 0;
    const errors = [];
    for (const src of sources) {
      try {
        const buf = await readFile(path.join(config.dataDir, src.storage_path));
        const derived = await deriveAll(buf, specs);
        for (const d of Object.values(derived)) {
          await query(
            `UPDATE assets SET sha256 = $1, width = $2, height = $3, bytes = $4, storage_path = $5
             WHERE photo_id = $6 AND variant = $7`,
            [d.sha256, d.width, d.height, d.bytes, d.storagePath, src.photo_id, d.variant],
          );
        }
        updated += 1;
      } catch (err) {
        errors.push({ photoId: src.photo_id, error: err.message });
      }
    }

    // Old sha-addressed display/thumb files become unreferenced on disk once
    // their `assets` row repoints to the new (smaller) sha -- not garbage
    // collected here. That's a Railway-volume housekeeping concern, not the
    // on-device budget this row is about (CLAUDE.md's 50 MB cap governs the
    // iOS ImageStore cache, not backend storage); flagging rather than
    // guessing at a GC pass's shape.
    return { updated, errors, total: sources.length };
  });
}
