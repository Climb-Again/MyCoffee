#!/usr/bin/env node
// Regenerates the `plan` half of backend/src/data/whatsnew.json from
// status/BACKLOG.md — the file the in-app What's New > Plan tab reads.
//
// WHY THIS EXISTS
// ---------------
// `routes/whatsnew.js` used to say "keep it in sync with status/BACKLOG.md by
// hand whenever a row flips." Nobody owned that: `whatsnew.json` was last
// touched 2026-08-27 and by 2026-09-11 the Plan tab was showing 8 iOS items
// that had ALL shipped, and **zero** backend and data items while 14 backend
// rows sat `ready`. The one screen whose entire job is telling Radu what is
// planned was the most out-of-date thing in the repo — and nothing caught it,
// because a stale JSON file compiles, deploys and serves 200 exactly like a
// fresh one.
//
// So the plan is no longer curated. It is derived, and CI fails on drift
// (`--check`, wired into .github/workflows/backlog-check.yml). `live` stays
// hand-written: that half is release-note prose about things that already
// shipped, which is a genuine writing job and does not go stale on its own.
//
// ONE COUPLING TO KNOW ABOUT
// --------------------------
// This writes under `backend/`, and Railway deploys on any push touching
// `backend/**` — so wiring this up made every backlog row flip a potential
// redeploy, and a redeploy SIGTERMs a running extraction worker (CLAUDE.md
// §12). `railway-deploy.yml`'s path filter therefore negates this one file.
// The deployed plan then lags the repo by at most one backend deploy, which is
// bounded and self-correcting — unlike the 15 days of staleness it replaced.
//
// Usage:
//   node ops/gen-whatsnew-plan.mjs            # rewrite the plan section
//   node ops/gen-whatsnew-plan.mjs --check    # exit 1 if it would change
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const BACKLOG = path.join(ROOT, 'status', 'BACKLOG.md');
const TARGET = path.join(ROOT, 'backend', 'src', 'data', 'whatsnew.json');

/** Backlog lanes -> the three areas the iOS Plan tab groups by. */
const LANE_TO_AREA = {
  backend: 'backend',
  data: 'data',
  'ios-shell': 'ios',
  'ios-ux': 'ios',
  publish: 'ios',
};

/** Statuses that mean "still ahead of us" — everything else is history. */
const OPEN = new Set(['ready', 'blocked', 'claimed']);

export function parseRows(markdown) {
  const rows = [];
  for (const line of markdown.split('\n')) {
    if (!/^\|\s*\d{1,3}\s*\|/.test(line)) continue;
    // Split on the leading 6 cells only: the Item cell itself contains pipes
    // inside inline code, and splitting greedily mangles it.
    const cells = line.split('|');
    if (cells.length < 7) continue;
    const number = Number(cells[1].trim());
    const lane = cells[2].trim();
    const phase = cells[3].trim();
    const status = cells[4].trim();
    const item = cells.slice(6).join('|').trim();
    rows.push({ number, lane, phase, status, item });
  }
  return rows;
}

/**
 * A readable one-liner from a row's engineer-facing prose.
 *
 * Backlog items open with a bolded summary far more often than not
 * ("**Stop retrying a photo whose OCR keeps coming back illegible…**"), so a
 * leading `**…**` span is the best available headline — after any status
 * banner ("**DONE 2026-09-09.**", "**UNBLOCKED …**") is stripped, since that
 * describes the row's history rather than what the row is.
 */
export function titleFor(item) {
  const rest = withoutLeadingStatusShouts(item);
  // If what's left still OPENS with a bold span, that span is the row's own
  // headline and is always the best title. Otherwise the shout consumed it
  // (rows re-opened by an audit often leave the real summary as plain prose,
  // sometimes with an unbalanced `**`), so fall back to the first sentence —
  // which for those rows is exactly the summary the shout displaced.
  const leadingBold = rest.match(/^\*\*(.+?)\*\*/s);
  const raw = leadingBold
    ? leadingBold[1]
    : stripMarkdown(rest).split(/(?<=[.!?])\s/)[0] ?? rest;
  return clip(stripMarkdown(raw));
}

/**
 * Strips the "**DONE 2026-09-09.**" / "**UNBLOCKED …**" banners that sessions
 * prepend to a row when its state changes. They are the newest thing in the
 * cell and therefore the first bold span, but they describe the row's history,
 * not what the row IS.
 */
function withoutLeadingStatusShouts(item) {
  const shout = /^\s*\*\*\s*(DONE|UNBLOCKED|RE-?BLOCKED|BLOCKED|CLOSED|CLOSED OUT|OBSOLETE|CORRECTION|NOTE|SUPERSEDED)\b[^*]*\*\*\s*/i;
  let rest = item;
  while (shout.test(rest)) rest = rest.replace(shout, '');
  return rest;
}

function stripMarkdown(text) {
  return text
    .replace(/`([^`]*)`/g, '$1')
    .replace(/\*\*/g, '')
    .replace(/\*/g, '')
    .replace(/~~/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function clip(text, max = 110) {
  if (text.length <= max) return text.replace(/[.,;:—-]+$/, '');
  return text.slice(0, max - 1).replace(/\s+\S*$/, '') + '…';
}

export function buildPlan(rows) {
  const byLane = { backend: [], data: [], ios: [] };
  const needsApproval = [];

  const open = rows
    .filter((r) => OPEN.has(r.status))
    .sort((a, b) => Number(a.phase) - Number(b.phase) || a.number - b.number);

  for (const row of open) {
    const area = LANE_TO_AREA[row.lane];
    if (!area) continue; // `human` rows are handled below, anything else is a typo
    byLane[area].push({
      title: titleFor(row.item),
      // "blocked" is worth surfacing: it tells Radu the thing he asked about
      // is queued behind something, not forgotten.
      detail: row.status === 'blocked' ? 'Queued behind earlier work.' : 'Queued.',
    });
  }

  for (const row of rows.filter((r) => r.status === 'human')) {
    needsApproval.push({ title: titleFor(row.item), detail: 'Waiting on your call.' });
  }
  // Standing constraint, not a backlog row — CLAUDE.md §12's hard cap.
  needsApproval.push({
    title: 'Anything that would exceed the 50 MB app+data cap',
    detail: 'A lane will ask before crossing it rather than deciding on its own.',
  });

  return { byLane, needsApproval };
}

function main() {
  const check = process.argv.includes('--check');
  const rows = parseRows(readFileSync(BACKLOG, 'utf8'));
  const current = JSON.parse(readFileSync(TARGET, 'utf8'));
  const next = { ...current, plan: buildPlan(rows) };
  const serialized = JSON.stringify(next, null, 2) + '\n';
  const existing = readFileSync(TARGET, 'utf8');

  if (serialized === existing) {
    console.log('gen-whatsnew-plan: OK — plan section matches status/BACKLOG.md');
    return;
  }
  if (check) {
    const counts = Object.entries(next.plan.byLane)
      .map(([lane, items]) => `${lane}:${items.length}`)
      .join(' ');
    console.error(
      'FAIL whatsnew plan is stale — backend/src/data/whatsnew.json does not match status/BACKLOG.md.\n' +
        `  expected open rows by area: ${counts}\n` +
        '  fix: node ops/gen-whatsnew-plan.mjs && git add backend/src/data/whatsnew.json'
    );
    process.exit(1);
  }
  writeFileSync(TARGET, serialized);
  console.log(
    `gen-whatsnew-plan: wrote ${next.plan.byLane.backend.length} backend / ` +
      `${next.plan.byLane.data.length} data / ${next.plan.byLane.ios.length} ios items`
  );
}

main();
