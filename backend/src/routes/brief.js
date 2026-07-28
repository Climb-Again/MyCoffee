// GET /api/brief — the app pulls its daily brief (reads). Requires APP_TOKEN.
//
// Skeleton: returns the most recent stored brief, or a placeholder. Wire this to
// Vertex generation once the product brief defines what a "brief" is for MyCoffee.
import { requireAppToken } from '../auth.js';
import { query } from '../db.js';

export default async function briefRoutes(app) {
  app.get('/api/brief', { preHandler: requireAppToken }, async () => {
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
