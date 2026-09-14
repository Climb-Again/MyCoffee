// Browsing history (#187). Radu, 2026-09-10: "Save the summary and scores of
// coffees I visit and always show last top 10 coffees ranked on score for 10
// days (discard any saves 10 days after visit)."
//
// Lives in `chrome.storage.local`, not the backend. This is "pages I looked at
// in this browser" — it needs no token, no round-trip and no schema, and it
// stays on the machine. The cost is that it does not reach the iOS app; a
// backend-backed version is a separate decision, not a silent default.
//
// Pruning happens on every read AND every write rather than on a timer. A
// timer is the obvious design and the wrong one: an MV3 service worker is
// evicted constantly, Chrome can be shut for a week, and "discard after 10
// days" would then depend on the browser having been open. Pruning at the
// point of use means the rule holds no matter how long the browser was closed.

// #199: one definition of the blend and of roast-age arithmetic, mirrored
// from backend/src/lib/scoring.js and pinned by a contract test. See
// extension/scoring-blend.js for why it is a mirror and not an import.
import { blendScore, daysSinceISO, roastRecencyScore } from './scoring-blend.js';

// #194 sync uses `getSettings`. Must be a STATIC import — this module is
// pulled in by `background.js`'s service worker, and MV3 service workers
// reject `await import()` at runtime ("import() is disallowed on
// ServiceWorkerGlobalScope"). A dynamic import here was the reason the
// shortlist silently stayed empty on every browser: the try/catch around
// `remoteHistory` swallowed the TypeError, the local write still landed,
// nothing reached the server, and no user saw an error.
import { getSettings } from './settings.js';

const KEY = 'history';
// #197 (Radu, 2026-09-12): "discard after 30d from being added to shortlist
// (since you sync on server you have timestamp)". Two changes in one ask, and
// both matter: the window is 30 days, and it is measured from `addedAt` — the
// FIRST time a coffee entered the list — not from `savedAt`, which `upsert`
// overwrites on every revisit. Under the old rule a coffee he kept checking in
// on quietly reset its own clock and rode the list forever, while one he saw
// once and mentally shortlisted fell off at exactly 10 days. Both wrong, in
// opposite directions.
export const RETENTION_DAYS = 30;
export const TOP_N = 10;

// A hard cap so a heavy browsing week cannot grow storage without bound.
// Well above anything 10 days of coffee shopping produces; it is a backstop,
// not a policy.
const MAX_ENTRIES = 300;

const DAY_MS = 86_400_000;

// Same page revisited = same entry. Query strings on shop pages carry cart
// ids, tracking params and variant selections, so a URL compared verbatim
// would file one coffee under several entries. Hash goes too — it is never
// the product.
export function historyKey(url) {
  try {
    const u = new URL(url);
    return `${u.origin}${u.pathname}`.replace(/\/+$/, '');
  } catch {
    return String(url ?? '');
  }
}

// #197: an entry written before this update has no `addedAt`. Falling back to
// `savedAt` is the same as saying "he shortlisted it at its last visit", which
// underestimates its age by at most the old 10-day window — the safe direction,
// since it keeps a row a little longer rather than dropping it early.
export function addedAtOf(entry) {
  if (!entry) return null;
  if (typeof entry.addedAt === 'number') return entry.addedAt;
  return typeof entry.savedAt === 'number' ? entry.savedAt : null;
}

export function prune(entries, now = Date.now()) {
  const cutoff = now - RETENTION_DAYS * DAY_MS;
  return (entries ?? [])
    .filter((e) => {
      const added = addedAtOf(e);
      return added != null && added > cutoff;
    })
    .sort((a, b) => b.savedAt - a.savedAt)
    .slice(0, MAX_ENTRIES);
}

/**
 * The ranked list the popup shows: highest score first, scored entries only.
 *
 * An entry with no score cannot be ranked — that is the point of the
 * suppression, not a gap to paper over — so it is excluded here and counted
 * separately, rather than being sorted as if it were a zero.
 */
export function rank(entries, { limit = TOP_N, now = Date.now() } = {}) {
  const live = prune(entries, now);
  const scored = live.filter((e) => typeof e.score === 'number');
  // #196/#199: rank on the number the popup actually SHOWS, not the frozen one.
  // Otherwise the whole exercise is cosmetic — a bag that just crossed 40 days
  // would display a lower score while still sitting at the top of the list, and
  // a manual -10 would change the badge and nothing else.
  scored.sort((a, b) => displayScore(b, now) - displayScore(a, now) || b.savedAt - a.savedAt);
  return {
    top: scored.slice(0, limit),
    scoredCount: scored.length,
    unscoredCount: live.length - scored.length,
    total: live.length,
  };
}

