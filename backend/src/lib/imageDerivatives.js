// The sharp resize/encode pipeline for photo derivatives (PLAN.md §3),
// factored out of routes/photos.js so the admin re-derive pass (PLAN.md §11
// #43) can reuse the exact same pipeline against an already-stored derivative
// instead of duplicating it.
//
// `display`'s spec was shrunk 1290px/q82 -> 1080px/q72 (Radu: "optimize
// photos instead of not caching" -- CLAUDE.md's 50 MB budget). The on-device
// 30 MB cache + launch eviction (ImageStore) stays the backstop; this is the
// lever that lets more photos fit before eviction kicks in.
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, rename, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

import { derivativeAbsPath, derivativeRelPath } from '../media.js';

export const DISPLAY_DERIVATIVES = [
  { variant: 'ocr', maxDim: 2048, quality: 85 },
  { variant: 'display', maxDim: 1080, quality: 72 },
  { variant: 'thumb', maxDim: 320, quality: 75, cover: true },
];

export function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

// One derivative from a source image buffer. `.rotate()` bakes in EXIF
// orientation before sharp strips metadata by default (no GPS on a coffee-bag
// photo). Content-addressed: only written to disk if that exact sha isn't
// already there -- two sources (or an unchanged re-derive) producing
// byte-identical output share the file rather than duplicating it.
export async function deriveOne(sourceBuf, spec) {
  let pipeline = sharp(sourceBuf).rotate();
  pipeline = spec.cover
    ? pipeline.resize(spec.maxDim, spec.maxDim, { fit: 'cover' })
    : pipeline.resize(spec.maxDim, spec.maxDim, { fit: 'inside', withoutEnlargement: true });
  const buf = await pipeline.jpeg({ quality: spec.quality }).toBuffer();
  const meta = await sharp(buf).metadata();
  const sha256 = sha256Hex(buf);
  const absPath = derivativeAbsPath(sha256, spec.variant);

  let exists = true;
  try {
    await access(absPath);
  } catch {
    exists = false;
  }
  if (!exists) {
    await mkdir(path.dirname(absPath), { recursive: true });
    const tmpPath = `${absPath}.tmp-${randomBytes(6).toString('hex')}`;
    await writeFile(tmpPath, buf);
    await rename(tmpPath, absPath);
  }

  return {
    variant: spec.variant,
    sha256,
    width: meta.width,
    height: meta.height,
    bytes: buf.length,
    storagePath: derivativeRelPath(sha256, spec.variant),
  };
}

export async function deriveAll(sourceBuf, specs) {
  const out = {};
  for (const spec of specs) {
    out[spec.variant] = await deriveOne(sourceBuf, spec);
  }
  return out;
}
