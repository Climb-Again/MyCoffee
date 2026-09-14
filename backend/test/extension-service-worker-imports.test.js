// #194 regression — every module reachable from `background.js` runs inside
// the MV3 service worker, and service workers reject dynamic `import()` at
// runtime with a `TypeError` the calling try/catch will swallow. That is
// exactly how the shipped shortlist sync silently failed on every browser
// for a week: the write path threw, was caught, no user saw an error, and
// the server stayed empty.
//
// This test enumerates the service worker's static import graph and greps
// each module for `await import(` / `= import(`. Popup-only modules are not
// checked — popups run in a regular page context where dynamic imports work.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const extDir = path.dirname(fileURLToPath(new URL('../../extension/background.js', import.meta.url)));

// Only relative imports (`./…`); ignore extension-native URLs and bare names.
const IMPORT_RE = /import\s+(?:[^'"]+?\s+from\s+)?['"](\.\/[^'"]+)['"]/g;
const DYNAMIC_RE = /\b(?:await\s+)?import\s*\(/;

function readModule(rel) {
  return readFileSync(path.join(extDir, rel), 'utf8');
}

function staticImportsOf(rel) {
  const src = readModule(rel);
  const out = new Set();
  for (const m of src.matchAll(IMPORT_RE)) out.add(m[1]);
  return out;
}

function reachableFromServiceWorker() {
  const visited = new Set(['./background.js']);
  const queue = ['./background.js'];
  while (queue.length) {
    const rel = queue.shift();
    for (const dep of staticImportsOf(rel)) {
      if (visited.has(dep)) continue;
      visited.add(dep);
      queue.push(dep);
    }
  }
  return visited;
}

test('no module reachable from background.js uses a dynamic import()', () => {
  const modules = reachableFromServiceWorker();
  const offenders = [];
  for (const rel of modules) {
    const src = readModule(rel);
    // Ignore // and /* */ comments before matching, since our own comment
    // above explains the bug and would otherwise trip the check.
    const stripped = src
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .split('\n')
      .map((line) => line.replace(/\/\/.*$/, ''))
      .join('\n');
    if (DYNAMIC_RE.test(stripped)) offenders.push(rel);
  }
  assert.deepEqual(
    offenders,
    [],
    `dynamic import() in service-worker-reachable module(s): ${offenders.join(', ')}. ` +
      `MV3 service workers reject import() at runtime — use a static import instead.`,
  );
});

test('background.js pulls in history.js (guard against the graph shrinking silently)', () => {
  const modules = reachableFromServiceWorker();
  assert.ok(modules.has('./history.js'), 'history.js is no longer reachable from background.js — did the sync path move?');
});