/**
 * Fold a fresh visit into the list. A revisit REPLACES its earlier entry
 * (same coffee, newer reading) rather than appending — otherwise browsing the
 * same tab twice would put one coffee in the top 10 twice, and the ranking
 * would quietly become "pages I refreshed most".
 */
export function upsert(entries, entry, now = Date.now()) {
  const key = historyKey(entry.url);
  const all = entries ?? [];
  const previous = all.find((e) => historyKey(e.url) === key);
  const rest = all.filter((e) => historyKey(e.url) !== key);
  return prune(
    [
      {
        ...entry,
        // #197: `addedAt` is set ONCE and never bumped by a revisit — that is
        // the whole point of the ask. `savedAt` still moves, because the "seen
        // 2h ago" subtitle (#188) is about the visit.
        addedAt: addedAtOf(previous) ?? addedAtOf(entry) ?? now,
        savedAt: now,
        // #196: a manual adjustment belongs to the coffee, not to the visit, so
        // a re-score must not silently reset it. `entryFromScore` cannot know
        // about it (it only sees the server's response), so carry it here.
        adjustment: clampAdjustment(entry.adjustment ?? previous?.adjustment ?? 0),
      },
      ...rest,
    ],
    now,
  );
}

// ---- manual score adjustment (#196) ----
//
// Radu, 2026-09-12: "add a manual +10p / -10p button to coffees so i can
// adjust". CLIENT-ONLY data: never sent to /api/score (that would corrupt the
// corpus math the score is derived from) and never fed into evaluateCoffee. It
// rides along in the entry payload, so #194's server sync carries it between
// browsers for free — the server stores the payload opaquely.
export const ADJUST_STEP = 10;
export const ADJUST_MAX = 20;

export function clampAdjustment(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.max(-ADJUST_MAX, Math.min(ADJUST_MAX, Math.round(n)));
}

// Repeat taps compound (+10 twice = +20); a tap that would exceed the cap
// resets to 0, which is what makes a single button both "more" and "undo".
export function nextAdjustment(current, delta) {
  const next = clampAdjustment(current) + delta;
  if (next > ADJUST_MAX || next < -ADJUST_MAX) return 0;
  return clampAdjustment(next);
}

export function adjust(entries, url, delta, now = Date.now()) {
  const key = historyKey(url);
  return (entries ?? []).map((e) =>
    historyKey(e.url) === key ? { ...e, adjustment: nextAdjustment(e.adjustment, delta) } : e,
  );
}

export function resetAdjustment(entries, url) {
  const key = historyKey(url);
  return (entries ?? []).map((e) => (historyKey(e.url) === key ? { ...e, adjustment: 0 } : e));
}

// ---- live roast age + re-blended score (#199) ----

/**
 * The bag's age TODAY, from its roast date. Falls back to the age frozen at the
 * visit when no roast date was captured — there is nothing to recompute then.
 */
export function liveRoastDays(entry, now = Date.now()) {
  const fromDate = daysSinceISO(entry?.roastedOn, now);
  if (fromDate != null) return fromDate;
  return typeof entry?.roastDays === 'number' ? entry.roastDays : null;
}

/**
 * The score to render and to rank on: the blend re-run against today's roast
 * term, plus any manual adjustment (#196), clamped to 0-100.
 *
 * An entry stored before #199 has no `valueScore`/`noveltyScore`, so there is
 * nothing to re-blend from — it keeps its frozen `score` and picks up the new
 * fields the next time a visit re-scores it.
 */
export function displayScore(entry, now = Date.now()) {
  if (!entry) return null;
  const adjustment = clampAdjustment(entry.adjustment);
  const canReblend = typeof entry.affinity === 'number'
    && (typeof entry.valueScore === 'number' || typeof entry.noveltyScore === 'number');

  let base = typeof entry.score === 'number' ? entry.score : null;
  if (canReblend) {
    const days = liveRoastDays(entry, now);
    const reblended = blendScore(
      {
        affinity: entry.affinity,
        roast: roastRecencyScore(days),
        value: entry.valueScore,
        novelty: entry.noveltyScore,
      },
      days,
    );
    if (reblended != null) base = reblended;
  }
  if (base == null) return null;
  return Math.max(0, Math.min(100, base + adjustment));
}

