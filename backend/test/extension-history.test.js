// #187 — the extension's browsing history: 10-day retention, top-10 ranking,
// and revisit handling. Pure functions, so they test here even though they run
// in the browser.
//
// Retention is the part worth pinning down: "discard any saves 10 days after
// visit" has to hold even if the browser was shut for a month, which is why
// pruning happens on read and write rather than on a timer.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// history.js touches `chrome` only inside the async storage helpers; the pure
// functions above them are what these tests exercise.
const src = readFileSync(new URL('../../extension/history.js', import.meta.url), 'utf8');
const pure = src.slice(0, src.indexOf('export async function loadHistory')).replace(/^export /gm, '');
const { prune, rank, upsert, historyKey, RETENTION_DAYS, TOP_N } = new Function(
  `${pure}; return { prune, rank, upsert, historyKey, RETENTION_DAYS, TOP_N };`,
)();

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 8, 10);
const entry = (over) => ({ url: `https://shop.test/${over.id ?? 'a'}`, savedAt: NOW, score: 50, ...over });

// ---- retention ----

test('prune keeps entries inside the retention window', () => {
  const kept = prune([entry({ id: 'a', savedAt: NOW - 9 * DAY })], NOW);
  assert.equal(kept.length, 1);
});

test('prune discards anything older than the window', () => {
  const gone = prune(
    [entry({ id: 'a', savedAt: NOW - (RETENTION_DAYS + 1) * DAY }), entry({ id: 'b', savedAt: NOW - 400 * DAY })],
    NOW,
  );
  assert.deepEqual(gone, []);
});

test('prune survives a browser that was closed for a month', () => {
  // The reason pruning is not on a timer: no alarm fires while Chrome is shut,
  // so the rule has to be enforced when the data is next touched.
  const entries = [entry({ id: 'old', savedAt: NOW - 30 * DAY }), entry({ id: 'fresh', savedAt: NOW - 1 * DAY })];
  const kept = prune(entries, NOW + 5 * DAY);
  assert.deepEqual(kept.map((e) => e.url), ['https://shop.test/fresh']);
});

test('prune drops malformed entries rather than throwing', () => {
  assert.deepEqual(prune([null, undefined, {}, { savedAt: 'yesterday' }], NOW), []);
  assert.deepEqual(prune(undefined, NOW), []);
});

// ---- ranking ----

test('rank orders by score, highest first, and caps at ten', () => {
  const entries = Array.from({ length: 25 }, (_, i) => entry({ id: `c${i}`, score: i }));
  const { top } = rank(entries, { now: NOW });
  assert.equal(top.length, TOP_N);
  assert.equal(top[0].score, 24);
  assert.equal(top[9].score, 15);
});

test('rank excludes unscored entries rather than treating them as zero', () => {
  // A suppressed headline is a deliberate outcome (#106); sorting it as 0
  // would rank "we could not judge this" below a genuinely bad coffee.
  const { top, unscoredCount, scoredCount } = rank(
    [entry({ id: 'a', score: 70 }), entry({ id: 'b', score: null }), entry({ id: 'c', score: null })],
    { now: NOW },
  );
  assert.equal(top.length, 1);
  assert.equal(scoredCount, 1);
  assert.equal(unscoredCount, 2);
});

test('rank never returns an entry older than the window', () => {
  const { top } = rank(
    [entry({ id: 'old', score: 99, savedAt: NOW - 20 * DAY }), entry({ id: 'new', score: 10 })],
    { now: NOW },
  );
  assert.deepEqual(top.map((e) => e.score), [10], 'a stale 99 must not outrank a live 10');
});

test('rank breaks a score tie with the more recent visit', () => {
  const { top } = rank(
    [entry({ id: 'older', score: 50, savedAt: NOW - 3 * DAY }), entry({ id: 'newer', score: 50, savedAt: NOW })],
    { now: NOW },
  );
  assert.equal(top[0].url, 'https://shop.test/newer');
});

// ---- revisits ----

test('historyKey ignores query strings and hashes', () => {
  // Shop URLs carry cart ids, tracking params and variant selections; compared
  // verbatim, one coffee would file under several entries.
  const a = historyKey('https://shop.test/coffee?variant=42&utm_source=x');
  const b = historyKey('https://shop.test/coffee#reviews');
  const c = historyKey('https://shop.test/coffee/');
  assert.equal(a, b);
  assert.equal(b, c);
});

test('revisiting a page replaces its entry instead of duplicating it', () => {
  // Otherwise the top 10 quietly becomes "pages I refreshed most".
  let entries = upsert([], entry({ id: 'a', score: 40 }), NOW);
  entries = upsert(entries, { url: 'https://shop.test/a?variant=2', score: 80 }, NOW + 1000);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].score, 80, 'the newer reading wins');
});

test('a revisit refreshes the retention clock', () => {
  let entries = upsert([], entry({ id: 'a' }), NOW - 9 * DAY);
  entries = upsert(entries, { url: 'https://shop.test/a', score: 50 }, NOW);
  assert.equal(prune(entries, NOW + 5 * DAY).length, 1, 'seen 5 days ago, so still live');
});

test('different pages stay separate entries', () => {
  let entries = upsert([], entry({ id: 'a' }), NOW);
  entries = upsert(entries, entry({ id: 'b' }), NOW);
  assert.equal(entries.length, 2);
});

test('upsert prunes as it writes', () => {
  const stale = entry({ id: 'stale', savedAt: NOW - 40 * DAY });
  const entries = upsert([stale], entry({ id: 'new' }), NOW);
  assert.deepEqual(entries.map((e) => e.url), ['https://shop.test/new']);
});
