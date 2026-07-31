// Controlled-vocabulary matching — "guess only very close matches", made
// mechanical (PLAN.md §2). A fuzzy match auto-accepts only when ALL of:
//   1. normalised Levenshtein similarity ≥ 0.90 OR trigram similarity ≥ 0.55
//   2. there is a unique best candidate (no tie at the top score)
//   3. the margin over the runner-up is ≥ 0.15
// Anything short of that becomes a review item rather than a silent merge —
// this is what stops `Kofio` from ever being folded into `Kolibri`, and
// `Father Carpenter` from being folded into `Father's Coffee Roastery`.

import { normalizeVocabString } from './normalize.js';

const DEFAULT_LEV_THRESHOLD = 0.9;
const DEFAULT_TRIGRAM_THRESHOLD = 0.55;
const DEFAULT_MARGIN = 0.15;

export function levenshteinDistance(a, b) {
  const s = String(a);
  const t = String(b);
  const m = s.length;
  const n = t.length;
  if (m === 0) return n;
  if (n === 0) return m;

  let prev = new Array(n + 1);
  let curr = new Array(n + 1);
  for (let j = 0; j <= n; j++) prev[j] = j;

  for (let i = 1; i <= m; i++) {
    curr[0] = i;
    for (let j = 1; j <= n; j++) {
      const cost = s[i - 1] === t[j - 1] ? 0 : 1;
      curr[j] = Math.min(
        prev[j] + 1,      // deletion
        curr[j - 1] + 1,  // insertion
        prev[j - 1] + cost // substitution
      );
    }
    [prev, curr] = [curr, prev];
  }
  return prev[n];
}

export function normalizedLevenshteinSimilarity(a, b) {
  const an = normalizeVocabString(a);
  const bn = normalizeVocabString(b);
  const maxLen = Math.max(an.length, bn.length);
  if (maxLen === 0) return 1;
  return 1 - levenshteinDistance(an, bn) / maxLen;
}

function trigramSet(s) {
  // Pad like pg_trgm's word trigrams (2 leading blanks, 1 trailing) so short
  // strings still produce boundary-aware trigrams.
  const padded = `  ${s} `;
  const set = new Set();
  for (let i = 0; i <= padded.length - 3; i++) {
    set.add(padded.slice(i, i + 3));
  }
  return set;
}

// Sørensen–Dice coefficient over character-trigram sets. Deliberately more
// forgiving than the Jaccard ratio Postgres's pg_trgm index uses (which only
// narrows DB-side candidates) — this is the JS-side confidence score.
export function trigramSimilarity(a, b) {
  const ta = trigramSet(normalizeVocabString(a));
  const tb = trigramSet(normalizeVocabString(b));
  if (ta.size === 0 && tb.size === 0) return 1;
  let common = 0;
  for (const t of ta) if (tb.has(t)) common++;
  return (2 * common) / (ta.size + tb.size);
}

export function matchVocab(input, candidates, opts = {}) {
  const levThreshold = opts.levThreshold ?? DEFAULT_LEV_THRESHOLD;
  const trigramThreshold = opts.trigramThreshold ?? DEFAULT_TRIGRAM_THRESHOLD;
  const margin = opts.margin ?? DEFAULT_MARGIN;

  if (!input || !candidates || candidates.length === 0) {
    return { accepted: false, match: null, reason: 'no candidates' };
  }

  const scored = candidates.map((c) => {
    const name = typeof c === 'string' ? c : c.name;
    const lev = normalizedLevenshteinSimilarity(input, name);
    const trigram = trigramSimilarity(input, name);
    return {
      candidate: c,
      lev,
      trigram,
      passesThreshold: lev >= levThreshold || trigram >= trigramThreshold,
      score: Math.max(lev, trigram),
    };
  });
  scored.sort((x, y) => y.score - x.score);

  const best = scored[0];
  const runnerUp = scored[1];

  if (!best.passesThreshold) {
    return { accepted: false, match: null, best, reason: 'below threshold' };
  }
  if (runnerUp && runnerUp.score === best.score) {
    return { accepted: false, match: null, best, runnerUp, reason: 'not a unique best candidate' };
  }
  const marginScore = runnerUp ? best.score - runnerUp.score : 1;
  if (marginScore < margin) {
    return { accepted: false, match: null, best, runnerUp, margin: marginScore, reason: 'insufficient margin over runner-up' };
  }
  return { accepted: true, match: best.candidate, confidence: best.score, best, runnerUp, margin: marginScore };
}
