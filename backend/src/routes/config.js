// GET /api/config — self-diagnostic for the iOS Connect screen. Requires
// either token so a working ingest-only or app-only Keychain entry both get a
// real answer instead of an opaque 401 (PLAN.md §4).
import { requireAnyToken, presentedTokenKind } from '../auth.js';

// Bump only when a client-visible read contract changes shape.
const SNAPSHOT_VERSION = null; // GET /api/snapshot doesn't exist yet (Phase 2).

export default async function configRoutes(app) {
  app.get('/api/config', { preHandler: requireAnyToken }, async (req) => {
    return {
      ok: true,
      tokenKind: presentedTokenKind(req),
      capabilities: ['status', 'brief'],
      snapshotVersion: SNAPSHOT_VERSION,
      features: {},
    };
  });
}
