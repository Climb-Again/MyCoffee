// Table-driven coverage for backend/src/lib/deterministic.js — the P3
// "rules" voter (PLAN.md §2). Pure, no DB: `roasterVocab`/`countryVocab` are
// hand-built fixtures in the same `{ candidates, aliasIndex }` shape
// `vocab.js`'s loaders produce (see vocab.test.js), not a live Postgres.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildAliasIndex } from '../src/lib/vocab.js';
import {
  findAliasMentions,
  extractRoasterField,
  extractOriginCountriesField,
  extractRoasterCountryOverride,
  extractFarmField,
  extractRoastedOnField,
  extractProfileField,
  extractRuleFields,
} from '../src/lib/deterministic.js';

const ROASTER_VOCAB = {
  candidates: [
    { id: 1, name: 'DAK Coffee Roasters' },
    { id: 2, name: 'Kolibri' },
    { id: 3, name: 'Kaffa' },
    { id: 4, name: "Father's Coffee Roastery" },
    { id: 5, name: 'Father Carpenter' },
  ],
  aliasIndex: buildAliasIndex([
    { id: 1, alias: 'DAK Coffee Roasters', alias_norm: 'dak coffee roasters' },
    { id: 1, alias: 'DAK', alias_norm: 'dak' },
    { id: 2, alias: 'Kolibri', alias_norm: 'kolibri' },
    { id: 3, alias: 'Kaffa', alias_norm: 'kaffa' },
    { id: 4, alias: "Father's Coffee Roastery", alias_norm: "father's coffee roastery" },
    { id: 4, alias: "Father's", alias_norm: "father's" },
    { id: 5, alias: 'Father Carpenter', alias_norm: 'father carpenter' },
  ]),
};

const COUNTRY_VOCAB = {
  candidates: [
    { id: 1, name: 'Colombia', is_origin: true, is_roaster: false },
    { id: 2, name: 'Ethiopia', is_origin: true, is_roaster: false },
    { id: 3, name: 'Brazil', is_origin: true, is_roaster: false },
    { id: 4, name: 'Netherlands', is_origin: false, is_roaster: true },
    { id: 5, name: 'United Kingdom', is_origin: false, is_roaster: true },
  ],
  aliasIndex: buildAliasIndex([
    { id: 1, alias: 'Colombia', alias_norm: 'colombia' },
    { id: 1, alias: 'Columbia', alias_norm: 'columbia' },
    { id: 2, alias: 'Ethiopia', alias_norm: 'ethiopia' },
    { id: 2, alias: 'Etiopia', alias_norm: 'etiopia' },
    { id: 3, alias: 'Brazil', alias_norm: 'brazil' },
    { id: 4, alias: 'Netherlands', alias_norm: 'netherlands' },
    { id: 4, alias: 'Olanda', alias_norm: 'olanda' },
    { id: 5, alias: 'United Kingdom', alias_norm: 'united kingdom' },
    { id: 5, alias: 'Marea Britanie', alias_norm: 'marea britanie' },
  ]),
};

// ---- findAliasMentions ----

test('findAliasMentions: matches a short alias only at a word boundary', () => {
  const mentions = findAliasMentions('Roasted by DAK, delicious bag', ROASTER_VOCAB.aliasIndex);
  assert.deepEqual(mentions.map((m) => m.id), [1]);
});

test('findAliasMentions: a short alias inside a longer word is not a false positive', () => {
  const mentions = findAliasMentions('vodakas everywhere', ROASTER_VOCAB.aliasIndex);
  assert.deepEqual(mentions, []);
});

test('findAliasMentions: prefers the longest (most specific) alias for a given id', () => {
  const mentions = findAliasMentions('From DAK Coffee Roasters, great espresso', ROASTER_VOCAB.aliasIndex);
  assert.equal(mentions.length, 1);
  assert.equal(mentions[0].alias, 'DAK Coffee Roasters');
});

test('findAliasMentions: diacritic-folded text still matches an ASCII alias', () => {
  const mentions = findAliasMentions('Din Etiopia, superb', COUNTRY_VOCAB.aliasIndex);
  assert.deepEqual(mentions.map((m) => m.id), [2]);
});

test('findAliasMentions: empty text or missing index resolves to nothing', () => {
  assert.deepEqual(findAliasMentions('', ROASTER_VOCAB.aliasIndex), []);
  assert.deepEqual(findAliasMentions('DAK', null), []);
});

// ---- extractRoasterField ----

test('extractRoasterField: a clear single mention is proposed', () => {
  const result = extractRoasterField('Roaster: Kolibri, love it', ROASTER_VOCAB);
  assert.deepEqual(result, { value: 'Kolibri', confidence: 1.0, evidence: 'Kolibri' });
});

