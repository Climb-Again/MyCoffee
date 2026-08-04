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
//
// All ingest-token-gated: these are write/spend-triggering operations, same
// tier as every other mutation in the API.
import { requireIngestToken } from '../auth.js';
import { config } from '../config.js';
import { query } from '../db.js';
import { runWorker, defaultVoters, readjudicateAll } from '../lib/worker.js';
import { generateContent } from '../vertex.js';

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
    const startedAt = Date.now();
    try {
      const res = await generateContent({
        prompt: 'Reply with the single word: pong',
        maxOutputTokens: 8192,
        timeoutMs,
      });
      return { ok: true, ms: Date.now() - startedAt, model: config.vertex.model, text: res?.text ?? null, usage: res?.usage ?? null };
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
}
