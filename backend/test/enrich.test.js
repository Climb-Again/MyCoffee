// #161 — "you already own this one" matching and the enrich diff.
//
// The matcher is the risky half: a FALSE match tells Radu he owns a bag he
// doesn't and invites him to write page data onto the wrong record. Most of
// these tests exist to pin down what must NOT match.
import test from 'node:test';
import assert from 'node:assert/strict';
import { distinctiveTokens, rankMatches, diffFields } from '../src/lib/enrich.js';

const GARDELLI = 'Gardelli';

// Stands in for genericTokensFromVocab(shared.vocab.countries) — the country
// names the route strips so an origin can never carry a match on its own.
const GENERIC = new Set(['ethiopia', 'congo', 'kenya', 'colombia', 'rwanda', 'democratic', 'republic']);

// The real record from Radu's library (#165), and a plausible shop page for it.
const sopacdi = {
  id: 'fzh3Sz3vedFG4iGZms1FPA',
  rawTitle: 'Cafea Gardelli Sopacdi (Congo) MAI 2018 aeropress',
  purchasedOn: '2018-05-06',
  rating: 4.0,
  originCountryIds: [54],
  originFarmId: 190,
  profileId: null,
  roastedOn: null,
  weightG: null,
  altitudeMinM: null,
  altitudeMaxM: null,
  priceOriginalAmount: null,
  priceOriginalCurrency: null,
};

const ethiopia = {
  id: 'other1',
  rawTitle: 'Gardelli Ethiopia Uraga Washed',
  purchasedOn: '2024-02-01',
  rating: 4.2,
  originCountryIds: [2],
  originFarmId: null,
  profileId: 1,
  roastedOn: null,
  weightG: 250,
  altitudeMinM: null,
  altitudeMaxM: null,
  priceOriginalAmount: 17,
  priceOriginalCurrency: 'EUR',
};

// ---- distinctive tokens ----

test('the roaster name is never distinctive — every candidate shares it', () => {
  const t = distinctiveTokens('Gardelli Sopacdi Congo', { roasterName: GARDELLI });
  assert.ok(t.has('sopacdi'));
  assert.ok(!t.has('gardelli'), 'roaster name would make every comparison look like a match');
});

test('generic coffee words and processes are not distinctive', () => {
  const t = distinctiveTokens('Specialty Coffee Washed Natural Filter Espresso Blend', { roasterName: GARDELLI });
  assert.equal(t.size, 0);
});

test('bare numbers are not distinctive — a year or a weight identifies nothing', () => {
  const t = distinctiveTokens('Sopacdi 2018 250 1750', { roasterName: GARDELLI });
  assert.deepEqual([...t], ['sopacdi']);
});

test('Romanian title words are handled — Radu writes his own titles in Romanian', () => {
  const t = distinctiveTokens('Cafea Gardelli Sopacdi (Congo) MAI 2018 aeropress', { roasterName: GARDELLI });
  assert.ok(t.has('sopacdi'));
  assert.ok(t.has('congo'));
  assert.ok(!t.has('cafea'), '"cafea" is Romanian for coffee');
  assert.ok(!t.has('aeropress'));
  assert.ok(!t.has('mai'), '"mai" is Romanian for May');
});

test('diacritics fold, so a page spelling without them still matches', () => {
  const a = distinctiveTokens('Finca Nuñez', { roasterName: GARDELLI });
  const b = distinctiveTokens('Finca Nunez', { roasterName: GARDELLI });
  assert.deepEqual([...a], [...b]);
});

// ---- matching ----

test('matches the real coffee from a real shop title', () => {
  const ranked = rankMatches(
    { title: 'Sopacdi | Congo | Washed — Gardelli Specialty Coffees', originCountryId: 54 },
    [sopacdi, ethiopia],
    { roasterName: GARDELLI },
  );
  assert.equal(ranked.length, 1, 'only the Sopacdi row shares a distinctive word');
  assert.equal(ranked[0].id, sopacdi.id);
  assert.equal(ranked[0].confidence, 'strong');
  assert.ok(ranked[0].sharedTokens.includes('sopacdi'));
});

test('a DIFFERENT coffee from the same roaster does not match', () => {
  // The failure that matters: same roaster, same shape of title, different bag.
  const ranked = rankMatches(
    { title: 'Gardelli — Kieni AA, Kenya, Washed', originCountryId: 3 },
    [sopacdi, ethiopia],
    { roasterName: GARDELLI },
  );
  assert.deepEqual(ranked, [], 'no shared distinctive word means no match, not a weak one');
});

test('sharing only the roaster name does not match', () => {
  const ranked = rankMatches(
    { title: 'Gardelli Specialty Coffees', originCountryId: null },
    [sopacdi, ethiopia],
    { roasterName: GARDELLI },
  );
  assert.deepEqual(ranked, []);
});

test('sharing only origin and process does not match', () => {
  // "Gardelli Ethiopia Washed" describes plenty of different bags. Country
  // names come out of the live vocab, exactly as the route supplies them.
  const ranked = rankMatches(
    { title: 'Gardelli Ethiopia Washed', originCountryId: 2 },
    [ethiopia],
    { roasterName: GARDELLI, genericTokens: GENERIC },
  );
  assert.deepEqual(ranked, [], 'origin + process is a category, not an identity');
});

