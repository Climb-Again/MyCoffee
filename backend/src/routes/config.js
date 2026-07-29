// GET /api/config — self-diagnostic for the iOS Connect screen. Requires
// either token so a working ingest-only or app-only Keychain entry both get a
// real answer instead of an opaque 401 (PLAN.md §4).
import { requireAnyToken, presentedTokenKind } from '../auth.js';
import { config } from '../config.js';

// Bump only when a client-visible read contract changes shape.
const SNAPSHOT_VERSION = null; // GET /api/snapshot doesn't exist yet (Phase 2).

// TEMPORARY diagnostic for #33. /api/status reports vertex:false and a previous
// measurement showed config.vertex.privateKey with length 0, yet Radu reports
// GOOGLE_PRIVATE_KEY is set in Railway exactly as in the sibling app where it works.
// Length 0 (not ~27) rules out newline truncation and means process.env lookup
// missed entirely — i.e. the KEY differs, not the value. A trailing space, a
// non-breaking space, or a zero-width character from a paste all render identically
// in a web UI.
//
// So this reports the KEY SPACE, not values: every process.env name matching
// /GOOGLE|VERTEX/, JSON-escaped so invisible characters become visible, with the
// value's length only.
//
// SAFETY: env var NAMES and value LENGTHS are not secrets. No value is emitted.
// This repo is public and Actions logs are world-readable — keep it that way.
// Delete when #33 closes.
function envKeyDiag() {
  const keys = Object.keys(process.env).filter((k) => /GOOGLE|VERTEX/i.test(k));
  return {
    // JSON.stringify exposes "GOOGLE_PRIVATE_KEY " or "GOOGLE_PRIVATE_KEY\u200b"
    namesAsSeenByProcess: keys.sort().map((k) => ({
      name: JSON.stringify(k),
      nameLength: k.length,
      valueLength: (process.env[k] || '').length,
    })),
    exactLookup: {
      'GOOGLE_PRIVATE_KEY': process.env.GOOGLE_PRIVATE_KEY === undefined
        ? 'undefined'
        : `present(${process.env.GOOGLE_PRIVATE_KEY.length})`,
      resolvedByConfig: config.vertex.privateKey.length,
    },
  };
}

export default async function configRoutes(app) {
  app.get('/api/config', { preHandler: requireAnyToken }, async (req) => {
    return {
      ok: true,
      tokenKind: presentedTokenKind(req),
      capabilities: ['status', 'brief'],
      snapshotVersion: SNAPSHOT_VERSION,
      features: {},
      envKeyDiag: envKeyDiag(), // TEMPORARY — see #33
    };
  });
}
