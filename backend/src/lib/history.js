// #194 — pure helpers for the backend-backed shortlist (/api/history).
//
// The extension's client copy (extension/history.js, #187) owns the same rule
// set; these mirror it so server and client agree on what "the same coffee" is
// and how long a row lives. They are deliberately duplicated rather than
// shared (the browser cannot import backend code); history-lib.test.js pins
// the constants to the extension's values so the two cannot drift silently.

// Retention window, in days, measured from the row's `added_at` — the first
// time the coffee entered the shortlist, NOT the last visit (#197). `saved_at`
// is bumped on every revisit, so keying retention on it meant a coffee Radu
// kept checking in on quietly reset its own clock and rode the list forever,
// while one he saw once and mentally shortlisted fell off at exactly 10 days.
// Dropped on the next read or write — never on a timer, since a browser can be
// shut for a week.
//
// ⚠ Pinned against extension/history.js by history-lib.test.js. Change both.
export const RETENTION_DAYS = 30;

// A hard cap per token so a heavy browsing week cannot grow the table without
// bound. A backstop, not a policy — well above anything 10 days of coffee
// shopping produces.
export const MAX_ENTRIES = 300;

// Same page revisited = same entry. Shop URLs carry cart ids, tracking params
// and variant selections, so a URL compared verbatim would file one coffee
// under several keys; the hash is never the product either. Identical to the
// extension's historyKey so a row written by the client upserts, not
// duplicates, once it round-trips through the server.
export function historyKey(url) {
  try {
    const u = new URL(url);
    return `${u.origin}${u.pathname}`.replace(/\/+$/, '');
  } catch {
    return String(url ?? '');
  }
}
