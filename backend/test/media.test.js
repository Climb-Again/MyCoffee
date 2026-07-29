// Pure unit tests for signed media URLs — no DB, no server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { signMediaUrl, verifyMediaSignature, derivativeRelPath } from '../src/media.js';

test('a freshly signed URL verifies', () => {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const sig = signMediaUrl('pub123', 'thumb', exp);
  assert.equal(verifyMediaSignature('pub123', 'thumb', exp, sig), true);
});

test('an expired signature is rejected', () => {
  const exp = Math.floor(Date.now() / 1000) - 10;
  const sig = signMediaUrl('pub123', 'thumb', exp);
  assert.equal(verifyMediaSignature('pub123', 'thumb', exp, sig), false);
});

test('a tampered variant is rejected', () => {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const sig = signMediaUrl('pub123', 'thumb', exp);
  assert.equal(verifyMediaSignature('pub123', 'display', exp, sig), false);
});

test('a tampered publicId is rejected', () => {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const sig = signMediaUrl('pub123', 'thumb', exp);
  assert.equal(verifyMediaSignature('other-id', 'thumb', exp, sig), false);
});

test('an unknown variant is rejected', () => {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const sig = signMediaUrl('pub123', 'original', exp);
  assert.equal(verifyMediaSignature('pub123', 'original', exp, sig), false);
});

test('derivativeRelPath fans out by the first two byte-pairs of the hash', () => {
  const sha = 'ab'.padEnd(64, '0');
  assert.equal(derivativeRelPath(sha, 'thumb'), `media/ab/00/${sha}-thumb.jpg`);
});
