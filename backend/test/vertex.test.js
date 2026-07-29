// isConfigured() must agree with loadCredentials() about which credential
// shapes are usable (issue #33) — both the individual GOOGLE_* vars and a
// full service-account JSON pasted into GOOGLE_PRIVATE_KEY.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { config } from '../src/config.js';
import { isConfigured } from '../src/vertex.js';

function withVertexConfig(overrides, fn) {
  const original = { ...config.vertex };
  Object.assign(config.vertex, { projectId: '', serviceAccountEmail: '', privateKey: '' }, overrides);
  try {
    return fn();
  } finally {
    Object.assign(config.vertex, original);
  }
}

test('isConfigured() is false with nothing set', () => {
  withVertexConfig({}, () => {
    assert.equal(isConfigured(), false);
  });
});

test('isConfigured() is true with the three individual GOOGLE_* vars', () => {
  withVertexConfig(
    { projectId: 'proj', serviceAccountEmail: 'sa@proj.iam.gserviceaccount.com', privateKey: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----' },
    () => {
      assert.equal(isConfigured(), true);
    },
  );
});

test('isConfigured() is true with a full service-account JSON in GOOGLE_PRIVATE_KEY', () => {
  const json = JSON.stringify({
    project_id: 'proj-from-json',
    client_email: 'sa@proj.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
  });
  withVertexConfig({ privateKey: json }, () => {
    assert.equal(isConfigured(), true);
  });
});

test('isConfigured() is false when the JSON shape is missing private_key', () => {
  const json = JSON.stringify({ project_id: 'proj', client_email: 'sa@proj.iam.gserviceaccount.com' });
  withVertexConfig({ privateKey: json }, () => {
    assert.equal(isConfigured(), false);
  });
});

test('isConfigured() is false when only privateKey is set (individual-var shape)', () => {
  withVertexConfig({ privateKey: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----' }, () => {
    assert.equal(isConfigured(), false);
  });
});
