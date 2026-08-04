// Prompt building and response parsing are pure (no network) -- same split as
// vertex.test.js's buildRequestBody/parseResponse coverage. Only
// runExtractA/B/Critic/Reconciler touch the network, and those aren't
// exercised here (no live Vertex call in a test suite that runs without
// credentials in CI).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  FIELD_KEY_MAP,
  EXTRACT_RESPONSE_SCHEMA,
  buildExtractPrompt,
  buildCriticPrompt,
  buildReconcilerPrompt,
  parseExtractResponse,
  parseCriticResponse,
  estimateCostUsd,
} from '../src/lib/agents.js';

test('EXTRACT_RESPONSE_SCHEMA has no min/max/minLength -- Vertex rejects those on a response schema', () => {
  const json = JSON.stringify(EXTRACT_RESPONSE_SCHEMA);
  assert.ok(!/"minimum"|"maximum"|"minLength"/.test(json));
});

test('buildExtractPrompt renders the vocab block in a different order for extract_a vs extract_b', () => {
  const vocabShortlist = ['Alpha Roasters', 'Beta Roasters', 'Gamma Roasters'];
  const a = buildExtractPrompt('extract_a', { rawText: 'x', vocabShortlist });
  const b = buildExtractPrompt('extract_b', { rawText: 'x', vocabShortlist });
  assert.notEqual(a.prompt, b.prompt);
  assert.ok(a.prompt.includes('Alpha Roasters, Beta Roasters, Gamma Roasters'));
  assert.ok(b.prompt.includes('Gamma Roasters, Beta Roasters, Alpha Roasters'));
});

test('buildExtractPrompt gives extract_a and extract_b genuinely different framing', () => {
  const a = buildExtractPrompt('extract_a', { rawText: 'x' });
  const b = buildExtractPrompt('extract_b', { rawText: 'x' });
  assert.ok(a.system.includes('caption'));
  assert.ok(b.system.includes('checklist'));
});

test('buildExtractPrompt rejects an unknown agent', () => {
  assert.throws(() => buildExtractPrompt('nope', {}));
});

test('buildCriticPrompt summarizes every field candidate for review, never proposing a value itself', () => {
  const { system, prompt } = buildCriticPrompt({
    rawText: 'Ethiopia, washed, 250g',
    candidatesByField: { roaster_id: [{ agent: 'extract_a', value: 'DAK' }] },
  });
  assert.ok(/refute/i.test(system));
  assert.ok(prompt.includes('roaster_id'));
  assert.ok(prompt.includes('extract_a="DAK"'));
});

test('buildReconcilerPrompt includes every voter candidate with its confidence', () => {
  const { prompt } = buildReconcilerPrompt({
    rawText: 'x',
    candidatesByField: {
      rating: [
        { agent: 'extract_a', value: '4.5', confidence: 0.9 },
        { agent: 'rules', value: '4.5', confidence: 1.0 },
      ],
    },
  });
  assert.ok(prompt.includes('extract_a="4.5" (conf 0.9)'));
  assert.ok(prompt.includes('rules="4.5" (conf 1)'));
});

test('parseExtractResponse maps camelCase wire keys to adjudicate.js snake_case fields', () => {
  const text = JSON.stringify({
    roaster: { value: 'DAK', confidence: 0.9, evidence: 'bag says DAK' },
    rating: { value: '4.5/5' },
    descFarmLot: { start: 3, end: 20, confidence: 0.8 },
  });
  const fields = parseExtractResponse(text);
  assert.deepEqual(fields.roaster_id, { value: 'DAK', confidence: 0.9, evidence: 'bag says DAK' });
  assert.equal(fields.rating.confidence, 0.8); // default when the model omits confidence
  assert.deepEqual(fields.desc_farm_lot.value, { start: 3, end: 20 });
});

test('parseExtractResponse omits an empty/absent field rather than inventing a null candidate', () => {
  const fields = parseExtractResponse(JSON.stringify({ roaster: { value: '' } }));
  assert.ok(!('roaster_id' in fields));
});

test('parseExtractResponse returns {} on unparseable JSON rather than throwing', () => {
  assert.deepEqual(parseExtractResponse('not json'), {});
});

test('parseCriticResponse maps verdicts by field, defaulting refuted to false', () => {
  const verdicts = parseCriticResponse(JSON.stringify({ roaster: { reason: 'looks fine' } }));
  assert.equal(verdicts.roaster_id.refuted, false);
  assert.equal(verdicts.roaster_id.reason, 'looks fine');
});

test('FIELD_KEY_MAP covers every adjudicate.js field used by the coffees column mapping', () => {
  const expected = [
    'roaster_id',
    'origin_country_ids',
    'origin_farm_id',
    'altitude',
    'price',
    'weight_g',
    'rating',
    'roasted_on',
    'profile',
    'desc_farm_lot',
    'desc_brew_guide',
    'desc_roaster_copy',
  ];
  assert.deepEqual(Object.values(FIELD_KEY_MAP).sort(), [...expected].sort());
});

test('estimateCostUsd uses per-model rates and counts thinking tokens as output', () => {
  const pro = estimateCostUsd('gemini-2.5-pro', { promptTokenCount: 1_000_000, candidatesTokenCount: 0, thoughtsTokenCount: 1_000_000 });
  assert.equal(pro, 1.25 + 10); // 1M input @ $1.25/MTok + 1M "output" (thinking) @ $10/MTok
  assert.equal(estimateCostUsd('unknown-model', { promptTokenCount: 1000 }), 0);
  assert.equal(estimateCostUsd('gemini-2.5-pro', null), 0);
});
