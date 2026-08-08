// Deterministic adjudication over stored candidate rows (PLAN.md §2, §11).
// Pure — no DB, no network: every input (candidate rows, the vocab
// dictionary, fx rates) is passed in, so re-adjudicating the whole corpus
// after a rule tweak is a few milliseconds and costs nothing. The model
// never decides whether it was right; this module does.
//
// Field value shapes, as returned by `canonicalize()`:
//   roaster_id / origin_farm_id -> { id, confidenceFactor }
//   origin_country_ids          -> { ids: number[], isBlend, unresolved }
//   altitude                    -> { min, max, confidenceFactor, needsReview }
//   price                       -> { amount, currency, confidenceFactor }
//   weight_g                    -> { grams, confidenceFactor }
//   rating                      -> { value, confidenceFactor }
//   roasted_on                  -> { date: 'YYYY-MM-DD' }
//   profile                     -> { profileId, isDecaf, detail }
//   desc_* (prose)               -> { start, end, text }
import {
  parseAltitude,
  parsePrice,
  parseWeight,
  parseRating,
  parseDate,
  parseProfile,
} from './normalize.js';
import { resolveVocab, resolveOriginCountries } from './vocab.js';

export const PROSE_FIELDS = ['desc_farm_lot', 'desc_brew_guide', 'desc_roaster_copy'];

export function isProseField(field) {
  return PROSE_FIELDS.includes(field);
}

function clamp01(n) {
  return Math.max(0, Math.min(1, n));
}

function round3(n) {
  return Math.round(n * 1000) / 1000;
}

function normalizeProseText(s) {
  return String(s ?? '').trim().replace(/\s+/g, ' ');
}

// ---- Canonicalisation: raw candidate value -> comparable form ----

export function canonicalize(field, rawValue, ctx = {}) {
  if (rawValue == null) return null;

  switch (field) {
    case 'roaster_id': {
      const r = resolveVocab(rawValue, ctx.vocab?.roasters, ctx.fuzzyOpts);
      return r.resolved && r.id != null ? { id: r.id, confidenceFactor: r.confidence ?? 1 } : null;
    }
    case 'origin_farm_id': {
      const r = resolveVocab(rawValue, ctx.vocab?.farms, ctx.fuzzyOpts);
      return r.resolved && r.id != null ? { id: r.id, confidenceFactor: r.confidence ?? 1 } : null;
    }
    case 'origin_country_ids': {
      const r = resolveOriginCountries(rawValue, ctx.vocab?.countries, ctx.fuzzyOpts);
      if (r.ids.length === 0) return null;
      return {
        ids: [...r.ids].sort((a, b) => a - b),
        isBlend: r.isBlend,
        unresolved: r.unresolved,
        // A partial miss (one origin resolved, one didn't) should never look
        // as confident as a clean full resolve.
        confidenceFactor: r.unresolved.length > 0 ? 0.6 : 1,
      };
    }
    case 'altitude': {
      const r = parseAltitude(rawValue);
      return r ? { min: r.min, max: r.max, confidenceFactor: r.confidence, needsReview: r.needsReview } : null;
    }
    case 'price': {
      const r = parsePrice(rawValue);
      return r && r.currency ? { amount: r.amount, currency: r.currency, confidenceFactor: r.confidence } : null;
    }
    case 'weight_g': {
      const r = parseWeight(rawValue);
      return r ? { grams: r.grams, confidenceFactor: r.confidence } : null;
    }
    case 'rating': {
      const r = parseRating(rawValue);
      return r ? { value: r.value, confidenceFactor: r.confidence } : null;
    }
    case 'roasted_on': {
      const r = parseDate(rawValue, { photoDate: ctx.photoDate });
      return r && !r.rejected ? { date: r.date.toISOString().slice(0, 10), confidenceFactor: 1 } : null;
    }
    case 'profile': {
      const r = parseProfile(rawValue);
      return { profileId: r.profileId, isDecaf: r.isDecaf, detail: r.detail, confidenceFactor: 1 };
    }
    default:
      if (isProseField(field)) {
        if (!ctx.rawText || typeof rawValue.start !== 'number' || typeof rawValue.end !== 'number') return null;
        const start = Math.max(0, Math.min(rawValue.start, ctx.rawText.length));
        const end = Math.max(start, Math.min(rawValue.end, ctx.rawText.length));
        const text = ctx.rawText.slice(start, end).trim();
        return text ? { start, end, text, confidenceFactor: 1 } : null;
      }
      return { raw: rawValue, confidenceFactor: 1 };
  }
}

