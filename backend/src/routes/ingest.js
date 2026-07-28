// POST /api/ingest — the iOS app posts events here (writes). Requires INGEST_TOKEN.
//
// Skeleton shape: accept an arbitrary JSON envelope { type, payload, capturedAt }
// and store it. Grow into typed routes as the product brief lands.
import { requireIngestToken } from '../auth.js';
import { query } from '../db.js';

export default async function ingestRoutes(app) {
  app.post('/api/ingest', { preHandler: requireIngestToken }, async (req, reply) => {
    const body = req.body || {};
    const type = typeof body.type === 'string' ? body.type : null;
    if (!type) {
      return reply.code(400).send({ error: 'missing_type' });
    }

    const payload = body.payload ?? {};
    const capturedAt = body.capturedAt ? new Date(body.capturedAt) : new Date();
    if (Number.isNaN(capturedAt.getTime())) {
      return reply.code(400).send({ error: 'invalid_capturedAt' });
    }

    const { rows } = await query(
      `INSERT INTO ingest_events (type, payload, captured_at)
       VALUES ($1, $2, $3)
       RETURNING id, received_at`,
      [type, JSON.stringify(payload), capturedAt.toISOString()],
    );

    return reply.code(201).send({
      ok: true,
      id: rows[0].id,
      receivedAt: rows[0].received_at,
    });
  });
}
