// #194 — the backend shortlist helpers, and the guard that they never drift
// from the extension's copy. The client (extension/history.js, #187) and the
// server independently key and prune the same list; if their notion of "the
// same coffee" or "how long a row lives" diverged, a row written on one side
// would duplicate or vanish when it round-tripped through the other.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { historyKey, RETENTION_DAYS, MAX_ENTRIES } from '../src/lib/history.js';
// Imported as a real module (#199 added a static import to it, which the old
// slice-and-`new Function` harness could not survive). history.js touches
// `chrome` only inside its async storage helpers, never at module top level.
import * as client from '../../extension/history.js';

test('historyKey ignores query strings, hashes and trailing slashes', () => {
  const a = historyKey('https://shop.test/coffee?variant=42&utm_source=x');
  const b = historyKey('https://shop.test/coffee#reviews');
  const c = historyKey('https://shop.test/coffee/');
  assert.equal(a, 'https://shop.test/coffee');
  assert.equal(a, b);
  assert.equal(b, c);
});

test('historyKey falls back to the raw string for an unparseable url', () => {
  assert.equal(historyKey('not a url'), 'not a url');
  assert.equal(historyKey(null), '');
  assert.equal(historyKey(undefined), '');
});

// Parity with the extension. The client defines these constants for its own
// prune/rank; the server must agree, or "top 10 over 10 days" means two
// different things on the two sides.
test('retention + cap constants match the extension client', () => {
  assert.equal(RETENTION_DAYS, client.RETENTION_DAYS, 'RETENTION_DAYS drifted from the extension');
  // MAX_ENTRIES is module-private on the client, so read it from the source.
  const src = readFileSync(new URL('../../extension/history.js', import.meta.url), 'utf8');
  const m = /MAX_ENTRIES\s*=\s*(\d+)/.exec(src);
  assert.ok(m, 'MAX_ENTRIES not found in extension/history.js');
  assert.equal(MAX_ENTRIES, Number(m[1]), 'MAX_ENTRIES drifted from the extension');
});

// The extension's historyKey is the origin+pathname rule this mirrors; assert
// the two implementations agree on a representative set rather than trusting
// the prose.
test('historyKey matches the extension implementation', () => {
  const clientKey = client.historyKey;
  for (const u of [
    'https://shop.test/coffee?variant=42#x',
    'https://roaster.example/beans/ethiopia/',
    'garbage',
    '',
  ]) {
    assert.equal(historyKey(u), clientKey(u), `mismatch for ${JSON.stringify(u)}`);
  }
});
