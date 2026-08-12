// Exercises the real sharp pipeline (no DB) against a synthetic in-memory
// source image -- config.dataDir is pointed at a fresh tmp dir for the
// duration of this file so derivative files land somewhere writable instead
// of the production default (/data, absent outside Railway).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import sharp from 'sharp';

import { config } from '../src/config.js';
import { DISPLAY_DERIVATIVES, deriveOne, deriveAll, sha256Hex } from '../src/lib/imageDerivatives.js';

config.dataDir = await mkdtemp(path.join(tmpdir(), 'mycoffee-imagederiv-'));

async function syntheticJpeg(width, height) {
  return sharp({ create: { width, height, channels: 3, background: { r: 120, g: 90, b: 60 } } })
    .jpeg()
    .toBuffer();
}

test('sha256Hex is deterministic and content-derived', () => {
  const a = Buffer.from('hello');
  const b = Buffer.from('hello');
  const c = Buffer.from('hello!');
  assert.equal(sha256Hex(a), sha256Hex(b));
  assert.notEqual(sha256Hex(a), sha256Hex(c));
});

test('DISPLAY_DERIVATIVES: display was shrunk below the old 1290px/q82 spec (PLAN.md §11 #43)', () => {
  const display = DISPLAY_DERIVATIVES.find((s) => s.variant === 'display');
  assert.ok(display.maxDim < 1290);
  assert.ok(display.quality < 82);
});

test('deriveOne resizes down to the spec\'s maxDim and writes a content-addressed file', async () => {
  const source = await syntheticJpeg(2400, 1800); // larger than every spec's maxDim
  const spec = DISPLAY_DERIVATIVES.find((s) => s.variant === 'display');
  const result = await deriveOne(source, spec);

  assert.equal(result.variant, 'display');
  assert.ok(result.width <= spec.maxDim);
  assert.ok(result.height <= spec.maxDim);
  assert.equal(result.sha256, sha256Hex(await sharp(source).rotate().resize(spec.maxDim, spec.maxDim, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: spec.quality }).toBuffer()));

  const absPath = path.join(config.dataDir, result.storagePath);
  const stats = await stat(absPath);
  assert.equal(stats.size, result.bytes);
});

test('deriveOne: a "cover" spec (thumb) crops to an exact square regardless of source aspect ratio', async () => {
  const source = await syntheticJpeg(3000, 1000); // wide, non-square
  const spec = DISPLAY_DERIVATIVES.find((s) => s.variant === 'thumb');
  const result = await deriveOne(source, spec);
  assert.equal(result.width, spec.maxDim);
  assert.equal(result.height, spec.maxDim);
});

test('deriveAll produces every requested variant, each smaller than the ocr source for a big enough image', async () => {
  const source = await syntheticJpeg(3000, 2000);
  const derived = await deriveAll(source, DISPLAY_DERIVATIVES);
  assert.deepEqual(Object.keys(derived).sort(), ['display', 'ocr', 'thumb']);
  assert.ok(derived.display.bytes < derived.ocr.bytes);
  assert.ok(derived.thumb.bytes < derived.display.bytes);
});

test('deriveOne is idempotent -- re-deriving byte-identical output reuses the same content-addressed file', async () => {
  const source = await syntheticJpeg(1500, 1200);
  const spec = DISPLAY_DERIVATIVES.find((s) => s.variant === 'display');
  const first = await deriveOne(source, spec);
  const second = await deriveOne(source, spec);
  assert.equal(first.sha256, second.sha256);
  assert.equal(first.storagePath, second.storagePath);
});
