// "You already own this one" — matching a browsed shop page against the
// library, and working out what the page could ADD to the stored record (#161).
//
// Radu, 2026-09-09: "when im visiting a page with a coffee IN my coffees the
// extension identifies and presents enriching opportunities (if any new
// information is found)."
//
// Two rules shape everything here:
//
//  1. **A false "you own this" is the worst outcome.** It tells him he has a
//     bag he doesn't, and invites him to write page data onto the wrong
//     record. So matching is deliberately conservative: the roaster must match
//     exactly (a hard SQL filter), and beyond that at least one DISTINCTIVE
//     word must be shared. Origin and process agreeing is not enough on its
//     own — "Gardelli Ethiopia Washed" describes plenty of different bags.
//
//  2. **Fill blanks only, never overwrite.** The diff returns a field only
//     when the page has a value and the record has none. Anything already
//     stored is left alone, and the accept path goes through #40's edit
//     endpoint, which refuses to touch human-locked fields anyway.
//
// Matching runs in JS, not SQL: a roaster has a handful of coffees (414 over
// ~90 roasters), so the candidate set is tiny, and keeping it here makes the
// whole decision unit-testable without a database.
import { query } from '../db.js';
import { foldDiacritics } from './normalize.js';

// Words that appear in coffee titles everywhere and so carry no identifying
// information. Romanian included — Radu's own titles are written in it
// ("Cafea Gardelli Sopacdi (Congo) MAI 2018 aeropress").
const STOPWORDS = new Set([
  // structural / commerce
  'coffee', 'coffees', 'cafea', 'cafe', 'beans', 'bean', 'roasters', 'roastery', 'roasted',
  'specialty', 'speciality', 'the', 'and', 'with', 'from', 'for', 'this', 'that',
  'whole', 'ground', 'filter', 'espresso', 'omni', 'blend', 'single', 'origin',
  'bag', 'bags', 'pack', 'gram', 'grams', 'kilo', 'sold', 'out', 'stock', 'new',
  'aeropress', 'chemex', 'v60', 'moka', 'french', 'press', 'brew',
  // processes — real signal, but matched separately; as tokens they are far
  // too common to identify a specific bag
  'washed', 'natural', 'honey', 'anaerobic', 'fermented', 'cofermented', 'experimental',
  'spalat', 'naturala', 'decaf', 'decofeinizat',
  // months, English + Romanian
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec',
  'ian', 'mai', 'iun', 'iul', 'noi',
]);

const MIN_TOKEN_LEN = 4;

export function titleTokens(title) {
  return foldDiacritics(String(title ?? '').toLowerCase())
    .replace(/[^a-z0-9]+/g, ' ')
    .split(' ')
    .filter(Boolean);
}

// The words that could actually identify one bag rather than a category: long
// enough to matter, not a stopword, not a bare number (a year or a weight),
// and not part of the roaster's own name — every candidate shares that, so it
// would make every comparison look like a match.
export function distinctiveTokens(title, { roasterName, genericTokens } = {}) {
  const roasterTokens = new Set(titleTokens(roasterName ?? ''));
  const out = new Set();
  for (const t of titleTokens(title)) {
    if (t.length < MIN_TOKEN_LEN) continue;
    if (STOPWORDS.has(t)) continue;
    if (roasterTokens.has(t)) continue;
    if (genericTokens?.has(t)) continue;
    if (/^\d+$/.test(t)) continue;
    out.add(t);
  }
  return out;
}

// Country names are categories, not identities. "Gardelli Ethiopia Washed"
// describes plenty of different bags, so letting "ethiopia" carry a match
// would fire on any two Ethiopians from the same roaster. Built from the live
// country vocab rather than a hardcoded list so it tracks the seed (including
// the Congo aliases #165 added) automatically.
export function genericTokensFromVocab(countryVocab) {
  const out = new Set();
  for (const c of countryVocab?.candidates ?? []) {
    for (const t of titleTokens(c.name)) if (t.length >= MIN_TOKEN_LEN) out.add(t);
  }
  for (const aliasNorm of countryVocab?.aliasIndex?.keys() ?? []) {
    for (const t of titleTokens(aliasNorm)) if (t.length >= MIN_TOKEN_LEN) out.add(t);
  }
  return out;
}

function overlapOf(a, b) {
  const shared = [];
  for (const t of a) if (b.has(t)) shared.push(t);
  return shared;
}

/**
 * Rank a roaster's coffees against the browsed page.
 *
 * `candidates` are rows from `loadRoasterCoffees`. Returns them scored and
 * sorted, best first, each with the words that actually drove the match so the
 * UI (and a human reading a bug report) can see WHY it matched.
 *
 * `confidence`:
 *   'strong'   — a distinctive word is shared and origin does not contradict
 *   'possible' — a distinctive word is shared but origin disagrees
 * Anything with no shared distinctive word is dropped entirely rather than
 * returned with a low score: see rule 1 above.
 */
