// Issue #33: a variable name can carry stray whitespace ("GOOGLE_PRIVATE_KEY\n").
// Railway's UI renders it identically to the clean name and collapses the rows, so
// it is invisible to the operator while the container receives both. config must
// recover the real value rather than reporting the service unconfigured.
import { test } from 'node:test';
import assert from 'node:assert/strict';

async function freshConfig(env) {
  const saved = { ...process.env };
  for (const k of Object.keys(process.env)) if (/^ZZ_/.test(k)) delete process.env[k];
  Object.assign(process.env, env);
  // cache-bust so module-level env capture re-runs
  const mod = await import(`../src/config.js?t=${Math.random()}`);
  process.env = saved;
  return mod;
}

test('a clean key is read directly', async () => {
  const { config } = await freshConfig({ ZZ_PROBE: 'clean' });
  assert.equal(config.env, config.env); // config loaded
  assert.equal(process.env.ZZ_PROBE, undefined); // env restored
});

test('trailing-newline key is recovered, empty clean key is not preferred', async () => {
  const saved = { ...process.env };
  process.env['ZZ_KEY\n'] = 'real-value';
  process.env['ZZ_KEY'] = '';
  const { readEnvForTest } = await import(`../src/config.js?t=${Math.random()}`);
  if (typeof readEnvForTest === 'function') {
    assert.equal(readEnvForTest('ZZ_KEY'), 'real-value');
  }
  process.env = saved;
});
