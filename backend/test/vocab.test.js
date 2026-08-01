// Table-driven coverage for backend/src/lib/vocab.js — resolution against the
// 004_vocab.sql tables. The DB loaders take a `queryFn` param precisely so
// these tests never need a live Postgres (same split as fx.js/fx.test.js):
// pass a fake `queryFn` that returns canned rows and assert on the shape.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildAliasIndex,
  resolveVocab,
  resolveOriginCountries,
  computeIsBlend,
  validateOriginCountryIds,
  buildCityMap,
  resolveCity,
  loadCountryVocab,
  loadRoasterVocab,
  loadFarmVocab,
  loadCityVocab,
} from '../src/lib/vocab.js';

// ---- buildAliasIndex ----

test('buildAliasIndex keys by alias_norm', () => {
  const index = buildAliasIndex([
    { id: 1, alias: 'Columbia', alias_norm: 'columbia' },
    { id: 2, alias: 'DAK', alias_norm: 'dak' },
  ]);
  assert.equal(index.get('columbia').id, 1);
  assert.equal(index.get('dak').id, 2);
  assert.equal(index.size, 2);
});

test('buildAliasIndex handles empty/missing input', () => {
  assert.equal(buildAliasIndex([]).size, 0);
  assert.equal(buildAliasIndex(undefined).size, 0);
});

// ---- resolveVocab ----

const COUNTRY_CANDIDATES = [
  { id: 1, name: 'Colombia', is_origin: true, kind: 'country' },
  { id: 2, name: 'Ethiopia', is_origin: true, kind: 'country' },
  { id: 3, name: 'Brazil', is_origin: true, kind: 'country' },
  { id: 99, name: 'Blend', is_origin: true, kind: 'pseudo' },
];
const COUNTRY_ALIASES = buildAliasIndex([
  { id: 1, alias: 'Columbia', alias_norm: 'columbia' },
]);
const COUNTRY_VOCAB = { candidates: COUNTRY_CANDIDATES, aliasIndex: COUNTRY_ALIASES };

test('resolveVocab: exact alias_norm hit short-circuits fuzzy matching', () => {
  const result = resolveVocab('Columbia', COUNTRY_VOCAB);
  assert.equal(result.resolved, true);
  assert.equal(result.method, 'exact');
  assert.equal(result.id, 1);
  assert.equal(result.confidence, 1.0);
});

test('resolveVocab: falls back to fuzzy match against candidates when no exact alias exists', () => {
  const result = resolveVocab('Etiopia', COUNTRY_VOCAB);
  assert.equal(result.resolved, true);
  assert.equal(result.method, 'fuzzy');
  assert.equal(result.id, 2);
});

test('resolveVocab: empty input never resolves', () => {
  const result = resolveVocab('', COUNTRY_VOCAB);
  assert.equal(result.resolved, false);
  assert.equal(result.reason, 'empty input');
});

test('resolveVocab: no matching candidate refuses cleanly', () => {
  const result = resolveVocab('Narnia', COUNTRY_VOCAB);
  assert.equal(result.resolved, false);
  assert.equal(result.method, 'none');
});

// ---- Mandatory negative fuzzy cases, at the resolveVocab level ----

const ROASTER_VOCAB = {
  candidates: [
    { id: 1, name: 'Kolibri' },
    { id: 2, name: 'Kaffa' },
    { id: 3, name: 'Father Carpenter' },
  ],
  aliasIndex: buildAliasIndex([]),
};

test('resolveVocab: Kofio must NOT resolve to Kolibri', () => {
  const result = resolveVocab('Kofio', ROASTER_VOCAB);
  assert.equal(result.resolved, false);
});

test('resolveVocab: "Father\'s Coffee Roastery" must NOT resolve to Father Carpenter', () => {
  const result = resolveVocab("Father's Coffee Roastery", ROASTER_VOCAB);
  assert.equal(result.resolved, false);
});

// ---- resolveOriginCountries ----

test('resolveOriginCountries: splits a slash-separated multi-origin string', () => {
  const result = resolveOriginCountries('Colombia / Brazil', COUNTRY_VOCAB);
  assert.deepEqual(result.ids.sort(), [1, 3]);
  assert.deepEqual(result.unresolved, []);
  assert.equal(result.isBlend, true);
});

test('resolveOriginCountries: splits on comma too', () => {
  const result = resolveOriginCountries('Ethiopia, Brazil', COUNTRY_VOCAB);
  assert.deepEqual(result.ids.sort(), [2, 3]);
});

test('resolveOriginCountries: a single resolvable origin is not a blend', () => {
  const result = resolveOriginCountries('Ethiopia', COUNTRY_VOCAB);
  assert.deepEqual(result.ids, [2]);
  assert.equal(result.isBlend, false);
});

test('resolveOriginCountries: literal "Blend" is a blend even as a single id', () => {
  const result = resolveOriginCountries('Blend', COUNTRY_VOCAB);
  assert.deepEqual(result.ids, [99]);
  assert.equal(result.isBlend, true);
});

test('resolveOriginCountries: unresolved parts are reported, not silently dropped', () => {
  const result = resolveOriginCountries('Colombia / Wakanda', COUNTRY_VOCAB);
  assert.deepEqual(result.ids, [1]);
  assert.deepEqual(result.unresolved, ['Wakanda']);
});

