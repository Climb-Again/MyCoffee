// Table-driven coverage for backend/src/lib/normalize.js — pure functions,
// no DB. Cases are drawn from the brief's own examples (PLAN.md §2).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeVocabString,
  foldDiacritics,
  parseNumber,
  parseAltitude,
  parsePrice,
  parseWeight,
  parseRating,
  parseDate,
  parseProfile,
  parseFarm,
  resolveCityCountry,
} from '../src/lib/normalize.js';

test('normalizeVocabString trims, collapses whitespace, lowercases', () => {
  assert.equal(normalizeVocabString('  DAK   Coffee  Roasters '), 'dak coffee roasters');
  assert.equal(normalizeVocabString(null), '');
});

test('foldDiacritics strips accents', () => {
  assert.equal(foldDiacritics('Etiopia café'), 'Etiopia cafe');
});

// ---- parseNumber: shape-by-field, never one shared parser ----

test('parseNumber: number shapes resolved by shape, and by field only when ambiguous', () => {
  const cases = [
    // [raw, field, expected]
    ['4.1', 'rating', 4.1],
    ['4,1', 'rating', 4.1],
    ['3,9', 'rating', 3.9],
    ['1.600', 'weight', 1600],
    ['1,600', 'weight', 1600],
    ['1.600,50', 'price', 1600.5],
    ['1,600.50', 'price', 1600.5],
    ['1.6', 'altitude', 1600],   // field-dependent: altitude shorthand
    ['1.6', 'rating', 1.6],      // same shape, different field, different answer
    ['1300', 'altitude', 1300],
    ['-5', undefined, -5],
    ['', undefined, null],
    [null, undefined, null],
    ['abc', undefined, null],
  ];
  for (const [raw, field, expected] of cases) {
    assert.equal(parseNumber(raw, { field }), expected, `parseNumber(${raw}, ${field})`);
  }
});

// ---- Altitude ----

test('parseAltitude: ranges, single values, the brief\'s own typo', () => {
  assert.deepEqual(
    { min: 1300, max: 1600 },
    (({ min, max }) => ({ min, max }))(parseAltitude('1300 to 1600 masl'))
  );
  assert.deepEqual(
    { min: 1300, max: 1600 },
    (({ min, max }) => ({ min, max }))(parseAltitude('1300 ro 1600')) // "ro" typo for "to"
  );
  const single = parseAltitude('1.600m');
  assert.equal(single.min, 1600);
  assert.equal(single.max, 1600);

  const plausible = parseAltitude('1400 to 1500 masl');
  assert.equal(plausible.confidence, 1.0);
  assert.equal(plausible.needsReview, false);

  const implausible = parseAltitude('50 to 80 masl');
  assert.equal(implausible.confidence, 0.5);
  assert.equal(implausible.needsReview, true);

  const wideSpan = parseAltitude('1000 to 2000 masl'); // >800m apart -> review
  assert.equal(wideSpan.needsReview, true);

  assert.equal(parseAltitude('no altitude mentioned here'), null);
  assert.equal(parseAltitude(''), null);
});

// ---- Price ----

test('parsePrice: currency detection, never-silent bare numbers', () => {
  assert.deepEqual(parsePrice('18.50 lei'), { amount: 18.5, currency: 'RON', confidence: 1.0 });
  assert.deepEqual(parsePrice('120 Kč'), { amount: 120, currency: 'CZK', confidence: 1.0 });
  assert.deepEqual(parsePrice('12.50€'), { amount: 12.5, currency: 'EUR', confidence: 1.0 });
  assert.deepEqual(parsePrice('€12.50'), { amount: 12.5, currency: 'EUR', confidence: 1.0 });

  const bare = parsePrice('just 25 no currency');
  assert.equal(bare.amount, 25);
  assert.equal(bare.currency, null);
  assert.equal(bare.confidence, 0.5); // below any acceptance threshold, but never null/silent

  assert.equal(parsePrice('no numbers here'), null);
});

// ---- Weight ----

test('parseWeight: unit-anchored, snapped to the brief\'s standard bag sizes', () => {
  assert.deepEqual(parseWeight('250g bag'), { grams: 250, confidence: 1.0 });
  assert.deepEqual(parseWeight('a 100gr sample'), { grams: 100, confidence: 1.0 });
  assert.deepEqual(parseWeight('248 grams'), { grams: 250, confidence: 1.0 }); // snaps within ±3g
  assert.equal(parseWeight('225g').confidence, 0.6); // not a standard size, lower confidence
  assert.equal(parseWeight('no weight'), null);
});

test('parseWeight: refuses to guess when an altitude marker sits right next to the number', () => {
  // "1600m250g" — the 250g candidate is glued right after a bare altitude marker.
  assert.equal(parseWeight('1600m250g'), null);
  // A genuine, unambiguous weight elsewhere in the same text still parses.
  assert.deepEqual(parseWeight('grown at 1600 masl, bag is 250g'), { grams: 250, confidence: 1.0 });
});

