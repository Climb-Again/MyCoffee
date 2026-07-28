// Bearer-token auth with constant-time comparison.
//
//   requireIngestToken -> INGEST_TOKEN  (all writes; the iOS app)
//   requireAppToken    -> APP_TOKEN     (reads)
//   requireAnyToken    -> either        (e.g. /api/status)
import { timingSafeEqual } from 'node:crypto';
import { config } from './config.js';

function extractBearer(req) {
  const header = req.headers['authorization'] || req.headers['Authorization'];
  if (!header || typeof header !== 'string') return null;
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  return m ? m[1] : null;
}

// Constant-time string compare that doesn't leak length via early return.
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) {
    // Still run a compare to keep timing uniform, then fail.
    timingSafeEqual(ab, ab);
    return false;
  }
  return timingSafeEqual(ab, bb);
}

function makeGuard(getTokens, label) {
  return async function guard(req, reply) {
    const tokens = getTokens().filter(Boolean);
    if (tokens.length === 0) {
      // Misconfiguration: no token set server-side. Deny rather than allow.
      req.log?.error(`[auth] ${label}: no server token configured`);
      return reply.code(503).send({ error: 'auth_not_configured' });
    }
    const presented = extractBearer(req);
    if (!presented) {
      return reply.code(401).send({ error: 'missing_bearer_token' });
    }
    const ok = tokens.some((t) => safeEqual(presented, t));
    if (!ok) {
      return reply.code(401).send({ error: 'invalid_token' });
    }
  };
}

export const requireIngestToken = makeGuard(() => [config.ingestToken], 'ingest');
export const requireAppToken = makeGuard(() => [config.appToken], 'app');
export const requireAnyToken = makeGuard(
  () => [config.ingestToken, config.appToken],
  'any',
);
