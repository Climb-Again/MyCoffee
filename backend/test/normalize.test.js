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
  stripFarmAffixes,
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

  const implausible = parseAltitude('300 to 500 masl'); // real elevation, outside the soft 900-2200 band
  assert.equal(implausible.confidence, 0.5);
  assert.equal(implausible.needsReview, true);

  const wideSpan = parseAltitude('1000 to 2000 masl'); // >800m apart -> review
  assert.equal(wideSpan.needsReview, true);

  assert.equal(parseAltitude('no altitude mentioned here'), null);
  assert.equal(parseAltitude(''), null);
});

test('parseAltitude: word/locale unit spellings parse, not just m/masl (review accept 422 fix)', () => {
  // A review candidate kept the bag's own wording, e.g. "2000 meter", and
  // resolving it 422'd because only m/masl/m.a.s.l were recognised.
  for (const [text, expected] of [
    ['2000 meter', 2000],
    ['2000 metres', 2000],
    ['1900 metros', 1900],
    ['2100 msnm', 2100],
    ['2,100 MSN', 2100], // truncated m.s.n.m.
    ['1800 mt', 1800],
  ]) {
    const a = parseAltitude(text);
    assert.ok(a, `expected ${text} to parse`);
    assert.equal(a.min, expected);
    assert.equal(a.max, expected);
  }
  // Guard: a stray unit word without a plausible elevation still doesn't match.
  assert.equal(parseAltitude('a note with 5 meter clearance'), null);
});

