// Signed media URLs + content-addressed storage paths for photo derivatives.
//
// SwiftUI's AsyncImage can't attach an Authorization header, so images are
// served from an unauthenticated GET /media/:publicId/:variant.jpg guarded by
// an HMAC signature + expiry instead of a bearer token (PLAN.md §3).
import { createHmac, timingSafeEqual } from 'node:crypto';
import path from 'node:path';
import { config } from './config.js';

const VARIANTS = ['ocr', 'display', 'thumb'];

let _signingKey = null;
function signingKey() {
  if (_signingKey) return _signingKey;
  _signingKey = config.mediaSigningKey
    ? Buffer.from(config.mediaSigningKey)
    : createHmac('sha256', config.appToken || '').update('media').digest();
  return _signingKey;
}

function payload(publicId, variant, exp) {
  return `${publicId}|${variant}|${exp}`;
}

export function signMediaUrl(publicId, variant, exp) {
  return createHmac('sha256', signingKey()).update(payload(publicId, variant, exp)).digest('hex');
}

// `exp` is a unix timestamp in seconds. Returns false on any invalid input
// rather than throwing, so callers can treat this as a plain boolean gate.
export function verifyMediaSignature(publicId, variant, exp, sig) {
  if (!publicId || !VARIANTS.includes(variant) || !sig) return false;
  const expNum = Number(exp);
  if (!Number.isFinite(expNum) || expNum < Math.floor(Date.now() / 1000)) return false;

  const expected = signMediaUrl(publicId, variant, expNum);
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(String(sig), 'hex');
  if (a.length !== b.length) {
    timingSafeEqual(a, a);
    return false;
  }
  return timingSafeEqual(a, b);
}

export function buildMediaUrl(baseUrl, publicId, variant, ttlSeconds = 3600) {
  const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
  const sig = signMediaUrl(publicId, variant, exp);
  return `${baseUrl}/media/${publicId}/${variant}.jpg?exp=${exp}&sig=${sig}`;
}

// Content-addressed path, relative to DATA_DIR: media/<aa>/<bb>/<sha256>-<variant>.jpg
// Two-level fan-out keeps any one directory from holding all ~2,700 files.
export function derivativeRelPath(sha256, variant) {
  const a = sha256.slice(0, 2);
  const b = sha256.slice(2, 4);
  return path.posix.join('media', a, b, `${sha256}-${variant}.jpg`);
}

export function derivativeAbsPath(sha256, variant) {
  return path.join(config.dataDir, derivativeRelPath(sha256, variant));
}

export { VARIANTS };
