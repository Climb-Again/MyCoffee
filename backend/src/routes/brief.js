// GET /api/brief — the app pulls its daily brief (a read). Requires either
// token: the app only ever holds INGEST_TOKEN in its Keychain today, so
// gating a read on APP_TOKEN alone made this endpoint unreachable from the
// app (PLAN.md "pre-existing defects to fix first", #1).
//
// Skeleton: returns the most recent stored brief, or a placeholder. Wire this to
// Vertex generation once the product brief defines what a "brief" is for MyCoffee.
import { requireAnyToken } from '../auth.js';
import { query } from '../db.js';

export default async function briefRoutes(app) {
  app.get('/api/brief', { preHandler: requireAnyToken }, async () => {
    let latest = null;
    try {
      const { rows } = await query(
        `SELECT id, title, body, generated_at
           FROM briefs
          ORDER BY generated_at DESC
          LIMIT 1`,
      );
      latest = rows[0] || null;
    } catch {
      latest = null; // table may not exist yet
    }

    if (!latest) {
      return {
        ok: true,
        brief: null,
        message: 'No brief generated yet.',
      };
    }

    return {
      ok: true,
      brief: {
        id: latest.id,
        title: latest.title,
        body: latest.body,
        generatedAt: latest.generated_at,
      },
    };
  });
}
