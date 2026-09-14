// #152 (option A) — roaster logo bytes on the Railway /data volume.
//
// Radu's pick, over widening `assets` or accepting a pasted URL. The storage
// layer here is deliberately the same shape as `imageDerivatives.js`:
// content-addressed by sha256, written once, never mutated. What differs is
// everything photo-shaped — no `photos` row, no variants, no signed URL.
//
// ⚠ THE SERVING URL IS STABLE AND UNSIGNED, and that is a decision, not an
// oversight. `/media/:publicId/:variant.jpg` is HMAC-signed with an expiry
// because a coffee-bag photo is Radu's private data. A roaster logo is a brand
// mark that has been served from PUBLIC raw.githubusercontent.com since #133 —
// signing it would add no privacy and would break the app: `roasters.logo_url`
// is cached inside the snapshot vocab, so an expiring URL means logos that
// silently stop rendering between syncs.
import { createHash } from 'node:crypto';
import { mkdir, rename, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

import { config } from '../config.js';

// Matches `ops/roaster-assets/normalize-logos.py` exactly (MAX = 512,
// QUALITY = 85), so a logo uploaded from the app and one dropped into the
// ops/ folder come out byte-comparable rather than subtly different sizes.
export const LOGO_MAX_DIM = 512;
export const LOGO_QUALITY = 85;

// Bound a bad upload. A logo is ~11 KB average and 52 KB at the worst of the
// 64 already shipped; 2 MB is far above anything real and far below the
// global 1 MB JSON limit's intent being bypassed.
export const LOGO_MAX_UPLOAD_BYTES = 2 * 1024 * 1024;

export function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

// media/logos/<aa>/<bb>/<sha>.webp — same two-level fan-out as photo
// derivatives, so no directory ends up holding every file.
export function logoRelPath(sha256) {
  return path.posix.join('media', 'logos', sha256.slice(0, 2), sha256.slice(2, 4), `${sha256}.webp`);
}

export function logoAbsPath(sha256) {
  return path.join(config.dataDir, logoRelPath(sha256));
}

/**
 * Normalize an uploaded logo to <=512px WebP and store it content-addressed.
 * Returns { sha256, bytes, width, height, storagePath, deduped }.
 *
 * `withoutEnlargement` so a 128px logo is not upscaled into a blurry 512px one
 * — the cap is a ceiling, not a target.
 */
export async function storeRoasterLogo(buffer) {
  const image = sharp(buffer, { failOn: 'error' });
  const meta = await image.metadata();
  if (!meta.width || !meta.height) throw new Error('unreadable_image');

  const out = await image
    .resize({
      width: LOGO_MAX_DIM,
      height: LOGO_MAX_DIM,
      fit: 'inside',
      withoutEnlargement: true,
    })
    .webp({ quality: LOGO_QUALITY })
    .toBuffer({ resolveWithObject: true });

  const sha256 = sha256Hex(out.data);
  const storagePath = logoRelPath(sha256);
  const abs = path.join(config.dataDir, storagePath);

  // Content-addressed: identical bytes are already on disk, so a re-upload of
  // the same art writes nothing.
  try {
    await access(abs);
    return { sha256, bytes: out.data.length, width: out.info.width, height: out.info.height, storagePath, deduped: true };
  } catch {
    // not present yet
  }

  await mkdir(path.dirname(abs), { recursive: true });
  // Write-then-rename, so a crash mid-write cannot leave a truncated file at a
  // path whose name promises a specific sha.
  const tmp = `${abs}.${process.pid}.tmp`;
  await writeFile(tmp, out.data);
  await rename(tmp, abs);

  return { sha256, bytes: out.data.length, width: out.info.width, height: out.info.height, storagePath, deduped: false };
}
