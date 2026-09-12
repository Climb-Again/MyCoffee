// #200 — What's New feed's pure helpers. The entry-key hash is the load-
// bearing bit: whatsnew.json entries have no stable id, so if a re-worded
// title were to shift keys every check would flip on the next deploy.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../extension/whatsnew.js', import.meta.url), 'utf8');
// Strip the chrome.storage-touching bottom half so this runs under Node.
const pure = src.slice(0, src.indexOf('// ---- chrome.storage glue')).replace(/^export /gm, '');
const { entryKey, liveEntries, planByLane, unseenLiveCount, markAllSeen } = new Function(
  `${pure}; return { entryKey, liveEntries, planByLane, unseenLiveCount, markAllSeen };`,
)();

test('entryKey is stable across calls', () => {
  const e = { title: 'A', detail: 'B' };
  assert.equal(entryKey(e), entryKey(e));
});

test('entryKey depends on both title and detail', () => {
  const a = entryKey({ title: 'A', detail: 'B' });
  const b = entryKey({ title: 'A', detail: 'C' });
  const c = entryKey({ title: 'D', detail: 'B' });
  assert.notEqual(a, b);
  assert.notEqual(a, c);
});

test('entryKey ignores fields other than title and detail', () => {
  // A newly added `area` chip must not silently uncheck every existing row.
  const a = entryKey({ title: 'A', detail: 'B' });
  const b = entryKey({ title: 'A', detail: 'B', area: 'backend' });
  assert.equal(a, b);
});

test('liveEntries tolerates a missing feed', () => {
  assert.deepEqual(liveEntries(null), []);
  assert.deepEqual(liveEntries({}), []);
  assert.deepEqual(liveEntries({ live: [{ title: 'x' }] }), [{ title: 'x' }]);
});

test('planByLane returns groups in a stable order and skips empty ones', () => {
  const feed = {
    plan: {
      byLane: {
        'ios-ux': [{ title: 'u' }],
        backend: [{ title: 'b' }],
        publish: [],
        'novel-lane': [{ title: 'n' }],
      },
    },
  };
  const groups = planByLane(feed);
  assert.deepEqual(
    groups.map((g) => g.lane),
    ['backend', 'ios-ux', 'novel-lane'],
  );
  assert.equal(groups[0].entries.length, 1);
});

test('unseenLiveCount counts only live entries', () => {
  const feed = {
    live: [{ title: 'A', detail: '1' }, { title: 'B', detail: '2' }],
    plan: { byLane: { backend: [{ title: 'P' }] } },
  };
  assert.equal(unseenLiveCount(feed, new Set()), 2);
  const seen = new Set([entryKey(feed.live[0])]);
  assert.equal(unseenLiveCount(feed, seen), 1);
  const allSeen = new Set(feed.live.map(entryKey));
  assert.equal(unseenLiveCount(feed, allSeen), 0);
});

test('unseenLiveCount ignores plan seen keys', () => {
  const feed = {
    live: [{ title: 'A', detail: '1' }],
    plan: { byLane: { backend: [{ title: 'P', detail: '' }] } },
  };
  // Marking a plan item seen must not reduce the live badge.
  const seen = new Set([entryKey({ title: 'P', detail: '' })]);
  assert.equal(unseenLiveCount(feed, seen), 1);
});

test('markAllSeen returns every key across live and plan', () => {
  const feed = {
    live: [{ title: 'A', detail: '1' }, { title: 'B', detail: '2' }],
    plan: { byLane: { backend: [{ title: 'P', detail: 'q' }] } },
  };
  const seen = markAllSeen(feed, []);
  assert.equal(seen.length, 3);
  assert.equal(unseenLiveCount(feed, new Set(seen)), 0);
});

test('markAllSeen preserves keys already in the input set', () => {
  const feed = { live: [{ title: 'A', detail: '1' }] };
  const prior = ['stale-key-that-lived-before'];
  const seen = markAllSeen(feed, prior);
  assert.ok(seen.includes('stale-key-that-lived-before'));
});