test('extractRoasterField: "Father\'s Coffee Roastery" mention never collapses into "Father Carpenter"', () => {
  const result = extractRoasterField('From Father\'s Coffee Roastery, excellent', ROASTER_VOCAB);
  assert.equal(result.value, "Father's Coffee Roastery");
});

test('extractRoasterField: two distinct roasters of equal specificity in one caption is ambiguous, not guessed', () => {
  const tiedVocab = {
    candidates: [
      { id: 1, name: 'Kolibri' },
      { id: 2, name: 'Kaffara' },
    ],
    aliasIndex: buildAliasIndex([
      { id: 1, alias: 'Kolibri', alias_norm: 'kolibri' },
      { id: 2, alias: 'Kaffara', alias_norm: 'kaffara' },
    ]),
  };
  const result = extractRoasterField('Kolibri vs Kaffara, side by side tasting', tiedVocab);
  assert.equal(result, null);
});

test('extractRoasterField: no mention proposes nothing', () => {
  assert.equal(extractRoasterField('A lovely coffee, no roaster named', ROASTER_VOCAB), null);
});

// ---- extractOriginCountriesField ----

test('extractOriginCountriesField: a single origin mention', () => {
  const result = extractOriginCountriesField('Beans from Ethiopia, washed', COUNTRY_VOCAB);
  assert.deepEqual(result, { value: 'Ethiopia', confidence: 1.0, evidence: 'Ethiopia' });
});

test('extractOriginCountriesField: multiple origins are joined for downstream splitting', () => {
  const result = extractOriginCountriesField('A blend of Colombia and Brazil', COUNTRY_VOCAB);
  const parts = result.value.split(' / ');
  assert.deepEqual(new Set(parts), new Set(['Colombia', 'Brazil']));
});

test('extractOriginCountriesField: a roaster-only country mention (Netherlands) is never proposed as an origin', () => {
  assert.equal(extractOriginCountriesField('Roasted in the Netherlands', COUNTRY_VOCAB), null);
});

test('extractOriginCountriesField: an alias variant is proposed as literally written — resolveVocab resolves the alias downstream', () => {
  const result = extractOriginCountriesField('Columbia, lovely', COUNTRY_VOCAB);
  assert.equal(result.value, 'Columbia');
});

// ---- extractRoasterCountryOverride (#48b) ----

test('extractRoasterCountryOverride: a caption stating the roaster city/country in Romanian resolves it — the real Uncommon bug', () => {
  const id = extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)', COUNTRY_VOCAB);
  assert.equal(id, 4); // Netherlands, not the vocab's stale United Kingdom guess
});

test('extractRoasterCountryOverride: a diacritic-free spelling still matches (fold happens at match time, not storage time)', () => {
  const id = extractRoasterCountryOverride('Prajitorie: Uncommon (Amsterdam, Olanda)', COUNTRY_VOCAB);
  assert.equal(id, 4);
});

test('extractRoasterCountryOverride: no country mention at all declines (caller keeps the vocab-derived country)', () => {
  assert.equal(extractRoasterCountryOverride('A lovely washed coffee, no location named', COUNTRY_VOCAB), null);
});

test('extractRoasterCountryOverride: an origin-only mention (Ethiopia, the beans) is never read as the roaster location', () => {
  assert.equal(extractRoasterCountryOverride('Single origin Ethiopia, notes of jasmine', COUNTRY_VOCAB), null);
});

test('extractRoasterCountryOverride: two distinct roaster-countries mentioned is ambiguous and declines rather than guesses', () => {
  const id = extractRoasterCountryOverride('Roasted in the Netherlands, imported from United Kingdom stock', COUNTRY_VOCAB);
  assert.equal(id, null);
});

test('extractRoasterCountryOverride: the same country mentioned via two different aliases is not ambiguous (one distinct id)', () => {
  const id = extractRoasterCountryOverride('Prăjitorie olandeză, i.e. Netherlands, a.k.a. Olanda', COUNTRY_VOCAB);
  assert.equal(id, 4);
});

test('extractRoasterCountryOverride: no vocab passed declines rather than throwing', () => {
  assert.equal(extractRoasterCountryOverride('Prăjitorie: Uncommon (Amsterdam, Olanda)', undefined), null);
});

// ---- extractFarmField ----

test('extractFarmField: a "Finca" line proposes the residual farm name', () => {
  const result = extractFarmField('Great coffee.\nFinca El Paraiso — Diego Bermudez.\nEnjoyed it a lot.');
  assert.equal(result.value, 'Diego Bermudez');
});

