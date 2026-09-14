// #187 — the extension's browsing history: 10-day retention, top-10 ranking,
// and revisit handling. Pure functions, so they test here even though they run
// in the browser.
//
// Retention is the part worth pinning down: "discard any saves 10 days after
// visit" has to hold even if the browser was shut for a month, which is why
// pruning happens on read and write rather than on a timer.
import test from 'node:test';
import assert from 'node:assert/strict';

// Imported as a real module, not by slicing and `new Function`-ing the source.
// The old harness existed to keep `chrome` out of scope, but history.js only
// touches `chrome` INSIDE its async storage helpers — nothing at module top
// level — so a plain import works in Node and survives #199's static import of
// ./scoring-blend.js, which the text-slicing harness could not.
import {
  prune,
  rank,
  upsert,
  historyKey,
  RETENTION_DAYS,
  TOP_N,
  adjust,
  resetAdjustment,
  nextAdjustment,
  clampAdjustment,
  displayScore,
  liveRoastDays,
  addedAtOf,
  ADJUST_MAX,
} from '../../extension/history.js';
import * as viewHelpers from '../../extension/history.js';
import { readFileSync } from 'node:fs';

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
  // 40 days, not 20: #197 widened retention to 30 days, so the old fixture was
  // inside the window and this test was asserting the opposite of its name.
  const { top } = rank(
    [
      entry({ id: 'old', score: 99, addedAt: NOW - 40 * DAY, savedAt: NOW - 40 * DAY }),
      entry({ id: 'new', score: 10 }),
    ],
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

// ---- #188: roast-age colour and the visit timestamp ----
// Also a plain import now (the slice-and-`new Function` harness this file used
// to build went away with #199's static import).
const view = viewHelpers;

test('roast colour is green through two weeks', () => {
  // Radu: "green less than 2w going red as its older".
  const green = view.roastColor(0);
  assert.equal(view.roastColor(7), green);
  assert.equal(view.roastColor(view.ROAST_GREEN_DAYS), green, 'the whole first fortnight reads the same');
  assert.match(green, /^hsl\(130 /);
});

test('roast colour ramps continuously rather than jumping between buckets', () => {
  const hue = (c) => Number(/^hsl\((\d+)/.exec(c)[1]);
  let prev = hue(view.roastColor(view.ROAST_GREEN_DAYS));
  for (let d = view.ROAST_GREEN_DAYS; d <= view.ROAST_RED_DAYS; d += 2) {
    const h = hue(view.roastColor(d));
    assert.ok(h <= prev, `hue must fall toward red, rose at ${d}d`);
    prev = h;
  }
  assert.equal(hue(view.roastColor(view.ROAST_RED_DAYS)), 0, 'fully red at the far end');
});

test('roast colour is null when there is no date — not green', () => {
  // An unknown roast date must not be shown as fresh.
  assert.equal(view.roastColor(null), null);
  assert.equal(view.roastColor(undefined), null);
  assert.equal(view.roastLabel(null), null);
});

test('roast label reads naturally at each scale', () => {
  assert.equal(view.roastLabel(0), 'roasted today');
  assert.equal(view.roastLabel(1), 'roasted 1d ago');
  assert.equal(view.roastLabel(12), 'roasted 12d ago');
  assert.match(view.roastLabel(120), /~4mo ago/);
});

test('relativeTime renders the visit timestamp that was always stored', () => {
  const now = Date.UTC(2026, 8, 10, 12, 0, 0);
  assert.equal(view.relativeTime(now - 30_000, now), 'just now');
  assert.equal(view.relativeTime(now - 5 * 60_000, now), '5m ago');
  assert.equal(view.relativeTime(now - 3 * 3_600_000, now), '3h ago');
  assert.equal(view.relativeTime(now - 26 * 3_600_000, now), 'yesterday');
  assert.equal(view.relativeTime(now - 4 * 86_400_000, now), '4d ago');
  assert.equal(view.relativeTime(null, now), '');
});

// ---- the popup must only read component keys the server actually sends ----
//
// #188 renamed `components.roastRecency` to `components.roast` on the server
// and the popup was not updated, so the Freshness bar silently disappeared for
// a day. Nothing failed: a missing key is just `undefined`, and the DOM-id
// cross-check I was running only verified element ids, not response paths.
// This closes that gap.
test('popup.js reads no component key the API actually sends', async () => {
  // The popup consumes the ROUTE's response, not evaluateCoffee's return
  // value: /api/score reshapes components on the way out (it re-adds the
  // deprecated `roastRecency` alias for installed extensions, #190). Checking
  // against the scorer alone would fail a key the API legitimately sends --
  // which it did, the first time this test met that alias.
  const { evaluateCoffee } = await import('../src/lib/scoring.js');
  const produced = new Set(
    Object.keys(
      evaluateCoffee({
        groups: { roaster: { n: 9, mean: 4.2 } },
        globalMean: 4,
        priced: Array.from({ length: 20 }, (_, i) => ({ pricePer100gEur: 4 + i * 0.5, rating: 4 })),
        affinitySamples: [3.9, 4, 4.1],
        pricePer100gEur: 8,
        roastedOn: '2026-09-01',
      }).components,
    ),
  );

  // Plus whatever the route adds or renames in its own `components:` literal.
  const route = readFileSync(new URL('../src/routes/score.js', import.meta.url), 'utf8');
  const block = route.slice(route.indexOf('components: {'), route.indexOf('fields: {'));
  for (const m of block.matchAll(/^\s{8}([a-zA-Z]+):/gm)) produced.add(m[1]);

  const popup = readFileSync(new URL('../../extension/popup.js', import.meta.url), 'utf8');
  // Strip comments first: the fix for this very bug documents the old key by
  // name, and a comment must not fail the check.
  const code = popup.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  const read = new Set([...code.matchAll(/components\??\.([a-zA-Z]+)/g)].map((m) => m[1]));

  const unknown = [...read].filter((k) => !produced.has(k));
  assert.deepEqual(unknown, [], `popup reads ${unknown.join(', ')}; API sends ${[...produced].join(', ')}`);
});

// ---- #197: 30-day retention, measured from ADD time ----

test('#197: retention is 30 days, not 10', () => {
  assert.equal(RETENTION_DAYS, 30);
  const kept = prune([entry({ id: 'a', addedAt: NOW - 29 * DAY, savedAt: NOW })], NOW);
  assert.equal(kept.length, 1);
  const dropped = prune([entry({ id: 'a', addedAt: NOW - 31 * DAY, savedAt: NOW })], NOW);
  assert.equal(dropped.length, 0);
});

test("#197: a revisit does NOT reset the retention clock", () => {
  // Added 29 days ago, revisited today. Under the old savedAt rule this rode
  // the list forever; it must now expire tomorrow.
  const existing = [entry({ id: 'a', addedAt: NOW - 29 * DAY, savedAt: NOW - 29 * DAY })];
  const after = upsert(existing, { url: 'https://shop.test/a', score: 50 }, NOW);
  assert.equal(after[0].addedAt, NOW - 29 * DAY, 'addedAt was bumped by a revisit');
  assert.equal(after[0].savedAt, NOW, 'savedAt did not move on a revisit');
  assert.equal(prune(after, NOW + 2 * DAY).length, 0, 'entry outlived its 30 days');
});

test('#197: an entry written before this version falls back to savedAt', () => {
  const legacy = { url: 'https://shop.test/legacy', score: 50, savedAt: NOW - 5 * DAY };
  assert.equal(addedAtOf(legacy), NOW - 5 * DAY);
  assert.equal(prune([legacy], NOW).length, 1);
});

// ---- #196: manual +-10 adjustment ----

test('#196: adjustments compound and wrap to zero past the cap', () => {
  assert.equal(nextAdjustment(0, 10), 10);
  assert.equal(nextAdjustment(10, 10), 20);
  assert.equal(nextAdjustment(20, 10), 0, 'past the cap resets, which is the undo affordance');
  assert.equal(nextAdjustment(-20, -10), 0);
  assert.equal(clampAdjustment('nonsense'), 0);
  assert.equal(clampAdjustment(999), ADJUST_MAX);
});

test('#196: adjust targets one entry by url key, reset clears it', () => {
  const entries = [entry({ id: 'a' }), entry({ id: 'b' })];
  const bumped = adjust(entries, 'https://shop.test/a?utm=x', 10, NOW);
  assert.equal(bumped[0].adjustment, 10);
  assert.equal(bumped[1].adjustment ?? 0, 0);
  assert.equal(resetAdjustment(bumped, 'https://shop.test/a')[0].adjustment, 0);
});

test('#196: an adjustment survives a re-score of the same page', () => {
  const existing = adjust([entry({ id: 'a' })], 'https://shop.test/a', -10, NOW);
  const after = upsert(existing, { url: 'https://shop.test/a', score: 80 }, NOW);
  assert.equal(after[0].adjustment, -10, 'a revisit silently reset the manual adjustment');
});

test('#196: displayScore clamps at 0 and 100', () => {
  assert.equal(displayScore({ score: 95, adjustment: 20 }), 100);
  assert.equal(displayScore({ score: 5, adjustment: -20 }), 0);
});

// ---- #199: the roast term recomputes, the inputs stay frozen ----

test('#199: the same entry scores lower once it crosses 40 days', () => {
  const e = {
    url: 'https://shop.test/fresh',
    score: 70,
    affinity: 70,
    valueScore: 50,
    noveltyScore: 100,
    roastedOn: new Date(NOW - 30 * DAY).toISOString(),
    savedAt: NOW,
    addedAt: NOW,
  };
  const atVisit = displayScore(e, NOW);
  const twoWeeksLater = displayScore(e, NOW + 14 * DAY);
  assert.ok(twoWeeksLater < atVisit, `expected a drop past 40 days, got ${atVisit} -> ${twoWeeksLater}`);
  assert.equal(liveRoastDays(e, NOW + 14 * DAY), 44);
});

test('#199: a pre-#199 entry with no component scores keeps its frozen score', () => {
  const legacy = { url: 'https://shop.test/old', score: 64, roastDays: 12, savedAt: NOW, addedAt: NOW };
  assert.equal(displayScore(legacy, NOW + 100 * DAY), 64);
});

test('#199: ranking uses the recomputed score, not the stored one', () => {
  const stale = {
    url: 'https://shop.test/stale', score: 90, affinity: 90, valueScore: 90, noveltyScore: 100,
    roastedOn: new Date(NOW - 200 * DAY).toISOString(), savedAt: NOW, addedAt: NOW,
  };
  const fresh = {
    url: 'https://shop.test/fresh', score: 70, affinity: 70, valueScore: 70, noveltyScore: 100,
    roastedOn: new Date(NOW - 2 * DAY).toISOString(), savedAt: NOW, addedAt: NOW,
  };
  const { top } = rank([stale, fresh], { now: NOW });
  assert.equal(top[0].url, fresh.url, 'a 200-day-old bag still outranked a fresh one');
});
