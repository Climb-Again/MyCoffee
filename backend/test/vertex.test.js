// Since the Gemini Developer API migration (2026-08-16), auth is a single API
// key (GEMINI_API_KEY / GOOGLE_API_KEY → config.vertex.apiKey), so isConfigured()
// is just "is the key present". The old service-account credential shapes no
// longer apply.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { isConfigured, buildRequestBody, parseResponse } from '../src/vertex.js';

function withVertexConfig(overrides, fn) {
  const original = { ...config.vertex };
  Object.assign(config.vertex, { apiKey: '' }, overrides);
  try {
    return fn();
  } finally {
    Object.assign(config.vertex, original);
  }
}

test('isConfigured() is false when no API key is set', () => {
  withVertexConfig({ apiKey: '' }, () => {
    assert.equal(isConfigured(), false);
  });
});

test('isConfigured() is true when an API key is set', () => {
  withVertexConfig({ apiKey: 'AIza-test-key' }, () => {
    assert.equal(isConfigured(), true);
  });
});

// #23: request-body shaping, no network involved.

test('buildRequestBody() defaults to a text-only part with no schema/thinking config', () => {
  const body = buildRequestBody({ prompt: 'hello' });
  assert.deepEqual(body.contents, [{ role: 'user', parts: [{ text: 'hello' }] }]);
  assert.equal(body.generationConfig.maxOutputTokens, 8192);
  assert.equal(body.generationConfig.temperature, 0.7);
  assert.equal('responseMimeType' in body.generationConfig, false);
  assert.equal('responseSchema' in body.generationConfig, false);
  assert.equal('thinkingConfig' in body.generationConfig, false);
  assert.equal(body.systemInstruction, undefined);
});

test('buildRequestBody() carries system instruction when given', () => {
  const body = buildRequestBody({ prompt: 'hello', system: 'be terse' });
  assert.deepEqual(body.systemInstruction, { parts: [{ text: 'be terse' }] });
});

test('buildRequestBody() appends inline image parts after the text part, in order', () => {
  const images = [
    { mimeType: 'image/jpeg', dataBase64: 'aaa' },
    { mimeType: 'image/png', dataBase64: 'bbb' },
  ];
  const body = buildRequestBody({ prompt: 'describe this bag', images });
  assert.deepEqual(body.contents[0].parts, [
    { text: 'describe this bag' },
    { inlineData: { mimeType: 'image/jpeg', data: 'aaa' } },
    { inlineData: { mimeType: 'image/png', data: 'bbb' } },
  ]);
});

test('buildRequestBody() attaches responseSchema alongside responseMimeType', () => {
  const schema = { type: 'object', properties: { currency: { type: 'string', enum: ['EUR', 'RON'] } } };
  const body = buildRequestBody({ prompt: 'extract', responseSchema: schema });
  assert.equal(body.generationConfig.responseMimeType, 'application/json');
  assert.deepEqual(body.generationConfig.responseSchema, schema);
});

test('buildRequestBody() sets responseMimeType from json:true without a schema', () => {
  const body = buildRequestBody({ prompt: 'extract', json: true });
  assert.equal(body.generationConfig.responseMimeType, 'application/json');
  assert.equal('responseSchema' in body.generationConfig, false);
});

test('buildRequestBody() honours thinkingBudget, including 0 (thinking off)', () => {
  const off = buildRequestBody({ prompt: 'x', thinkingBudget: 0 });
  assert.deepEqual(off.generationConfig.thinkingConfig, { thinkingBudget: 0 });

  const withBudget = buildRequestBody({ prompt: 'x', thinkingBudget: 1024 });
  assert.deepEqual(withBudget.generationConfig.thinkingConfig, { thinkingBudget: 1024 });

  const omitted = buildRequestBody({ prompt: 'x' });
  assert.equal('thinkingConfig' in omitted.generationConfig, false);
});

test('buildRequestBody() keeps maxOutputTokens/temperature overridable', () => {
  const body = buildRequestBody({ prompt: 'x', maxOutputTokens: 16384, temperature: 0 });
  assert.equal(body.generationConfig.maxOutputTokens, 16384);
  assert.equal(body.generationConfig.temperature, 0);
});

test('parseResponse() extracts text, usage, and finishReason', () => {
  const data = {
    candidates: [
      {
        content: { parts: [{ text: 'foo' }, { text: 'bar' }] },
        finishReason: 'STOP',
      },
    ],
    usageMetadata: {
      promptTokenCount: 100,
      candidatesTokenCount: 50,
      thoughtsTokenCount: 200,
    },
  };
  const result = parseResponse(data);
  assert.equal(result.text, 'foobar');
  assert.equal(result.finishReason, 'STOP');
  assert.deepEqual(result.usage, {
    promptTokenCount: 100,
    candidatesTokenCount: 50,
    thoughtsTokenCount: 200,
  });
  assert.equal(result.raw, data);
});

test('parseResponse() surfaces MAX_TOKENS finishReason instead of hiding truncation', () => {
  const data = {
    candidates: [{ content: { parts: [{ text: 'partial' }] }, finishReason: 'MAX_TOKENS' }],
    usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 8192, thoughtsTokenCount: 0 },
  };
  const result = parseResponse(data);
  assert.equal(result.finishReason, 'MAX_TOKENS');
  assert.equal(result.text, 'partial');
});

test('parseResponse() handles a missing candidate/usage gracefully', () => {
  const result = parseResponse({});
  assert.equal(result.text, '');
  assert.equal(result.finishReason, undefined);
  assert.deepEqual(result.usage, {
    promptTokenCount: undefined,
    candidatesTokenCount: undefined,
    thoughtsTokenCount: undefined,
  });
});

// Regression: the first real extraction run failed on every photo with
// "The model does not support setting thinking_budget to 0". Cause was that
// generateContent ignored the caller's model and always used
// config.vertex.model (2.5-pro), so the voters labelled 2.5-flash — the only
// ones allowed to disable thinking — were actually sent to pro with
// thinkingBudget: 0. buildRequestBody must keep honouring an explicit 0 (it is
// a real cost saver on flash); the model selection and the pro guard live in
// generateContent, which needs the network. What is assertable here is that a
// 0 budget is still expressed faithfully for the flash case.
test('buildRequestBody keeps an explicit thinkingBudget of 0 (valid on flash)', () => {
  const body = buildRequestBody({ prompt: 'x', thinkingBudget: 0 });
  const cfg = body.generationConfig ?? {};
  assert.ok('thinkingConfig' in cfg, 'thinkingConfig should be present for an explicit 0');
  assert.equal(cfg.thinkingConfig.thinkingBudget, 0);
});

test('buildRequestBody omits thinkingConfig when no budget is given', () => {
  const body = buildRequestBody({ prompt: 'x' });
  const cfg = body.generationConfig ?? {};
  assert.ok(!('thinkingConfig' in cfg), 'no thinkingConfig unless asked for');
});

// Text-only mode (no image part) must still produce a valid request: the
// sample run extracts from the caption alone.
test('buildRequestBody with no images produces a text-only parts array', () => {
  const body = buildRequestBody({ prompt: 'caption text', images: [] });
  const parts = body.contents[0].parts;
  assert.equal(parts.length, 1);
  assert.ok(parts[0].text.includes('caption text'));
  assert.ok(!parts.some((p) => p.inlineData), 'no inlineData without images');
});
