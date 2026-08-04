// P3 — the "rules" voter (PLAN.md §2): pure JS, no network, "better than any
// LLM here" on numbers/units/currency/vocab exact-alias. This is the Phase 0
// pass (#25) that runs over the whole corpus for $0, before any LLM spend, so
// its scope is deliberately conservative: propose a field only when a
// deterministic signal actually fired. A voter that guesses on every photo
// would spam `review_items` with "no_candidates" rows for the (common) case
// where a field simply isn't mentioned.
//
// Contract (agents.js's `loadRulesVoter()`): { agent: 'rules', provider:
// 'rules', run(ctx) => Promise<{ fields, usage, costUsd }> }. `ctx.rawText`
// is the only input this voter needs — no image, no vocabulary shortlist.
//
// Two different strategies, matching how adjudicate.js's `canonicalize()`
// re-derives a value from whatever raw string a voter proposes:
//   - altitude/price/weight/rating/profile: `normalize.js`'s parsers already
//     scan arbitrary free text for their own markers, and canonicalize() re-
//     runs the exact same parser on this voter's raw value. So this module
//     only needs to decide whether the field is present at all (by calling
//     the parser once itself) and, if so, hand the raw text straight through.
//   - roaster_id/origin_country_ids/origin_farm_id: canonicalize() resolves
//     these via `resolveVocab()`, which does an EXACT alias_norm lookup on
//     the whole raw value — it does not scan a paragraph for a substring. So
//     this module has to find the matching substring itself and propose just
//     that (see `findAliasMentions`).
import { parseAltitude, parsePrice, parseWeight, parseRating, parseProfile, parseFarm, foldDiacritics, normalizeVocabString } from './normalize.js';
import { loadRoasterVocab, loadCountryVocab } from './vocab.js';
import { query } from '../db.js';

export const PROMPT_VERSION = 'rules-v1';

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// One mention per distinct id, keeping the longest (most specific) alias a
// given id matched under — e.g. "Father's Coffee Roastery" beats a shorter
// alias of the same roaster if both happen to appear.
export function findAliasMentions(text, aliasIndex) {
  const haystack = foldDiacritics(normalizeVocabString(text));
  if (!haystack || !aliasIndex) return [];

  const byId = new Map();
  for (const [aliasNorm, row] of aliasIndex.entries()) {
    const needle = foldDiacritics(aliasNorm);
    if (!needle) continue;
    const re = new RegExp(`\\b${escapeRegExp(needle)}\\b`, 'i');
    if (!re.test(haystack)) continue;
    const existing = byId.get(row.id);
    if (!existing || needle.length > existing.aliasNorm.length) {
      byId.set(row.id, { id: row.id, alias: row.alias, aliasNorm: needle });
    }
  }
  return [...byId.values()].sort((a, b) => b.aliasNorm.length - a.aliasNorm.length);
}

// A single-valued field (roaster, farm): only propose when there's a unique
// longest match — a tie between two *different* entities is exactly the
// ambiguity PLAN.md §2 says must go to review, not get guessed.
function uniqueTopMention(mentions) {
  if (mentions.length === 0) return null;
  const topLen = mentions[0].aliasNorm.length;
  const top = mentions.filter((m) => m.aliasNorm.length === topLen);
  return top.length === 1 ? top[0] : null;
}

export function extractRoasterField(rawText, roasterVocab) {
  const top = uniqueTopMention(findAliasMentions(rawText, roasterVocab?.aliasIndex));
  if (!top) return null;
  return { value: top.alias, confidence: 1.0, evidence: top.alias };
}

// Origin isn't single-valued (PLAN.md §1) — every distinct *origin* country
// mentioned is proposed, joined the same way a human caption would
// ("Colombia / Brazil"), so `resolveOriginCountries` downstream splits it
// back apart per-part exactly as it would a human-written multi-origin string.
export function extractOriginCountriesField(rawText, countryVocab) {
  const originIds = new Set((countryVocab?.candidates ?? []).filter((c) => c.is_origin).map((c) => c.id));
  const mentions = findAliasMentions(rawText, countryVocab?.aliasIndex).filter((m) => originIds.has(m.id));
  if (mentions.length === 0) return null;
  const names = mentions.map((m) => m.alias);
  return { value: names.join(' / '), confidence: 1.0, evidence: names.join(', ') };
}

// Farms start with no seeded vocabulary at all (PLAN.md §1: "derived from the
// data and approved in the review queue") — so unlike roaster/country, this
// never resolves via alias matching. It surfaces a *candidate new farm name*
// whenever the text carries one of `parseFarm`'s recognised prefixes
// ("Finca …", "Producer: …", …), so Phase 0 also seeds the farm review queue,
// not just roaster/country. Gated on a real prefix hit, not just any residual
// text, so a caption with no farm/producer mention proposes nothing.
const FARM_LINE_KEYWORDS_RE = /\b(finca|fazenda|producer|washing station)\b/i;

export function extractFarmField(rawText) {
  if (!rawText) return null;
  const lines = String(rawText).split(/[\n.]+/).map((l) => l.trim()).filter(Boolean);
  for (const line of lines) {
    if (!FARM_LINE_KEYWORDS_RE.test(line)) continue;
    const parsed = parseFarm(line);
    if (parsed?.kind && parsed.name) {
      return { value: parsed.name, confidence: 1.0, evidence: line };
    }
  }
  return null;
}