// Only what the list actually renders. Deliberately NOT the page text: it can
// be 60 KB, it is worthless once scored, and chrome.storage.local is not the
// place for it.
export function entryFromScore(data, { url, title }) {
  return {
    url,
    title: title || data?.match?.rawTitle || null,
    score: typeof data?.score === 'number' ? data.score : null,
    confidence: data?.confidence ?? null,
    explanation: data?.explanation ?? null,
    roasterName: data?.fields?.roasterName ?? null,
    originName: data?.fields?.originName ?? null,
    profileId: data?.fields?.profileId ?? null,
    pricePer100gEur: data?.fields?.pricePer100gEur ?? null,
    priceAmount: data?.fields?.priceAmount ?? null,
    priceCurrency: data?.fields?.priceCurrency ?? null,
    weightG: data?.fields?.weightG ?? null,
    roastedOn: data?.fields?.roastedOn ?? null,
    imageUrl: data?.imageUrl ?? null,
    // Value pills and the affinity number, for the app-style right column.
    valuePills: data?.components?.value?.pillCount ?? null,
    affinity: data?.components?.affinity?.score ?? null,
    // #199: the component INPUTS are frozen; only the ROAST term is live.
    //
    // The inputs are snapshots of Radu's library at the moment of the visit — a
    // roaster he adds later must not retroactively change that page's novelty —
    // and re-deriving them would need the page text, which #187 deliberately
    // does not store. But a bag's AGE is a fact about the bag, not about the
    // visit, and the stale penalty is a rule about that fact: one shortlisted
    // at 30 days (no penalty) is 45 days two weeks later (-10), and the number
    // he would shop on has to say so. #188 froze both together to keep the chip
    // and the score consistent; the fix is to recompute both, not freeze both.
    //
    // `valueScore`/`noveltyScore` are stored so an entry can actually be
    // re-blended — before this, only `pillCount` and `affinity.score` landed,
    // so an older row had nothing to re-blend from. Rows written before this
    // version have neither and fall back to their frozen `score` (see
    // `displayScore`), degrading gracefully rather than showing nothing.
    valueScore: data?.components?.value?.score ?? null,
    noveltyScore: data?.components?.novelty?.score ?? null,
    roastDays: data?.components?.roast?.daysSinceRoast ?? null,
    roastStale: data?.components?.roast?.stale ?? null,
    // Owned coffees are worth flagging in the list — "I already have this" is
    // the most useful thing the row can say.
    ownedTitle: data?.match?.rawTitle ?? null,
  };
}

