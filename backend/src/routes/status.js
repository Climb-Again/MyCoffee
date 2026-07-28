// GET /api/status — authorized liveness + basic counts. Either token works.
import { requireAnyToken } from '../auth.js';
import { healthcheck, query } from '../db.js';
import { isConfigured as vertexConfigured } from '../vertex.js';

export default async function statusRoutes(app) {
  app.get('/api/status', { preHandler: requireAnyToken }, async () => {
    const db = await healthcheck();

    let ingestCount = null;
    if (db) {
      try {
        const { rows } = await query('SELECT count(*)::int AS n FROM ingest_events');
        ingestCount = rows[0]?.n ?? 0;
      } catch {
        ingestCount = null; // table may not exist yet
      }
    }

    return {
      ok: true,
      service: 'mycoffee-api',
      db,
      vertex: vertexConfigured(),
      ingestEvents: ingestCount,
    };
  });
}