test('extractFarmField: a "Producer:" line resolves to the same residual name', () => {
  const result = extractFarmField('Producer: Diego Bermudez');
  assert.equal(result.value, 'Diego Bermudez');
});

test('extractFarmField: no recognised prefix proposes nothing', () => {
  assert.equal(extractFarmField('A lovely coffee from a small farm, no name given'), null);
});

test('extractFarmField: empty text proposes nothing', () => {
  assert.equal(extractFarmField(''), null);
  assert.equal(extractFarmField(null), null);
});

// ---- extractRoastedOnField ----

test('extractRoastedOnField: a date near an explicit roast keyword is proposed', () => {
  const result = extractRoastedOnField('Bought 1kg. Roasted on 12.03.2021, very fresh.');
  assert.equal(result.value, '12.03.2021');
});

test('extractRoastedOnField: a date with no roast keyword nearby is never guessed (could be a purchase date)', () => {
  assert.equal(extractRoastedOnField('Bought on 12.03.2021, no roast date given'), null);
});

test('extractRoastedOnField: no date at all proposes nothing', () => {
  assert.equal(extractRoastedOnField('Roasted recently, no date on the bag'), null);
});

// ---- extractProfileField (delegates re-parsing to canonicalize(), so this only gates presence) ----

test('extractProfileField: a recognised profile term is passed through for re-parsing', () => {
  const result = extractProfileField('Washed process, floral notes');
  assert.equal(result.value, 'Washed process, floral notes');
});

test('extractProfileField: decaf alone (no profile) still counts as a signal', () => {
  const result = extractProfileField('Decaf, Swiss Water process');
  assert.ok(result);
});

test('extractProfileField: never defaults to Washed when nothing matches — proposes nothing', () => {
  assert.equal(extractProfileField('A coffee bag with no process mentioned'), null);
});

// ---- extractRuleFields (whole-record assembly) ----

test('extractRuleFields: assembles only the fields that actually fired', () => {
  const rawText = 'Roaster: Kolibri. Origin: Ethiopia. 250g, 4.1/5, 45 lei. Anaerobic process.';
  const fields = extractRuleFields(rawText, { roasterVocab: ROASTER_VOCAB, countryVocab: COUNTRY_VOCAB });

  assert.equal(fields.roaster_id.value, 'Kolibri');
  assert.equal(fields.origin_country_ids.value, 'Ethiopia');
  assert.equal(fields.weight_g.value, rawText);
  assert.equal(fields.rating.value, rawText);
  assert.equal(fields.price.value, rawText);
  assert.equal(fields.profile.value, rawText);
  assert.equal(fields.origin_farm_id, undefined);
  assert.equal(fields.roasted_on, undefined);
  assert.equal(fields.altitude, undefined);
  assert.ok(!('desc_farm_lot' in fields));
  assert.ok(!('desc_brew_guide' in fields));
  assert.ok(!('desc_roaster_copy' in fields));
});

test('extractRuleFields: a bare digit from an unrelated field (altitude/date) is never mistaken for a price or rating', () => {
  const rawText = 'Finca El Paraiso. Roasted on 05.06.2024. 1300 to 1600 masl, no price or rating on the bag.';
  const fields = extractRuleFields(rawText, { roasterVocab: ROASTER_VOCAB, countryVocab: COUNTRY_VOCAB });
  assert.equal(fields.price, undefined);
  assert.equal(fields.rating, undefined);
  assert.ok(fields.altitude); // the actual altitude marker still fires
});

test('extractRuleFields: a currency-marked price and a "/5" rating alongside unrelated digits still resolve correctly', () => {
  const rawText = 'Roasted on 05.06.2024. 250g, 4.1/5, 45 lei.';
  const fields = extractRuleFields(rawText, { roasterVocab: ROASTER_VOCAB, countryVocab: COUNTRY_VOCAB });
  assert.ok(fields.price);
  assert.ok(fields.rating);
});

test('extractRuleFields: a caption with nothing recognisable proposes an empty field set, not a wrong guess', () => {
  const fields = extractRuleFields('Just a nice coffee, drank it all', { roasterVocab: ROASTER_VOCAB, countryVocab: COUNTRY_VOCAB });
  assert.deepEqual(fields, {});
});

test('extractRuleFields: missing vocab dictionaries is handled without throwing', () => {
  const fields = extractRuleFields('45 lei, 250g, 4.1/5');
  assert.equal(fields.roaster_id, undefined);
  assert.equal(fields.origin_country_ids, undefined);
  assert.ok(fields.price);
  assert.ok(fields.weight_g);
  assert.ok(fields.rating);
});
