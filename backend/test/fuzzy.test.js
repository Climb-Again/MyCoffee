// Table-driven coverage for backend/src/lib/fuzzy.js — the mechanised version
// of "guess only very close matches" (PLAN.md §2). The negative cases here are
// not incidental: they are the two pairs the brief's own data surfaces as
// near-misses that must NOT be auto-merged.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  levenshteinDistance,
  normalizedLevenshteinSimilarity,
  trigramSimilarity,
  matchVocab,
} from '../src/lib/fuzzy.js';

test('levenshteinDistance: basic edit distances', () => {
  assert.equal(levenshteinDistance('kitten', 'sitting'), 3);
  assert.equal(levenshteinDistance('same', 'same'), 0);
  assert.equal(levenshteinDistance('', 'abc'), 3);
});

test('normalizedLevenshteinSimilarity: identical strings score 1, case/whitespace-insensitive', () => {
  assert.equal(normalizedLevenshteinSimilarity('DAK', ' dak '), 1);
});

test('trigramSimilarity: identical strings score 1', () => {
  assert.equal(trigramSimilarity('Colombia', 'colombia'), 1);
});

// ---- The vocabulary this was built from: docx spelling variants ----

test('matchVocab: accepts unambiguous spelling variants from the docx lists', () => {
  const countries = ['Colombia', 'Ethiopia', 'Brazil', 'Indonesia', 'Mexico', 'Nicaragua', 'Thailand'];
  const cases = [
    ['Columbia', 'Colombia'],
    ['Etiopia', 'Ethiopia'],
    ['Brazilia', 'Brazil'],
    ['Indonezia', 'Indonesia'],
    ['Mexic', 'Mexico'],
    ['NIcaragua', 'Nicaragua'],
    ['Thailanda', 'Thailand'],
  ];
  for (const [input, expected] of cases) {
    const result = matchVocab(input, countries);
    assert.equal(result.accepted, true, `expected ${input} to accept`);
    assert.equal(result.match, expected, `expected ${input} to match ${expected}`);
  }
});

test('matchVocab: accepts near-miss typos of a similar-length roaster name', () => {
  // Genuine fuzzy territory: a one-letter typo of a full-length name, not an
  // abbreviation. (Abbreviation-style variants like "DAK" -> "DAK Coffee
  // Roasters" or "Boo!" -> "BOO Modern Coffee" are already exact aliases in
  // 005_vocab_seed.sql, resolved by a direct alias_norm lookup — fuzzy
  // matching a 3-letter input against a 20-letter name is the wrong tool and
  // correctly refuses, which is covered by the negative cases below.)
  const roasters = ['Gardelli', 'Friedhats', 'Father\'s Coffee Roastery', 'Father Carpenter', 'Kolibri'];
  assert.equal(matchVocab('Gardeli', roasters).match, 'Gardelli');
  assert.equal(matchVocab('Freidhats', roasters).match, 'Friedhats');
});

test('matchVocab: refuses an abbreviation against its full name — that is an exact-alias job, not fuzzy', () => {
  const result = matchVocab('DAK', ['DAK Coffee Roasters', 'Other Roastery']);
  assert.equal(result.accepted, false);
});

// ---- The mandatory negative cases ----

test('matchVocab: Kofio must NOT match Kolibri', () => {
  const result = matchVocab('Kofio', ['Kolibri', 'Kaffa', 'Krok']);
  assert.equal(result.accepted, false);
  assert.equal(result.match, null);
});

test('matchVocab: Father\'s Coffee Roastery must NOT match Father Carpenter', () => {
  const roasters = ['Father Carpenter', 'Other Roastery', 'Some Other Coffee'];
  const result = matchVocab("Father's Coffee Roastery", roasters);
  assert.equal(result.accepted, false);
  assert.notEqual(result.match, 'Father Carpenter');
});

test('matchVocab: the reverse direction also refuses — Father Carpenter must NOT match Father\'s Coffee Roastery', () => {
  const roasters = ["Father's Coffee Roastery", 'Some Other Roastery'];
  const result = matchVocab('Father Carpenter', roasters);
  assert.equal(result.accepted, false);
});

test('matchVocab: no candidates -> refuses cleanly', () => {
  assert.equal(matchVocab('anything', []).accepted, false);
  assert.equal(matchVocab('', ['Colombia']).accepted, false);
});

test('matchVocab: a tie at the top score is never auto-accepted, even above threshold', () => {
  // Two identical candidate names -> tied best, must not silently pick one.
  const result = matchVocab('Colombia', ['Colombia', 'Colombia']);
  assert.equal(result.accepted, false);
  assert.equal(result.reason, 'not a unique best candidate');
});

test('matchVocab: insufficient margin over a close runner-up refuses', () => {
  // Two very similar candidates neither of which clearly wins.
  const result = matchVocab('Kolombia', ['Colombia', 'Kolumbia']);
  assert.equal(result.accepted, false);
});
