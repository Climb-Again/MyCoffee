// What's New — pure functions over the /api/whatsnew feed (#200).
//
// The backend serves `{live: [{title, detail, area}], plan: {byLane: {backend: [{title, detail}], …}}}`
// with no stable per-entry id. We key seen-state on a stable hash of
// `title\ndetail` so a re-worded entry keeps its check and a genuinely
// re-titled one legitimately unchecks — the alternative (positional index)
// silently shifts every checkmark the moment a new item lands on top.

const CACHE_KEY = 'whatsnew:feed';
const SEEN_KEY = 'whatsnew:seen';
const FEED_TTL_MS = 10 * 60 * 1000;

// Fast, stable, non-cryptographic. FNV-1a hash on the joined string, hex.
// Not a security primitive; a collision here just means two entries share a
// checkbox, which is worth much less than the cost of pulling in a crypto lib.
export function entryKey(entry) {
  const s = `${entry?.title ?? ''}\n${entry?.detail ?? ''}`;
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

export function liveEntries(feed) {
  return Array.isArray(feed?.live) ? feed.live : [];
}

// Plan is `{byLane: {backend: [...], ios-ux: [...], ...}}`. Flatten to a list
// of `{lane, entry}` in a stable lane order so the UI can render sections
// without inventing an order every render — matches what the iOS side does.
const LANE_ORDER = ['backend', 'data', 'ios-shell', 'ios-ux', 'publish'];

export function planByLane(feed) {
  const by = feed?.plan?.byLane ?? {};
  const knownLanes = LANE_ORDER.filter((l) => Array.isArray(by[l]) && by[l].length);
  const extras = Object.keys(by)
    .filter((l) => !LANE_ORDER.includes(l) && Array.isArray(by[l]) && by[l].length)
    .sort();
  return [...knownLanes, ...extras].map((lane) => ({ lane, entries: by[lane] }));
}

// Unseen counts the LIVE side only. Plan items are things Radu already knows
// he asked for; badging them would light the toolbar the moment a row is
// filed, which is noise. Live = "shipped for you to notice", which is the
// signal the badge exists to carry.
export function unseenLiveCount(feed, seen) {
  const set = seen instanceof Set ? seen : new Set(seen ?? []);
  return liveEntries(feed).filter((e) => !set.has(entryKey(e))).length;
}

export function markAllSeen(feed, prev = []) {
  const set = new Set(prev);
  for (const e of liveEntries(feed)) set.add(entryKey(e));
  for (const { entries } of planByLane(feed)) for (const e of entries) set.add(entryKey(e));
  return [...set];
}

// ---- chrome.storage glue (skipped in tests via dependency injection) ----

export async function loadSeen() {
  const stored = await chrome.storage.local.get(SEEN_KEY);
  return new Set(stored?.[SEEN_KEY] ?? []);
}

export async function saveSeen(seen) {
  await chrome.storage.local.set({ [SEEN_KEY]: [...seen] });
}

export async function fetchFeed(baseUrl, token, { now = Date.now(), maxAgeMs = FEED_TTL_MS } = {}) {
  const cached = await chrome.storage.local.get(CACHE_KEY);
  const hit = cached?.[CACHE_KEY];
  if (hit && now - hit.at < maxAgeMs) return hit.feed;

  const res = await fetch(`${baseUrl}/api/whatsnew`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  if (!res.ok) throw new Error(`whatsnew HTTP ${res.status}`);
  const feed = await res.json();
  await chrome.storage.local.set({ [CACHE_KEY]: { at: now, feed } });
  return feed;
}
