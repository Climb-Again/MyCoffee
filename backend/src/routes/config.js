// GET /api/config — self-diagnostic for the iOS Connect screen. Requires
// either token so a working ingest-only or app-only Keychain entry both get a
// real answer instead of an opaque 401 (PLAN.md §4).
import { requireAnyToken, presentedTokenKind } from '../auth.js';
import { SNAPSHOT_VERSION } from './coffees.js';

export default async function configRoutes(app) {
  app.get('/api/config', { preHandler: requireAnyToken }, async (req) => {
    return {
      ok: true,
      tokenKind: presentedTokenKind(req),
      capabilities: ['status', 'brief', 'snapshot', 'coffees'],
      snapshotVersion: SNAPSHOT_VERSION,
      features: {},
    };
  });
}