test('two different Ethiopians from one roaster do not match each other', () => {
  // The concrete false positive the generic-token set exists to stop.
  const uraga = { ...ethiopia, id: 'uraga', rawTitle: 'Gardelli Ethiopia Uraga Washed' };
  const guji = { ...ethiopia, id: 'guji', rawTitle: 'Gardelli Ethiopia Guji Natural' };
  const ranked = rankMatches(
    { title: 'Gardelli Ethiopia Guji Natural', originCountryId: 2 },
    [uraga, guji],
    { roasterName: GARDELLI, genericTokens: GENERIC },
  );
  assert.equal(ranked.length, 1, 'only the Guji lot shares a distinctive word');
  assert.equal(ranked[0].id, 'guji');
});

test('a country name alone is never distinctive once the vocab is supplied', () => {
  const t = distinctiveTokens('Gardelli Ethiopia Guji', { roasterName: GARDELLI, genericTokens: GENERIC });
  assert.ok(!t.has('ethiopia'));
  assert.ok(t.has('guji'));
});

test('a disagreeing origin downgrades a name match to possible', () => {
  const ranked = rankMatches(
    { title: 'Sopacdi — Rwanda', originCountryId: 4 },
    [sopacdi],
    { roasterName: GARDELLI },
  );
  assert.equal(ranked.length, 1);
  assert.equal(ranked[0].confidence, 'possible');
  assert.equal(ranked[0].originAgrees, false);
});

test('an unknown page origin stays strong rather than being punished', () => {
  const ranked = rankMatches({ title: 'Sopacdi lot', originCountryId: null }, [sopacdi], { roasterName: GARDELLI });
  assert.equal(ranked[0].confidence, 'strong');
  assert.equal(ranked[0].originAgrees, null);
});

test('an empty or generic page title matches nothing', () => {
  for (const title of ['', '   ', 'Coffee', 'Shop']) {
    assert.deepEqual(rankMatches({ title, originCountryId: 54 }, [sopacdi], { roasterName: GARDELLI }), []);
  }
});

test('the best match ranks first, with the rest offered as alternatives', () => {
  const twin = { ...sopacdi, id: 'twin', rawTitle: 'Gardelli Sopacdi Kivu lot 2 natural', originCountryIds: [54] };
  const ranked = rankMatches(
    { title: 'Gardelli Sopacdi Kivu lot 2', originCountryId: 54 },
    [sopacdi, twin],
    { roasterName: GARDELLI },
  );
  assert.equal(ranked.length, 2);
  assert.equal(ranked[0].id, 'twin', 'sharing "sopacdi" AND "kivu" beats sharing "sopacdi" alone');
});

// ---- the enrich diff ----

const fullPage = {
  originCountryName: 'Democratic Republic of the Congo',
  farmName: 'Sopacdi',
  profileName: 'Washed',
  roastedOn: '2026-09-01',
  weightG: 250,
  priceAmount: 18.5,
  priceCurrency: 'EUR',
  altitudeMin: 1600,
  altitudeMax: 1900,
};

test('offers only what the record is missing', () => {
  const diff = diffFields(fullPage, sopacdi);
  const fields = diff.map((d) => d.field);
  // The Sopacdi record has origin and farm already (repaired in #165), and
  // lacks everything else.
  assert.ok(!fields.includes('originCountry'), 'origin is already set — never offer to overwrite');
  assert.ok(!fields.includes('farm'), 'farm is already set');
  assert.deepEqual(fields, ['profile', 'roastedOn', 'weight', 'price', 'altitude']);
});

test('offers nothing when the record is already complete', () => {
  const complete = {
    ...sopacdi,
    profileId: 1,
    roastedOn: '2026-01-01',
    weightG: 250,
    altitudeMinM: 1500,
    priceOriginalAmount: 20,
    priceOriginalCurrency: 'EUR',
  };
  assert.deepEqual(diffFields(fullPage, complete), [], 'an always-present empty panel is worse than none');
});

test('offers nothing when the page itself carries nothing', () => {
  assert.deepEqual(diffFields({}, sopacdi), []);
});

test('a price with no currency is not offered — it would 422 on accept', () => {
  // parsePrice returns null without a currency marker, so the edit endpoint
  // would reject it. Better to not offer it than to offer a button that fails.
  const diff = diffFields({ priceAmount: 18.5, priceCurrency: null }, sopacdi);
  assert.ok(!diff.some((d) => d.field === 'price'));
});

test('values are formatted so the edit endpoint can re-parse them', () => {
  const diff = diffFields(fullPage, sopacdi);
  const by = Object.fromEntries(diff.map((d) => [d.field, d.value]));
  assert.equal(by.weight, '250 g');
  assert.equal(by.price, '18.5 EUR', 'a currency marker is mandatory for parsePrice');
  assert.equal(by.altitude, '1600-1900 masl');
  assert.equal(by.roastedOn, '2026-09-01');
});

test('a single-point altitude is not rendered as a range', () => {
  const diff = diffFields({ altitudeMin: 1750, altitudeMax: 1750 }, sopacdi);
  assert.equal(diff.find((d) => d.field === 'altitude').value, '1750 masl');
});

test('zero weight is treated as absent, not as a value worth writing', () => {
  const diff = diffFields({ weightG: 0 }, sopacdi);
  assert.ok(!diff.some((d) => d.field === 'weight'));
});