// ---- Equality: do two canonical values agree? ----

export function fieldsEqual(field, a, b) {
  if (a == null || b == null) return false;
  switch (field) {
    case 'roaster_id':
    case 'origin_farm_id':
      return a.id === b.id;
    case 'origin_country_ids':
      return a.ids.length === b.ids.length && a.ids.every((id, i) => id === b.ids[i]);
    case 'altitude': {
      const amid = (a.min + a.max) / 2;
      const bmid = (b.min + b.max) / 2;
      return Math.abs(amid - bmid) <= 50;
    }
    case 'price':
      return a.currency === b.currency && Math.abs(a.amount - b.amount) <= 0.05;
    case 'weight_g':
      return a.grams === b.grams;
    case 'rating':
      return Math.abs(a.value - b.value) <= 0.05;
    case 'roasted_on':
      return a.date === b.date;
    case 'profile':
      return a.profileId === b.profileId && a.isDecaf === b.isDecaf;
    default:
      if (isProseField(field)) return normalizeProseText(a.text) === normalizeProseText(b.text);
      return JSON.stringify(a.raw ?? a) === JSON.stringify(b.raw ?? b);
  }
}

// ---- Value to store in field_resolutions.value / apply to a coffees column ----

export function denormalize(field, canonical) {
  switch (field) {
    case 'roaster_id':
    case 'origin_farm_id':
      return canonical.id;
    case 'origin_country_ids':
      return canonical.ids;
    case 'altitude':
      return { min: canonical.min, max: canonical.max };
    case 'price':
      return { amount: canonical.amount, currency: canonical.currency };
    case 'weight_g':
      return canonical.grams;
    case 'rating':
      return canonical.value;
    case 'roasted_on':
      return canonical.date;
    case 'profile':
      return { profileId: canonical.profileId, isDecaf: canonical.isDecaf, detail: canonical.detail };
    default:
      if (isProseField(field)) return canonical.text;
      return canonical.raw ?? canonical;
  }
}

function weightFor(field, agent, ctx) {
  if (agent === 'rules') {
    if ((ctx.ruleVoterProseFields ?? []).includes(field)) return 0;
    if ((ctx.ruleVoterWeightedFields ?? []).includes(field)) return ctx.ruleVoterWeight ?? 1.5;
  }
  return 1;
}

function clusterCandidates(field, candidates) {
  const clusters = [];
  for (const cand of candidates) {
    const cluster = clusters.find((cl) => fieldsEqual(field, cl.members[0].canonical, cand.canonical));
    if (cluster) {
      cluster.members.push(cand);
      cluster.totalWeight += cand.weight;
    } else {
      clusters.push({ members: [cand], totalWeight: cand.weight });
    }
  }
  return clusters;
}