// Roasted-on is the lowest-priority field in the whole pipeline (brief: "not
// very relevant", threshold 0.70) and the riskiest one for rules to guess —
// a caption can carry more than one date. Only propose when a date sits near
// an explicit roast keyword, so a purchase date never gets mistaken for one.
const DATE_RE = /\b((?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-]\d{2,4}|\d{4}-\d{2}-\d{2})\b/;
const ROAST_KEYWORD_RE = /\b(roast(?:ed)?|prajit|praj)\b/i;
const ROAST_KEYWORD_WINDOW = 25;

export function extractRoastedOnField(rawText) {
  if (!rawText) return null;
  const s = String(rawText);
  const m = s.match(DATE_RE);
  if (!m) return null;
  const before = s.slice(Math.max(0, m.index - ROAST_KEYWORD_WINDOW), m.index);
  if (!ROAST_KEYWORD_RE.test(before)) return null;
  return { value: m[1], confidence: 1.0, evidence: m[0] };
}

function passthroughField(parseFn, rawText) {
  if (!rawText || !parseFn(rawText)) return null;
  return { value: rawText, confidence: 1.0 };
}

// `parsePrice`/`parseRating` both have a low-confidence *bare-number*
// fallback branch ("never silent" — PLAN.md §2) meant for a narrowly-scoped
// value a caller already believes is a price/rating. Rules scans the WHOLE
// caption, where that fallback is dangerous: the first bare digit sequence
// in free text is as likely to be a date or an altitude as an actual price
// or rating. Require the field's own explicit marker (a currency symbol/code,
// or "/5"/"⭐") before proposing at all — canonicalize() re-runs the real
// parser afterwards and takes the same marked (non-bare) branch, so this only
// gates *whether* to propose, never how the value is read.
const PRICE_MARKER_RE = /(?:\d[\d.,]*\s*(?:€|eur\b|lei\b|kč|kc\b|zł|zl\b|ft\b|huf\b|usd\b|gbp\b|chf\b)|[€$£]\s*\d[\d.,]*)/i;
const RATING_MARKER_RE = /(?:\d[.,]?\d?\s*\/\s*5\b|⭐️?\s*\d[.,]?\d?)/u;

function markerGatedField(rawText, markerRe, parseFn) {
  if (!rawText || !markerRe.test(rawText) || !parseFn(rawText)) return null;
  return { value: rawText, confidence: 1.0 };
}

export function extractProfileField(rawText) {
  if (!rawText) return null;
  const parsed = parseProfile(rawText);
  if (parsed.profileId == null && !parsed.isDecaf) return null;
  return { value: rawText, confidence: 1.0, evidence: parsed.detail ?? undefined };
}

// The core, pure logic — no DB, no network, fully unit-testable with fixture
// vocab dictionaries. `rulesVoter.run()` below is the thin DB-loading wrapper
// around this.
export function extractRuleFields(rawText, { roasterVocab, countryVocab } = {}) {
  const fields = {};
  const set = (field, candidate) => {
    if (candidate) fields[field] = candidate;
  };

  set('roaster_id', extractRoasterField(rawText, roasterVocab));
  set('origin_country_ids', extractOriginCountriesField(rawText, countryVocab));
  set('origin_farm_id', extractFarmField(rawText));
  set('altitude', passthroughField(parseAltitude, rawText));
  set('price', markerGatedField(rawText, PRICE_MARKER_RE, parsePrice));
  set('weight_g', passthroughField(parseWeight, rawText));
  set('rating', markerGatedField(rawText, RATING_MARKER_RE, parseRating));
  set('roasted_on', extractRoastedOnField(rawText));
  set('profile', extractProfileField(rawText));

  return fields;
}

// ---- DB-loading wrapper (the actual voter object agents.js picks up) ----
//
// Vocab is loaded once per process and reused for every `run()` call — the
// same tradeoff `agents.js`'s module-level `_rulesVoterPromise` cache already
// makes for the voter object itself. A newly-confirmed alias (`POST
// /api/review/rules`) is picked up on the next deploy/restart, not mid-run;
// acceptable for a Phase 0 pass that runs once over the corpus before any
// vocab-version bump.
let _vocabPromise;
async function loadVocab() {
  if (!_vocabPromise) {
    _vocabPromise = Promise.all([loadRoasterVocab(query), loadCountryVocab(query)]).then(
      ([roasterVocab, countryVocab]) => ({ roasterVocab, countryVocab }),
    );
  }
  return _vocabPromise;
}

export const rulesVoter = {
  agent: 'rules',
  provider: 'rules',
  model: null,
  promptVersion: PROMPT_VERSION,
  async run({ rawText } = {}) {
    const vocab = await loadVocab();
    return {
      agent: 'rules',
      provider: 'rules',
      model: null,
      promptVersion: PROMPT_VERSION,
      fields: extractRuleFields(rawText, vocab),
      usage: null,
      costUsd: 0,
    };
  },
};
