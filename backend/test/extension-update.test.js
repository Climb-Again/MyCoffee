// The version comparison behind the extension's auto-update (extension/update.js).
//
// Lives in the backend suite because it is the only place with a test runner,
// and the function is pure. It is worth a test for one reason: a string
// compare gets "1.2.10" vs "1.2.9" backwards, which would strand the extension
// on an old version at exactly the point where updates matter most.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// update.js imports nothing, but it does reference `chrome` at module scope in
// other exports, so pull the pure function out by evaluating just it.
const src = readFileSync(new URL('../../extension/update.js', import.meta.url), 'utf8');
const body = src.slice(src.indexOf('export function isNewer')).replace('export function', 'function');
const isNewer = new Function(`${body.slice(0, body.indexOf('\n}') + 2)}; return isNewer;`)();

test('isNewer: ordinary bumps', () => {
  assert.equal(isNewer('1.1.0', '1.0.0'), true);
  assert.equal(isNewer('1.0.1', '1.0.0'), true);
  assert.equal(isNewer('2.0.0', '1.9.9'), true);
});

test('isNewer: equal or older is not newer', () => {
  assert.equal(isNewer('1.0.0', '1.0.0'), false);
  assert.equal(isNewer('1.0.0', '1.0.1'), false);
  assert.equal(isNewer('1.9.9', '2.0.0'), false);
});

test('isNewer: compares numerically, not as strings', () => {
  // The whole reason this is tested: "1.2.10" < "1.2.9" as strings.
  assert.equal(isNewer('1.2.10', '1.2.9'), true);
  assert.equal(isNewer('1.10.0', '1.9.0'), true);
  assert.equal(isNewer('1.2.9', '1.2.10'), false);
});

test('isNewer: uneven segment counts', () => {
  assert.equal(isNewer('1.1', '1.0.9'), true);
  assert.equal(isNewer('1.0', '1.0.0'), false);
  assert.equal(isNewer('1.0.0.1', '1.0.0'), true);
});

test('isNewer: garbage never claims to be newer', () => {
  assert.equal(isNewer(undefined, '1.0.0'), false);
  assert.equal(isNewer('', '1.0.0'), false);
  assert.equal(isNewer('not.a.version', '1.0.0'), false);
});
