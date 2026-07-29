// GET /api/config — self-diagnostic for the iOS Connect screen. Requires
// either token so a working ingest-only or app-only Keychain entry both get a
// real answer instead of an opaque 401 (PLAN.md §4).
import { requireAnyToken, presentedTokenKind } from '../auth.js';
import { config } from '../config.js';

// Bump only when a client-visible read contract changes shape.
const SNAPSHOT_VERSION = null; // GET /api/snapshot doesn't exist yet (Phase 2).

// Temporary diagnostic for issue #33: /api/status reports vertex:false even though
// all three GOOGLE_* variables hold real values in Railway. isConfigured() is a
// plain AND over them, so one must arrive falsy — and that is not observable from
// outside. This narrows it to a specific variable in one request.
//
// SAFETY: this repo is PUBLIC and Actions logs are world-readable. Report only
// booleans, lengths and coarse shapes — NEVER a value, not even truncated. A
// length is enough to catch the likely culprits (empty string, or a stray
// newline/quote from pasting) without disclosing anything.
//
// Delete this block once #33 is resolved.
function vertexDiag() {
  const { projectId, serviceAccountEmail, privateKey, region, model } = config.vertex;
  const shape = (s) =>
    !s ? 'empty' : s.startsWith('{') ? 'json' : s.includes('BEGIN') ? 'pem' : 'other';
  const clean = (s) => s === s.trim() && !/^["']|["']$/.test(s);
  return {
    isConfigured: Boolean(projectId && serviceAccountEmail && privateKey),
    projectId: { present: Boolean(projectId), length: projectId.length, untrimmedOrQuoted: !clean(projectId) },
    serviceAccountEmail: {
      present: Boolean(serviceAccountEmail),
      length: serviceAccountEmail.length,
      looksLikeEmail: /^[^@\s]+@[^@\s]+$/.test(serviceAccountEmail.trim()),
      untrimmedOrQuoted: !clean(serviceAccountEmail),
    },
    privateKey: { present: Boolean(privateKey), length: privateKey.length, shape: shape(privateKey) },
    region,
    model,
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
      vertexDiag: vertexDiag(), // TEMPORARY — see #33, remove when resolved
    };
  });
}
