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

const KEY = 'history';
export const RETENTION_DAYS = 10;
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

export function prune(entries, now = Date.now()) {
  const cutoff = now - RETENTION_DAYS * DAY_MS;
  return (entries ?? [])
    .filter((e) => e && typeof e.savedAt === 'number' && e.savedAt > cutoff)
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
  scored.sort((a, b) => b.score - a.score || b.savedAt - a.savedAt);
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
  const rest = (entries ?? []).filter((e) => historyKey(e.url) !== key);
  return prune([{ ...entry, savedAt: now }, ...rest], now);
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
    // #188: the age AS EVALUATED, not recomputed at render time. A bag
    // roasted 39 days before a visit was fresh-ish when he looked at it, and
    // the saved score reflects that -- recomputing the age later would show a
    // red chip beside a score that was calculated when it was amber.
    roastDays: data?.components?.roast?.daysSinceRoast ?? null,
    roastStale: data?.components?.roast?.stale ?? null,
    // Owned coffees are worth flagging in the list — "I already have this" is
    // the most useful thing the row can say.
    ownedTitle: data?.match?.rawTitle ?? null,
  };
}

export async function loadHistory(now = Date.now()) {
  const stored = await chrome.storage.local.get(KEY);
  const live = prune(stored?.[KEY], now);
  // Write back only when pruning actually removed something, so a plain read
  // does not churn storage on every popup open.
  if ((stored?.[KEY]?.length ?? 0) !== live.length) {
    await chrome.storage.local.set({ [KEY]: live });
  }
  return live;
}

export async function recordVisit(data, { url, title }, now = Date.now()) {
  if (!url) return null;
  const stored = await chrome.storage.local.get(KEY);
  const next = upsert(stored?.[KEY], entryFromScore(data, { url, title }), now);
  await chrome.storage.local.set({ [KEY]: next });
  return next;
}

export async function clearHistory() {
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
export function daysSinceISO(iso, now = Date.now()) {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return null;
  return Math.max(0, Math.floor((now - t) / 86_400_000));
}

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