// ---- remote sync (#194) ----
//
// The shortlist moved from per-browser chrome.storage.local to a backend list
// keyed on the token (`/api/history`), so Chrome, Brave and Firefox — and iOS
// later (#195) — all see the same rows. chrome.storage.local stays as an
// OFFLINE CACHE, not the source of truth: reads race the network and fall back
// to it, writes update it immediately so a row shows before the round-trip
// finishes. The server owns pruning (#187) — a browser closed for 10 days must
// not un-prune a row on next sync — so a remote result REPLACES the cache
// wholesale rather than being merged into it.
//
async function remoteHistory(method, body) {
  const { baseUrl, writeToken } = await getSettings();
  // No write token → local-only, exactly as before #194. Syncing is a write
  // (it stores under that token) and reuses the same INGEST_TOKEN #161 does.
  if (!writeToken) return null;
  const res = await fetch(`${baseUrl}/api/history`, {
    method,
    headers: {
      authorization: `Bearer ${writeToken}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!res.ok) return null;
  const data = await res.json();
  return Array.isArray(data?.entries) ? data.entries : null;
}

export async function loadHistory(now = Date.now()) {
  // Remote first: the backend list is the shared truth. Prune client-side too
  // (belt and braces — the server already did) and adopt it as the cache.
  //
  // #214 trap: `if (remote)` treated an empty array as authoritative because
  // `Boolean([])` is `true` in JS. When the server had 0 rows for the token
  // (a POST that silently failed leaves it that way — #213's dynamic-import
  // bug was one of those), a GET would overwrite the local cache with `[]`
  // and any unsynced local write vanished on the next popup open. Now the
  // rule is explicit: only adopt the remote list when it is BOTH an array
  // AND non-empty; an empty server response falls through to the local
  // cache path below, so unsynced writes survive the round-trip. A genuine
  // "user cleared the list" doesn't go through here — it goes through
  // `clearHistory`, which resets local storage directly.
  try {
    const remote = await remoteHistory('GET');
    if (Array.isArray(remote) && remote.length > 0) {
      const live = prune(remote, now);
      await chrome.storage.local.set({ [KEY]: live });
      return live;
    }
  } catch (e) {
    console.warn('[mycoffee] history sync (read) failed; using local cache', e);
  }
  // Fallback: local cache (no write token, or the network is down, or server
  // is empty). If the local cache has unsynced entries, hand them back and
  // give reconcileToServer a shot at posting them, so the next open sees the
  // authoritative list on both sides.
  const stored = await chrome.storage.local.get(KEY);
  const live = prune(stored?.[KEY], now);
  if ((stored?.[KEY]?.length ?? 0) !== live.length) {
    await chrome.storage.local.set({ [KEY]: live });
  }
  if (live.length > 0) reconcileToServer(live, now);
  return live;
}

// Fire-and-forget best-effort push of local rows the server does not have.
// Runs on popup open when GET came back empty but the cache is not — the
// exact shape #213's write bug left every install in. Idempotent: the server
// upserts by (token_hash, url_key), so a re-post of the same row is a no-op.
async function reconcileToServer(entries, now) {
  try {
    for (const entry of entries) {
      // Server response is ignored on purpose: we just want the rows to land.
      // A repeated call after they already exist is a no-op server-side.
      await remoteHistory('POST', entry);
    }
  } catch (e) {
    console.warn('[mycoffee] history reconcile failed; will retry next open', e);
  }
}

export async function recordVisit(data, { url, title }, now = Date.now()) {
  if (!url) return null;
  const entry = entryFromScore(data, { url, title });
  // Update the local cache immediately so the row is present offline and
  // before the round-trip returns.
  const stored = await chrome.storage.local.get(KEY);
  const local = upsert(stored?.[KEY], entry, now);
  await chrome.storage.local.set({ [KEY]: local });
  // Then sync. The server upserts, prunes and returns the merged list, so a
  // row saved on another browser appears here too; adopt it as the cache.
  try {
    const remote = await remoteHistory('POST', entry);
    if (remote) {
      const live = prune(remote, now);
      await chrome.storage.local.set({ [KEY]: live });
      return live;
    }
  } catch (e) {
    console.warn('[mycoffee] history sync (write) failed; kept locally', e);
  }
  return local;
}

export async function clearHistory() {
  // Clear the shared list too, or the next loadHistory would pull it straight
  // back from the server. Best-effort: if the remote clear fails, the local
  // wipe still happens and the next successful sync reconciles.
  try {
    await remoteHistory('DELETE');
  } catch (e) {
    console.warn('[mycoffee] history clear (remote) failed; cleared locally', e);
  }
  await chrome.storage.local.set({ [KEY]: [] });
}

// ---- roast-age colour (#188) ----
//
// Radu: "Make roasting date color coded - green less than 2w going red as its
// older". A continuous hue ramp rather than three buckets, so there is no
// visual cliff where one day changes the colour completely -- except at 40
// days, where there IS a real cliff, because that is where the scoring
// penalty lands and the colour should say so.
export const ROAST_GREEN_DAYS = 14;
export const ROAST_RED_DAYS = 60;

export function roastColor(days) {
  if (days == null || !Number.isFinite(days)) return null;
  // 130 = green, 35 = amber, 0 = red.
  const GREEN = 130;
  const RED = 0;
  if (days <= ROAST_GREEN_DAYS) return `hsl(${GREEN} 62% 38%)`;
  if (days >= ROAST_RED_DAYS) return `hsl(${RED} 70% 45%)`;
  const t = (days - ROAST_GREEN_DAYS) / (ROAST_RED_DAYS - ROAST_GREEN_DAYS);
  return `hsl(${Math.round(GREEN - t * (GREEN - RED))} 66% 41%)`;
}

// Age from an ISO roast date, for when the response carries the date but no
// computed component (#190: an older or newer server than this build expects).
// Belt and braces -- the chip must never fall back to an unlabelled number.
// Re-exported from scoring-blend.js (#199) so there is exactly one copy of this
// arithmetic; every existing caller keeps importing it from here.
export { daysSinceISO };

export function roastLabel(days) {
  if (days == null) return null;
  if (days === 0) return 'roasted today';
  if (days === 1) return 'roasted 1d ago';
  if (days < 7) return `roasted ${days}d ago`;
  if (days < 70) return `roasted ${days}d ago`;
  const months = Math.round(days / 30);
  return `roasted ~${months}mo ago`;
}

// "when did I look at this" -- the timestamp was always stored, never shown.
export function relativeTime(ts, now = Date.now()) {
  if (!ts) return '';
  // FLOOR at the minute scale, not round: Math.round(0.5) is 1, so 30 seconds
  // ago rendered as "1m ago" instead of "just now". Hours and days stay
  // rounded — at those scales nearest reads better than truncated.
  const mins = Math.max(0, Math.floor((now - ts) / 60_000));
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  return days === 1 ? 'yesterday' : `${days}d ago`;
}
