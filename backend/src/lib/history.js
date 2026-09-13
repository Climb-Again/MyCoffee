// #194 — pure helpers for the backend-backed shortlist (/api/history).
//
// The extension's client copy (extension/history.js, #187) owns the same rule
// set; these mirror it so server and client agree on what "the same coffee" is
// and how long a row lives. They are deliberately duplicated rather than
// shared (the browser cannot import backend code); history-lib.test.js pins
// the constants to the extension's values so the two cannot drift silently.

// Retention window, in days. A save older than this is dropped on the next
// read or write — never on a timer, since a browser can be shut for a week.
export const RETENTION_DAYS = 10;

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