export function rankMatches(page, candidates, { roasterName, genericTokens } = {}) {
  const opts = { roasterName, genericTokens };
  const pageTokens = distinctiveTokens(page.title, opts);
  if (pageTokens.size === 0) return [];

  const ranked = [];
  for (const c of candidates) {
    const shared = overlapOf(pageTokens, distinctiveTokens(c.rawTitle, opts));
    if (shared.length === 0) continue;

    // Origin is a check, never the reason for a match. A page origin that
    // disagrees with the stored one is a real warning sign — same roaster,
    // similar name, different country is usually a different lot.
    const pageOrigin = page.originCountryId ?? null;
    const rowOrigins = c.originCountryIds ?? [];
    const originKnown = pageOrigin != null && rowOrigins.length > 0;
    const originAgrees = originKnown ? rowOrigins.includes(pageOrigin) : null;

    ranked.push({
      ...c,
      sharedTokens: shared,
      // Longer shared words are stronger evidence than short ones; two shared
      // words are stronger than one.
      score: shared.reduce((sum, t) => sum + t.length, 0) + (originAgrees ? 5 : 0),
      originAgrees,
      confidence: originAgrees === false ? 'possible' : 'strong',
    });
  }

  return ranked.sort((a, b) => b.score - a.score || String(b.purchasedOn ?? '').localeCompare(String(a.purchasedOn ?? '')));
}

// Every field the extension can offer to fill, in the order the popup shows
// them. `field` is the CLIENT field name #40's edit endpoint accepts, and
// `format` produces a string that endpoint's own parser will re-read — the
// accept path deliberately re-parses rather than trusting a number we send,
// so a value can never enter the DB by a route the edit sheet couldn't.
const ENRICHABLE = [
  {
    field: 'originCountry',
    label: 'Origin',
    isEmpty: (row) => (row.originCountryIds ?? []).length === 0,
    from: (p) => (p.originCountryName ? { value: p.originCountryName, display: p.originCountryName } : null),
  },
  {
    field: 'farm',
    label: 'Farm',
    isEmpty: (row) => row.originFarmId == null,
    from: (p) => (p.farmName ? { value: p.farmName, display: p.farmName } : null),
  },
  {
    field: 'profile',
    label: 'Process',
    isEmpty: (row) => row.profileId == null,
    from: (p) => (p.profileName ? { value: p.profileName, display: p.profileName } : null),
  },
  {
    field: 'roastedOn',
    label: 'Roast date',
    isEmpty: (row) => row.roastedOn == null,
    from: (p) => (p.roastedOn ? { value: p.roastedOn, display: p.roastedOn } : null),
  },
  {
    field: 'weight',
    label: 'Weight',
    isEmpty: (row) => row.weightG == null,
    from: (p) => (p.weightG > 0 ? { value: `${p.weightG} g`, display: `${p.weightG} g` } : null),
  },
  {
    field: 'price',
    label: 'Price',
    isEmpty: (row) => row.priceOriginalAmount == null,
    // A currency marker is required: `parsePrice` returns null without one, so
    // sending a bare number would 422 at accept time.
    from: (p) =>
      p.priceAmount != null && p.priceCurrency
        ? { value: `${p.priceAmount} ${p.priceCurrency}`, display: `${p.priceAmount} ${p.priceCurrency}` }
        : null,
  },
  {
    field: 'altitude',
    label: 'Altitude',
    isEmpty: (row) => row.altitudeMinM == null && row.altitudeMaxM == null,
    from: (p) => {
      if (p.altitudeMin == null && p.altitudeMax == null) return null;
      const lo = p.altitudeMin ?? p.altitudeMax;
      const hi = p.altitudeMax ?? p.altitudeMin;
      const text = lo === hi ? `${lo} masl` : `${lo}-${hi} masl`;
      return { value: text, display: text };
    },
  },
];

/**
 * What this page could add to the stored record: fields the page HAS and the
 * record LACKS. Never returns a field the record already holds — the extension
 * is an enricher, not an editor, and overwriting is not on offer.
 *
 * Returns [] when the page adds nothing, which the UI must render as silence
 * rather than an empty panel (Radu: "if any new information is found").
 */
export function diffFields(pageFields, row) {
  const out = [];
  for (const spec of ENRICHABLE) {
    if (!spec.isEmpty(row)) continue;
    const found = spec.from(pageFields);
    if (!found) continue;
    out.push({ field: spec.field, label: spec.label, value: found.value, display: found.display });
  }
  return out;
}

// Candidate set for matching: everything by this roaster. Small by
// construction — 414 coffees over ~90 roasters — so no index gymnastics.
export async function loadRoasterCoffees(roasterId) {
  if (roasterId == null) return [];
  const { rows } = await query(
    `SELECT public_id           AS "id",
            raw_title           AS "rawTitle",
            purchased_on        AS "purchasedOn",
            rating::float       AS "rating",
            origin_country_ids  AS "originCountryIds",
            origin_farm_id      AS "originFarmId",
            profile_id          AS "profileId",
            roasted_on          AS "roastedOn",
            weight_g            AS "weightG",
            altitude_min_m      AS "altitudeMinM",
            altitude_max_m      AS "altitudeMaxM",
            price_original_amount   AS "priceOriginalAmount",
            price_original_currency AS "priceOriginalCurrency",
            is_favorite         AS "isFavorite"
       FROM coffees
      WHERE roaster_id = $1 AND deleted_at IS NULL`,
    [roasterId],
  );
  return rows.map((r) => ({
    ...r,
    purchasedOn: r.purchasedOn instanceof Date ? r.purchasedOn.toISOString().slice(0, 10) : r.purchasedOn,
    roastedOn: r.roastedOn instanceof Date ? r.roastedOn.toISOString().slice(0, 10) : r.roastedOn,
    priceOriginalAmount: r.priceOriginalAmount == null ? null : Number(r.priceOriginalAmount),
  }));
}