test('parseAltitude: hard plausibility envelope — impossible elevations are absent, not a bogus value (#39)', () => {
  // Radu's own example: "1-5 m" is a roast-level scale/count bleeding into the
  // parse, not a real elevation — accept-by-default has no confidence gate to
  // stop it, so it must come out null (field absent) rather than stored.
  assert.equal(parseAltitude('1-5 m'), null);
  assert.equal(parseAltitude('50 to 80 masl'), null); // max < 200m floor
  assert.equal(parseAltitude('5000 to 6000 masl'), null); // min > 4000m ceiling
  assert.equal(parseAltitude('4500m'), null); // single value above the ceiling
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

test('parseWeight: hard plausibility envelope — sub-gram/over-5kg "bags" are absent, not a bogus value (#39)', () => {
  assert.equal(parseWeight('0.5g bag'), null);
  assert.equal(parseWeight('6000g bag'), null);
});

test('parseWeight/parseAltitude: decimals are rounded — weight_g / altitude_*_m are INTEGER columns', () => {
  // A live extraction ("18.5 g") crashed the coffee insert with
  // `invalid input syntax for type integer: "18.5"` — round instead.
  assert.equal(parseWeight('18.5 g').grams, 19);
  assert.equal(Number.isInteger(parseWeight('18.5 g').grams), true);
  const alt = parseAltitude('1850.5 masl');
  assert.equal(Number.isInteger(alt.min), true);
  assert.equal(Number.isInteger(alt.max), true);
});

// ---- Rating ----

test('parseRating: explicit /5, star emoji, and bare-number confidence tiers', () => {
  assert.deepEqual(parseRating('4.1/5'), { value: 4.1, confidence: 1.0 });
  assert.deepEqual(parseRating('3,9/5'), { value: 3.9, confidence: 1.0 });
  assert.deepEqual(parseRating('⭐️4.1'), { value: 4.1, confidence: 0.9 });
  assert.deepEqual(parseRating('4.1'), { value: 4.1, confidence: 0.6 }); // bare number -> 0.6
  assert.equal(parseRating(''), null);
});

test('parseRating: stays within its 0-5 scale — an out-of-range number is absent, not a bogus rating (#39)', () => {
  assert.equal(parseRating('9/5'), null); // impossible on a /5 scale
  assert.equal(parseRating('1800'), null); // altitude-shaped bare number, not a rating
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

test('parseDate: spelled-out months, English + Romanian, day-first and month-first', () => {
  const cases = [
    ['07 August 2026', 2026, 8, 7], // the screenshot case ("Data de prăjire: 07 August 2026")
    ['7 iunie 2021', 2021, 6, 7], // Romanian, day-first
    ['1 Aug. 2026', 2026, 8, 1], // abbreviated month with period
    ['August 7, 2026', 2026, 8, 7], // English, month-first
    ['Sept 15 2025', 2025, 9, 15], // abbreviated month-first, no comma
    ['1 Mai 2021', 2021, 5, 1], // Romanian "mai"
  ];
  for (const [text, y, mo, d] of cases) {
    const r = parseDate(text);
    assert.ok(r && !r.rejected, `expected a date for ${text}`);
    assert.equal(r.date.getUTCFullYear(), y, `year for ${text}`);
    assert.equal(r.date.getUTCMonth() + 1, mo, `month for ${text}`);
    assert.equal(r.date.getUTCDate(), d, `day for ${text}`);
  }
  // An unknown month word is not a date.
  assert.equal(parseDate('07 Smarch 2026'), null);
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
    // The literal word the edit sheet sends for the Experimental process must
    // resolve back — otherwise editing a coffee to "Experimental" saved blank.
    ['Experimental', 'experimental'],
  ];
  for (const [text, expected] of cases) {
    assert.equal(parseProfile(text).profileId, expected, `parseProfile(${text})`);
  }
});

test('parseProfile: honey-only variants fold into Washed, literal term preserved', () => {
  // Radu, 2026-08-29: "if it's just honey I want to normalize all as Washed" —
  // a permanent rule, not a one-off backfill. Colour qualifiers are honey
  // variants, not a second method, so they map the same way as bare Honey.
  const cases = [
    ['Honey process', 'Honey'],
    ['Yellow Honey process', 'Yellow Honey'],
    ['Black Honey process', 'Black Honey'],
    ['Honey', 'Honey'],
    ['honey', 'honey'],
    ['Black Honey', 'Black Honey'],
    ['Yellow Honey', 'Yellow Honey'],
    ['White Honey', 'White Honey'],
    ['Red Honey', 'Red Honey'],
  ];
  for (const [text, detail] of cases) {
    const r = parseProfile(text);
    assert.equal(r.profileId, 'washed', `parseProfile(${text}).profileId`);
    assert.equal(r.detail, detail, `parseProfile(${text}).detail`);
  }

  // "Pulped natural" is a honey process, not a natural one — the fragment
  // exclusion below keeps the structured "natural" alias from hijacking it,
  // so it still lands in the honey-only bucket.
  const pulped = parseProfile('pulped natural');
  assert.equal(pulped.profileId, 'washed');
  assert.equal(pulped.detail, 'pulped natural');
});

test('parseProfile: honey plus a genuinely different method is a hybrid -> Experimental', () => {
  const anaerobic = parseProfile('Anaerobic Honey');
  assert.equal(anaerobic.profileId, 'experimental');
  assert.equal(anaerobic.detail, 'Honey');

  const coFermented = parseProfile('Honey Co-fermented');
  assert.equal(coFermented.profileId, 'experimental');
  assert.equal(coFermented.detail, 'Honey');
});

test('parseProfile: a caption merely mentioning honey as a tasting note does not touch the profile', () => {
  // #80's flavour-notes backfill means stored text is full of "honey" as a
  // cupping descriptor — that must never be read as a process signal.
  const r = parseProfile('wild honey, floral');
  assert.equal(r.profileId, null);
  assert.equal(r.detail, null);
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

// --- Profile/decaf rules derived from the real 5-photo sample (#26) ---
// Radu's rule: if at least one profile can be structured, allocate to that;
// otherwise file it under Experimental. Honey is the one exception (#110,
// 2026-08-29): honey plus a distinct structured method is a hybrid, so it
// files under Experimental rather than the other structured process.
test('parseProfile: honey plus a structured process is a hybrid -> Experimental, keeping Honey as detail', () => {
  const r = parseProfile('Procesare: Co-Fermentata cu fructe, Honey');
  assert.equal(r.profileId, 'experimental');
  assert.equal(r.detail, 'Honey');
});

test('parseProfile: the distinguishing process beats the generic one', () => {
  // Sample record read as plain "washed" before this, losing the co-fermentation.
  assert.equal(parseProfile('Procesare: Co-Fermentata cu fructe, Washed').profileId, 'co_fermented');
  // ...but "Experimental Washed" is a real washed process, not the catch-all.
  assert.equal(parseProfile('Processing: Experimental Washed').profileId, 'washed');
});

test('parseProfile: Romanian process spellings resolve', () => {
  // "Anaerob" does not substring-match "anaerobic" — this was a live miss.
  assert.equal(parseProfile('Procesare: Anaerob, Decaf').profileId, 'anaerobic');
  assert.equal(parseProfile('Procesare: Double Anaerobic').profileId, 'anaerobic');
});

test('parseProfile: decaf is detected from the corpus spellings', () => {
  assert.equal(parseProfile('El Vergel (Decaf) ANAEROBIC FERMENTED AND DECAFFEINATED').isDecaf, true);
  assert.equal(parseProfile('Procesare: Anaerob, Decaf').isDecaf, true);
  assert.equal(parseProfile('cafea decofeinizata').isDecaf, true);
});

test('parseProfile: Romanian "ea" is not read as the ethyl-acetate decaf process', () => {
  // A bare 'ea' term made every Romanian caption a false-positive decaf.
  assert.equal(parseProfile('O cafea buna, ea este delicioasa').isDecaf, false);
  assert.equal(parseProfile('Decaf via ethyl acetate').isDecaf, true);
});

test('parseProfile: an unmodelled process falls back to experimental, silence stays null', () => {
  assert.equal(parseProfile('Procesare: Wet Hulled Giling Basah').profileId, 'experimental');
  // No process mentioned at all -> never guess (and never default to Washed).
  assert.equal(parseProfile('Origine: Brazilia | Varietal: Paraiso').profileId, null);
});

// ---- #98: farm facility affixes (comparison only, never a rename) ----
test('stripFarmAffixes collapses facility affixes so duplicates match', () => {
  const cases = [
    ['Banko Gotiti Washing Station', 'banko gotiti'],
    ['Banko Gotiti', 'banko gotiti'],
    ['Nano Challa Cooperative', 'nano challa'],
    ['Nano Challa', 'nano challa'],
    ['BENTI NENKA WASHING STATION', 'benti nenka'],
    ['Finca El Paraiso', 'el paraiso'],
    ['el paraiso', 'el paraiso'],
    ['Elida Estate Farm', 'elida'],
    ['Chelchele washing and drying station', 'chelchele'],
    ['Fazenda Um', 'um'],
  ];
  for (const [input, expected] of cases) {
    assert.equal(stripFarmAffixes(input), expected, `stripFarmAffixes(${JSON.stringify(input)})`);
  }
});

test('stripFarmAffixes leaves real names that merely contain an affix-like word', () => {
  // Radu, 2026-08-28: these are correct names and must survive verbatim.
  // "farm" is word-boundary anchored, so it cannot eat "farmers".
  for (const name of ['Several small farmers', 'Smallholder farmers', '5 small farmers']) {
    assert.equal(stripFarmAffixes(name), name.toLowerCase(), name);
  }
});

test('stripFarmAffixes never returns empty for an affix-only name', () => {
  // A name that is ONLY an affix keeps its identity rather than collapsing to
  // '' and fuzzy-matching everything in the vocabulary.
  for (const name of ['Estate', 'The Mill', 'Finca']) {
    assert.notEqual(stripFarmAffixes(name), '');
  }
});

test('the two duplicate pairs #91 created now compare equal', () => {
  assert.equal(stripFarmAffixes('Banko Gotiti Washing Station'), stripFarmAffixes('Banko Gotiti'));
  assert.equal(stripFarmAffixes('Nano Challa Cooperative'), stripFarmAffixes('Nano Challa'));
  // ...and a genuinely different farm still does NOT collide with them.
  assert.notEqual(stripFarmAffixes('BENTI NENKA WASHING STATION'), stripFarmAffixes('Banko Gotiti'));
});

// ---- #123: every envelope must reject the DEGENERATE end, not just out-of-range ----
//
// The bug this locks down: inRatingScale was `>= 0`, so a stray `0` in the text
// became a real rating. #39 added these envelopes precisely so an implausible
// number reads as ABSENT; an inclusive floor defeats that. These tests walk the
// low end of all four so the next envelope added has an obvious pattern to copy.
test('parseRating rejects 0 — in this app 0 means unrated, not "I hated it"', () => {
  for (const input of ['0', '0.0', '0/5', '0,0', '⭐️ 0']) {
    assert.equal(parseRating(input), null, `parseRating(${JSON.stringify(input)}) must be null`);
  }
});

test('parseRating still accepts the smallest real ratings', () => {
  // The live library's lowest genuine rating is 2.0, but nothing should stop a
  // legitimately low score from parsing — only 0 is reserved for "absent".
  for (const [input, expected] of [['0.5/5', 0.5], ['1', 1], ['2.0', 2], ['5/5', 5]]) {
    assert.equal(parseRating(input)?.value, expected, input);
  }
});

test('parseRating still rejects above-scale values', () => {
  for (const input of ['5.1', '6/5', '9']) {
    assert.equal(parseRating(input), null, input);
  }
});

test('parsePrice rejects a zero price — it would read as infinitely cheap', () => {
  // No upper bound on purpose: an expensive bag is plausible. But 0 makes
  // price_per_100g 0, which the value bands score as GREAT VALUE.
  for (const input of ['0', '0.00', '€0', '0 EUR', '€0.00']) {
    assert.equal(parsePrice(input), null, `parsePrice(${JSON.stringify(input)}) must be null`);
  }
  assert.equal(parsePrice('€15.95')?.amount, 15.95);
});

test('parseAltitude and parseWeight already reject their degenerate ends', () => {
  // Recorded so a later refactor cannot quietly loosen these to match the old
  // rating floor: altitude floors at 200m, weight at 1g.
  assert.equal(parseAltitude('0 m'), null);
  assert.equal(parseAltitude('0-0 m'), null);
  assert.equal(parseWeight('0g'), null);
  assert.equal(parseWeight('250g')?.grams, 250);
});

// ---- #184: a date is not an altitude, and never outranks a real one ----
//
// Found 2026-09-09 when the extension's enrich diff offered "9-2026 masl" for
// a Congo bag. The range pattern made its unit OPTIONAL and ran first, so
// `2026-09-01` parsed as a 9-2026 m range — and beat an explicit `1750 masl`
// on the same page purely by appearing earlier in the string.

test('parseAltitude: an ISO date is not an altitude', () => {
  assert.equal(parseAltitude('Roasted on: 2026-09-01'), null);
  assert.equal(parseAltitude('2026-09-01'), null);
  assert.equal(parseAltitude('01-09-2026'), null);
});

test('parseAltitude: a unit-anchored value beats a date anywhere in the text', () => {
  // The date comes FIRST here, which is exactly what used to lose.
  const r = parseAltitude('Roasted on: 2026-09-01\nAltitude: 1750 masl');
  assert.equal(r.min, 1750);
  assert.equal(r.max, 1750);
  assert.equal(r.needsReview, false);
});

test('parseAltitude: an anchored range beats a bare numeric pair earlier in the text', () => {
  const r = parseAltitude('Lot 12-34, grown at 1500-1800 masl');
  assert.deepEqual([r.min, r.max], [1500, 1800]);
});

test('parseAltitude: a bare range is still read when nothing contradicts it', () => {
  // Plenty of bags write it without a unit; this must keep working.
  assert.deepEqual(
    (({ min, max }) => ({ min, max }))(parseAltitude('1500-1800')),
    { min: 1500, max: 1800 },
  );
});

test('parseAltitude: scanning continues past a date to find a real bare range', () => {
  const r = parseAltitude('Roasted 2026-09-01, grown 1500-1800');
  assert.deepEqual([r.min, r.max], [1500, 1800]);
});

test('parseAltitude: an unanchored endpoint under 100 m is rejected as date-shaped', () => {
  // Coffee is never grown below 100 m, so this costs no real data and is what
  // kills 2026-09 / 09-2026 / 01-09.
  assert.equal(parseAltitude('9-2026'), null);
  assert.equal(parseAltitude('2026-09'), null);
});

// ---- #185: ISO currency codes, and feet is not forints ----
//
// JSON-LD's `Product.offers.priceCurrency` is an ISO code by specification and
// is the first thing the browser extension reads, so codes the table did not
// know silently dropped the whole value half of the score.

test('parsePrice: ISO codes are recognised, not just symbols', () => {
  const expected = {
    '103 RON': 'RON', '200 CZK': 'CZK', '80 PLN': 'PLN', '3500 HUF': 'HUF',
    '250 SEK': 'SEK', '250 NOK': 'NOK', '250 DKK': 'DKK',
    '18.5 EUR': 'EUR', '20 USD': 'USD', '15 GBP': 'GBP', '25 CHF': 'CHF',
  };
  for (const [text, currency] of Object.entries(expected)) {
    assert.equal(parsePrice(text)?.currency, currency, `${text} should be ${currency}`);
  }
});

test('parsePrice: the symbol forms still work', () => {
  const expected = { '103 lei': 'RON', '200 kč': 'CZK', '80 zł': 'PLN', '€18': 'EUR', '$20': 'USD', '£15': 'GBP' };
  for (const [text, currency] of Object.entries(expected)) {
    assert.equal(parsePrice(text)?.currency, currency, `${text} should be ${currency}`);
  }
});

test('parsePrice: an altitude in FEET is not a price in forints', () => {
  // `ft` was the HUF marker under /i, so `parsePrice('1500 ft')` returned
  // 1500 HUF. Hungarian capitalises the forint; feet does not.
  // parsePrice still reports the bare amount (that is its contract); what
  // matters is that no CURRENCY is invented, because canonicalize() drops a
  // price with no currency and so the feet never become money.
  assert.equal(parsePrice('1500 ft')?.currency ?? null, null);
  assert.equal(parsePrice('grown at 1500 ft')?.currency ?? null, null);
  assert.equal(parsePrice('3500 Ft')?.currency, 'HUF');
  assert.equal(parsePrice('3500 FT')?.currency, 'HUF');
});

test('parsePrice: an unknown currency still declines rather than guessing', () => {
  // Load-bearing: resolveField assumes RON for a bare amount, so a currency
  // that slipped through as null would be written as RON.
  assert.equal(parsePrice('200 XYZ')?.currency ?? null, null);
});