// ---- Rating ----

test('parseRating: explicit /5, star emoji, and bare-number confidence tiers', () => {
  assert.deepEqual(parseRating('4.1/5'), { value: 4.1, confidence: 1.0 });
  assert.deepEqual(parseRating('3,9/5'), { value: 3.9, confidence: 1.0 });
  assert.deepEqual(parseRating('⭐️4.1'), { value: 4.1, confidence: 0.9 });
  assert.deepEqual(parseRating('4.1'), { value: 4.1, confidence: 0.6 }); // bare number -> 0.6
  assert.equal(parseRating(''), null);
});

// ---- Dates ----

test('parseDate: day-first, and rejects a roast date after the photo date', () => {
  const d = parseDate('03/04/2024'); // day-first: 3 April 2024
  assert.equal(d.date.getUTCDate(), 3);
  assert.equal(d.date.getUTCMonth(), 3); // 0-indexed -> April
  assert.equal(d.rejected, false);

  const future = parseDate('01/01/2030', { photoDate: '2024-01-01' });
  assert.equal(future.rejected, true);

  const ok = parseDate('01/01/2020', { photoDate: '2024-01-01' });
  assert.equal(ok.rejected, false);

  assert.equal(parseDate('not a date'), null);
});

// ---- Roast profile + decaf (orthogonal axes) ----

test('parseProfile: maps aliases onto exactly the six profiles, never defaults to Washed', () => {
  const cases = [
    ['Lavado process', 'washed'],
    ['fully washed', 'washed'],
    ['spalat', 'washed'],
    ['Natural process', 'natural'],
    ['dry process', 'natural'],
    ['uscat', 'natural'],
    ['Anaerobic fermentation', 'anaerobic'],
    ['carbonic maceration', 'anaerobic'],
    ['CM process', 'anaerobic'],
    ['co-fermented with cacao', 'co_fermented'],
    ['cofermented', 'co_fermented'],
    ['infused with cinnamon', 'co_fermented'],
    ['yeast fermentation', 'experimental'],
    ['thermal shock', 'experimental'],
    ['lactic process', 'experimental'],
    ['double fermentation', 'experimental'],
  ];
  for (const [text, expected] of cases) {
    assert.equal(parseProfile(text).profileId, expected, `parseProfile(${text})`);
  }
});

test('parseProfile: honey variants fold into Experimental, literal term preserved', () => {
  const yellow = parseProfile('Yellow Honey process');
  assert.equal(yellow.profileId, 'experimental');
  assert.equal(yellow.detail, 'Yellow Honey');

  const black = parseProfile('Black Honey process');
  assert.equal(black.detail, 'Black Honey');

  const pulped = parseProfile('pulped natural');
  assert.equal(pulped.profileId, 'experimental');
  assert.equal(pulped.detail, 'pulped natural');

  const plain = parseProfile('Honey process');
  assert.equal(plain.detail, 'Honey');
});

test('parseProfile: decaf is orthogonal to process — a decaf can be washed', () => {
  const decafWashed = parseProfile('Decaf, fully washed');
  assert.equal(decafWashed.isDecaf, true);
  assert.equal(decafWashed.profileId, 'washed');

  const swissWater = parseProfile('Swiss Water process');
  assert.equal(swissWater.isDecaf, true);

  const notDecaf = parseProfile('Natural process');
  assert.equal(notDecaf.isDecaf, false);
});

test('parseProfile: no match -> null, never a default guess', () => {
  const result = parseProfile('just a nice cup of coffee');
  assert.equal(result.profileId, null);
  assert.equal(result.isDecaf, false);
});

// ---- Farm / producer ----

test('parseFarm: "Producer: X" and "Finca Y — X" resolve to the same residual name', () => {
  assert.equal(parseFarm('Producer: Diego Bermudez').name, 'Diego Bermudez');
  assert.equal(parseFarm('Finca El Paraiso — Diego Bermudez').name, 'Diego Bermudez');
  assert.equal(parseFarm('Finca El Paraiso — Diego Bermudez').kind, 'finca');
  assert.equal(parseFarm('Fazenda Santa Ines').kind, 'fazenda');
  assert.equal(parseFarm(null), null);
});

// ---- City -> country ----

test('resolveCityCountry: resolves an unambiguous city, refuses an ambiguous one', () => {
  const cities = new Map([
    ['amsterdam', { countryName: 'Netherlands', ambiguous: false }],
    ['cambridge', { countryName: 'United Kingdom', ambiguous: true }],
  ]);
  assert.equal(resolveCityCountry('Amsterdam', cities), 'Netherlands');
  assert.equal(resolveCityCountry('Cambridge', cities), null); // ambiguous -> never auto-accepts
  assert.equal(resolveCityCountry('Nowhereville', cities), null);
});