// ---- Decide one field from its raw candidates ----
//
// rawCandidates: [{ agent, value, confidence, evidence }] -- `value` is the
// voter's raw (uncanonicalized) output for this field.
//
// Accept-by-default policy (PLAN.md §11, Radu's 2026-08-08 directive): a
// field only goes to review when voters genuinely land on different
// canonical values. Self-reported confidence no longer gates the decision --
// in practice it has not once picked a wrong value -- so a single voter or a
// fully agreeing cluster is ACCEPTED regardless of confidence. `no_candidates`
// (the field is simply absent from the source) is its own decision, not a
// review item: leave the column null and move on.
export function adjudicateField(field, rawCandidates, ctx = {}) {
  // Critic (P4) never contributes a value -- it only refutes. A refuted field
  // gets every LLM voter's confidence discounted before clustering; P3 (rules)
  // is untouched since it's not vision-dependent, which is exactly what the
  // critic is checking for.
  const criticRefuted = Boolean(ctx.criticVerdicts?.[field]?.refuted);
  const criticPenalty = ctx.criticPenalty ?? 0.5;

  const candidates = (rawCandidates ?? [])
    .map((c) => {
      const canonical = canonicalize(field, c.value, ctx);
      if (canonical == null) return null;
      let confidence = clamp01((c.confidence ?? 1) * (canonical.confidenceFactor ?? 1));
      if (criticRefuted && c.agent !== 'rules') confidence *= criticPenalty;
      return { agent: c.agent, canonical, confidence, weight: weightFor(field, c.agent, ctx), evidence: c.evidence };
    })
    .filter(Boolean);

  if (candidates.length === 0) {
    return { field, value: null, confidence: 0, agreement: 0, voters: [], decision: 'absent', reviewReason: null };
  }

  const clusters = clusterCandidates(field, candidates).sort((a, b) => b.totalWeight - a.totalWeight);
  const winner = clusters[0];
  const totalWeight = clusters.reduce((s, cl) => s + cl.totalWeight, 0);
  const share = totalWeight > 0 ? winner.totalWeight / totalWeight : 0;
  const winnerVoters = new Set(winner.members.map((m) => m.agent));
  const meanConfidence = winner.members.reduce((s, m) => s + m.confidence, 0) / winner.members.length;

  // A single candidate or a single agreeing cluster is accepted outright.
  // Only a real cluster split -- >=2 materially different canonical values,
  // each carrying actual weight -- becomes a review item, and even then the
  // top-weighted pick below is still applied so the app always shows a
  // value; review just lets a human correct the minority case. A zero-weight
  // cluster (e.g. P3/rules voting on a prose field it's excluded from) isn't
  // a real disagreement, so it doesn't count toward "genuine split".
  const significantClusters = clusters.filter((cl) => cl.totalWeight > 0);
  let decision = significantClusters.length > 1 ? 'split' : 'accepted';
  let reviewReason = decision === 'split' ? 'split' : null;

  // Prose is selected, not voted (PLAN.md §2 point 6): a wide boundary spread
  // in the winning cluster means real disagreement even if the sliced text
  // happens to match closely enough to cluster.
  if (isProseField(field) && winner.members.length > 1) {
    const starts = winner.members.map((m) => m.canonical.start);
    const ends = winner.members.map((m) => m.canonical.end);
    const spread = Math.max(...ends) - Math.min(...starts);
    if (spread > (ctx.proseSpreadReviewChars ?? 80)) {
      decision = 'split';
      reviewReason = 'prose_spread';
    }
  }

  // Prose "value" is the median boundary across the winning cluster, not any
  // single voter's offsets -- lossless and non-hallucinatable per PLAN.md §2.
  const chosenCanonical = isProseField(field) ? medianProse(winner.members) : winner.members[0].canonical;

  return {
    field,
    value: denormalize(field, chosenCanonical),
    confidence: round3(meanConfidence),
    agreement: round3(share),
    voters: [...winnerVoters],
    decision,
    reviewReason,
  };
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

function medianProse(members) {
  const start = Math.round(median(members.map((m) => m.canonical.start)));
  const end = Math.round(median(members.map((m) => m.canonical.end)));
  // All members were clustered as "close enough"; reuse the first member's
  // sliced text if the median boundary lands exactly on it (the common case),
  // otherwise fall back to the longest candidate rather than re-slicing
  // without the raw source text in scope here.
  const exact = members.find((m) => m.canonical.start === start && m.canonical.end === end);
  if (exact) return exact.canonical;
  return members.reduce((a, b) => (b.canonical.text.length > a.canonical.text.length ? b : a)).canonical;
}

// ---- Whole-record adjudication ----
//
// candidatesByField: { [field]: [{ agent, value, confidence, evidence }] }
// ctx.locked: Set<field> of fields with a sticky human decision -- skipped
// entirely, per PLAN.md §1's single most important invariant.
export function adjudicateRecord(candidatesByField, ctx = {}) {
  const resolutions = {};
  const reviews = [];

  for (const [field, candidates] of Object.entries(candidatesByField ?? {})) {
    if (ctx.locked?.has(field)) continue;
    const result = adjudicateField(field, candidates, ctx);
    resolutions[field] = result;
    if (result.decision === 'split') {
      reviews.push({ field, reason: result.reviewReason, candidates });
    }
  }

  return { resolutions, reviews };
}