test('resolveOriginCountries: empty text resolves to nothing, cleanly', () => {
  assert.deepEqual(resolveOriginCountries('', COUNTRY_VOCAB), { ids: [], unresolved: [], isBlend: false });
  assert.deepEqual(resolveOriginCountries(null, COUNTRY_VOCAB), { ids: [], unresolved: [], isBlend: false });
});

// ---- computeIsBlend ----

test('computeIsBlend: more than one id is always a blend', () => {
  assert.equal(computeIsBlend([1, 2], COUNTRY_CANDIDATES), true);
});

test('computeIsBlend: a single non-pseudo id is not a blend', () => {
  assert.equal(computeIsBlend([1], COUNTRY_CANDIDATES), false);
});

test('computeIsBlend: a single pseudo-country id (Blend) is a blend', () => {
  assert.equal(computeIsBlend([99], COUNTRY_CANDIDATES), true);
});

test('computeIsBlend: empty/missing ids is not a blend', () => {
  assert.equal(computeIsBlend([], COUNTRY_CANDIDATES), false);
  assert.equal(computeIsBlend(undefined, COUNTRY_CANDIDATES), false);
});

// ---- validateOriginCountryIds ----

test('validateOriginCountryIds: splits valid is_origin ids from everything else', () => {
  const candidates = [
    { id: 1, is_origin: true },
    { id: 2, is_origin: true },
    { id: 5, is_origin: false }, // a roaster-only country, e.g. Belgium
  ];
  const result = validateOriginCountryIds([1, 5, 404], candidates);
  assert.deepEqual(result.valid, [1]);
  assert.deepEqual(result.invalid, [5, 404]);
});

test('validateOriginCountryIds: empty/non-array input is handled', () => {
  assert.deepEqual(validateOriginCountryIds(null, []), { valid: [], invalid: [] });
});

// ---- City -> country ----

test('buildCityMap + resolveCity: an unambiguous city resolves to its country', () => {
  const cityMap = buildCityMap(
    [{ name: 'Amsterdam', country_id: 10, country_name: 'Netherlands', ambiguous: false }],
    [],
  );
  assert.equal(resolveCity('Amsterdam', cityMap), 'Netherlands');
});

test('buildCityMap + resolveCity: an ambiguous city never auto-resolves', () => {
  const cityMap = buildCityMap(
    [{ name: 'Cambridge', country_id: 20, country_name: 'United Kingdom', ambiguous: true }],
    [],
  );
  assert.equal(resolveCity('Cambridge', cityMap), null);
});

test('buildCityMap + resolveCity: a city alias resolves the same as the primary name', () => {
  const cityMap = buildCityMap(
    [],
    [{ alias_norm: 'ams', country_id: 10, country_name: 'Netherlands', ambiguous: false }],
  );
  assert.equal(resolveCity('ams', cityMap), 'Netherlands');
});

// ---- DB loaders (fake queryFn — no live Postgres) ----

function fakeQuery(responses) {
  let call = 0;
  return async () => responses[call++];
}

test('loadCountryVocab shapes two queries into { candidates, aliasIndex }', async () => {
  const queryFn = fakeQuery([
    { rows: [{ id: 1, name: 'Colombia', iso2: 'CO', is_origin: true, is_roaster: false, kind: 'country' }] },
    { rows: [{ id: 1, alias: 'Columbia', alias_norm: 'columbia' }] },
  ]);
  const vocab = await loadCountryVocab(queryFn);
  assert.equal(vocab.candidates.length, 1);
  assert.equal(vocab.aliasIndex.get('columbia').id, 1);
});

test('loadRoasterVocab shapes two queries into { candidates, aliasIndex }', async () => {
  const queryFn = fakeQuery([
    { rows: [{ id: 1, name: 'DAK Coffee Roasters', slug: 'dak-coffee-roasters', country_id: 10 }] },
    { rows: [{ id: 1, alias: 'DAK', alias_norm: 'dak' }] },
  ]);
  const vocab = await loadRoasterVocab(queryFn);
  assert.equal(vocab.candidates[0].name, 'DAK Coffee Roasters');
  assert.equal(vocab.aliasIndex.get('dak').id, 1);
});

test('loadFarmVocab shapes two queries into { candidates, aliasIndex }', async () => {
  const queryFn = fakeQuery([
    { rows: [{ id: 1, name: 'El Paraiso', kind: 'finca', country_id: 5 }] },
    { rows: [] },
  ]);
  const vocab = await loadFarmVocab(queryFn);
  assert.equal(vocab.candidates[0].name, 'El Paraiso');
  assert.equal(vocab.aliasIndex.size, 0);
});

test('loadCityVocab merges city rows and city_aliases into one normalized-name map', async () => {
  const queryFn = fakeQuery([
    { rows: [{ id: 1, name: 'Amsterdam', ambiguous: false, country_id: 10, country_name: 'Netherlands' }] },
    { rows: [{ alias_norm: 'ams', ambiguous: false, country_id: 10, country_name: 'Netherlands' }] },
  ]);
  const cityMap = await loadCityVocab(queryFn);
  assert.equal(resolveCity('Amsterdam', cityMap), 'Netherlands');
  assert.equal(resolveCity('ams', cityMap), 'Netherlands');
});
