// Controlled-vocabulary resolution against the 004_vocab.sql tables.
// `src/lib/fuzzy.js` owns *matching* (scoring candidates against an input
// string); this module owns *resolution* — turning a raw extracted string
// into a canonical DB id — plus the array referential-integrity check that
// `origin_country_ids` needs, since Postgres can't FK-constrain array
// elements (PLAN.md §1: "enforce in src/lib/vocab.js").
//
// DB access is kept to thin loaders that shape query results into
// `{ candidates, aliasIndex }`; every resolution function below is pure and
// takes that shape as input, so it's testable without a live Postgres —
// same split as `fx.js` (query elsewhere, math/logic here).

import { normalizeVocabString, resolveCityCountry } from './normalize.js';
import { matchVocab } from './fuzzy.js';

const MULTI_VALUE_SPLIT_RE = /\s*(?:\/|,|&|\band\b)\s*/i;

// ---- Index building (pure) ----

// `aliasRows` is `[{ id, alias, alias_norm }]` — loaders below normalize each
// kind's differently-named FK column (`country_id`, `roaster_id`, ...) to `id`
// so this stays kind-agnostic.
export function buildAliasIndex(aliasRows) {
  const index = new Map();
  for (const row of aliasRows ?? []) {
    index.set(row.alias_norm, row);
  }
  return index;
}

// ---- Resolution (pure) ----

// Exact alias_norm lookup first (deterministic, free); fuzzy fallback only
// when no exact alias exists, gated by matchVocab's three-part guard
// ("guess only very close matches" — PLAN.md §2).
export function resolveVocab(input, { aliasIndex, candidates } = {}, fuzzyOpts) {
  const norm = normalizeVocabString(input);
  if (!norm) return { resolved: false, method: 'none', reason: 'empty input' };

  const exact = aliasIndex?.get(norm);
  if (exact) {
    return { resolved: true, id: exact.id, method: 'exact', confidence: 1.0, matchedAlias: exact.alias };
  }

  const match = matchVocab(input, candidates ?? [], fuzzyOpts);
  if (match.accepted) {
    const id = typeof match.match === 'string' ? undefined : match.match.id;
    return { resolved: true, id, method: 'fuzzy', confidence: match.confidence, matchedName: match.match.name ?? match.match };
  }
  return { resolved: false, method: 'none', reason: match.reason, best: match.best };
}

// Splits a multi-value origin string ("Colombia / Brazilia", "Kenya, Ethiopia")
// into parts and resolves each independently — origin isn't single-valued
// (PLAN.md §1). Unresolved parts are reported separately rather than dropped
// silently, so a partial miss surfaces as a review item instead of a
// half-populated array.
export function resolveOriginCountries(text, vocab, fuzzyOpts) {
  const raw = String(text ?? '').trim();
  if (!raw) return { ids: [], unresolved: [], isBlend: false };

  const parts = raw.split(MULTI_VALUE_SPLIT_RE).map((p) => p.trim()).filter(Boolean);
  const ids = [];
  const unresolved = [];
  for (const part of parts) {
    const result = resolveVocab(part, vocab, fuzzyOpts);
    if (result.resolved && result.id != null) ids.push(result.id);
    else unresolved.push(part);
  }

  return { ids, unresolved, isBlend: computeIsBlend(ids, vocab?.candidates) };
}

// True when the resolved origin is multi-valued, OR resolves to the `Blend`
// pseudo-country (kind='pseudo', 004_vocab.sql) even as a single id — a bag
// literally labelled "Blend" is a blend regardless of array length.
export function computeIsBlend(originCountryIds, countryCandidates) {
  const ids = Array.isArray(originCountryIds) ? originCountryIds : [];
  if (ids.length > 1) return true;
  const byId = new Map((countryCandidates ?? []).map((c) => [c.id, c]));
  return ids.some((id) => byId.get(id)?.kind === 'pseudo');
}

// Enforces the referential integrity Postgres can't: every id in
// `origin_country_ids` must reference a real, `is_origin` country row. Splits
// the input into `valid`/`invalid` rather than throwing, so a bad id becomes
// a review item, not a crash.
export function validateOriginCountryIds(ids, countryCandidates) {
  const originIds = new Set(
    (countryCandidates ?? []).filter((c) => c.is_origin).map((c) => c.id),
  );
  const valid = [];
  const invalid = [];
  for (const id of Array.isArray(ids) ? ids : []) {
    if (originIds.has(id)) valid.push(id);
    else invalid.push(id);
  }
  return { valid, invalid };
}

// ---- City -> country (ambiguous cities never auto-resolve) ----

// Merges `cities` primary names and `city_aliases` into one normalized-name
// map, then delegates the actual lookup to normalize.js's pure
// `resolveCityCountry` so the "ambiguous never wins" rule lives in one place.
export function buildCityMap(cityRows, cityAliasRows) {
  const map = new Map();
  for (const row of cityRows ?? []) {
    map.set(normalizeVocabString(row.name), {
      countryId: row.country_id,
      countryName: row.country_name,
      ambiguous: row.ambiguous,
    });
  }
  for (const row of cityAliasRows ?? []) {
    map.set(row.alias_norm, {
      countryId: row.country_id,
      countryName: row.country_name,
      ambiguous: row.ambiguous,
    });
  }
  return map;
}

export function resolveCity(cityName, cityMap) {
  return resolveCityCountry(cityName, cityMap);
}

// ---- DB loaders (thin — shape query results, no logic) ----
// `queryFn` is anything with pg's `(text, params?) => Promise<{ rows }>`
// shape (e.g. `db.query` or a pool client), kept as a parameter so callers
// choose the connection and tests can pass a fake.

export async function loadCountryVocab(queryFn) {
  const [{ rows: candidates }, { rows: aliasRows }] = await Promise.all([
    queryFn('SELECT id, name, iso2, is_origin, is_roaster, kind FROM countries'),
    queryFn('SELECT country_id AS id, alias, alias_norm FROM country_aliases'),
  ]);
  return { candidates, aliasIndex: buildAliasIndex(aliasRows) };
}

export async function loadRoasterVocab(queryFn) {
  const [{ rows: candidates }, { rows: aliasRows }] = await Promise.all([
    queryFn('SELECT id, name, slug, country_id FROM roasters'),
    queryFn('SELECT roaster_id AS id, alias, alias_norm FROM roaster_aliases'),
  ]);
  return { candidates, aliasIndex: buildAliasIndex(aliasRows) };
}

export async function loadFarmVocab(queryFn) {
  const [{ rows: candidates }, { rows: aliasRows }] = await Promise.all([
    queryFn('SELECT id, name, kind, country_id FROM farms'),
    queryFn('SELECT farm_id AS id, alias, alias_norm FROM farm_aliases'),
  ]);
  return { candidates, aliasIndex: buildAliasIndex(aliasRows) };
}

export async function loadCityVocab(queryFn) {
  const [{ rows: cityRows }, { rows: cityAliasRows }] = await Promise.all([
    queryFn(
      `SELECT c.id, c.name, c.ambiguous, c.country_id, co.name AS country_name
       FROM cities c JOIN countries co ON co.id = c.country_id`,
    ),
    queryFn(
      `SELECT ca.alias_norm, c.ambiguous, c.country_id, co.name AS country_name
       FROM city_aliases ca
       JOIN cities c ON c.id = ca.city_id
       JOIN countries co ON co.id = c.country_id`,
    ),
  ]);
  return buildCityMap(cityRows, cityAliasRows);
}
