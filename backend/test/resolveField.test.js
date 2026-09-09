// resolveField() itself needs a live Postgres (it writes field_resolutions),
// same as every other DB-touching helper in worker.js/review.js -- not part
// of this committed suite. What's pure -- the field-name maps the generic
// edit endpoint (PLAN.md §12 #40) and the review feed both key off of -- is
// unit-tested here without any DB.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIELD_TO_CLIENT, EDIT_FIELD_TO_CLIENT, STRUCTURED_FIELDS } from '../src/lib/resolveField.js';
import { canonicalize } from '../src/lib/adjudicate.js';

test('EDIT_FIELD_TO_CLIENT is a strict superset of the review feed\'s FIELD_TO_CLIENT', () => {
  for (const [dbField, clientField] of Object.entries(FIELD_TO_CLIENT)) {
    assert.equal(EDIT_FIELD_TO_CLIENT[dbField], clientField);
  }
});

test('EDIT_FIELD_TO_CLIENT adds the edit-only fields the review feed deliberately excludes', () => {
  assert.equal(EDIT_FIELD_TO_CLIENT.roaster_country_id, 'roasterCountry');
  assert.equal(EDIT_FIELD_TO_CLIENT.rating, 'rating');
  assert.equal(EDIT_FIELD_TO_CLIENT.roasted_on, 'roastedOn');
  assert.equal(FIELD_TO_CLIENT.roaster_country_id, undefined);
  assert.equal(FIELD_TO_CLIENT.rating, undefined);
});

// A bare free-text edit field (its stored value IS the string) must NOT be in
// STRUCTURED_FIELDS — resolveField writes it verbatim, skipping canonicalize.
// Structured-shaped fields (ids, {min,max}, {amount,currency}, …) MUST be, or a
// raw string would be written into a column expecting a shape and corrupt it.
const FREE_TEXT_EDIT_FIELDS = new Set(['flavor_notes']);

test('every EDIT_FIELD_TO_CLIENT key that denormalizes to a structured shape is in STRUCTURED_FIELDS', () => {
  for (const dbField of Object.keys(EDIT_FIELD_TO_CLIENT)) {
    if (FREE_TEXT_EDIT_FIELDS.has(dbField)) {
      assert.ok(!STRUCTURED_FIELDS.has(dbField), `${dbField} is free text and must not be structured`);
      continue;
    }
    assert.ok(STRUCTURED_FIELDS.has(dbField), `${dbField} should be structured`);
  }
});

// --- the shape contract the get-or-create branch depends on (2026-09-09) ---
//
// `resolveField` fires get-or-create on `canonical?.id == null`, not on
// `!canonical`, and this is why. An unknown ROASTER canonicalizes to null, but
// an unknown FARM canonicalizes to a TRUTHY carrier `{id: null, name}` so that
// voters proposing the same new farm still cluster. Farms are the only
// 0-seeded vocab, so they are exactly the field that needs get-or-create most
// -- and the old `!canonical` test skipped them: an edit setting a new farm
// wrote a human-locked resolution with a null id, stored `origin_farm_id =
// NULL`, and returned 200. Caught setting Sopacdi on #165's Congo coffee.
//
// If either shape below changes, revisit that condition.
test('an unknown farm canonicalizes to a truthy carrier with a null id, not to null', () => {
  const ctx = { vocab: { farms: { candidates: [], aliasIndex: new Map() } } };
  const canonical = canonicalize('origin_farm_id', 'Sopacdi', ctx);

  assert.ok(canonical, 'farm canonicalize must stay truthy so voters cluster on a new name');
  assert.equal(canonical.id, null);
  assert.equal(canonical.name, 'Sopacdi');
  // The condition resolveField actually uses.
  assert.ok(canonical?.id == null, 'get-or-create must fire for this shape');
});

test('an unknown roaster canonicalizes to null, and the same condition still fires', () => {
  const ctx = { vocab: { roasters: { candidates: [], aliasIndex: new Map() } } };
  const canonical = canonicalize('roaster_id', 'Some Roaster That Does Not Exist', ctx);

  assert.equal(canonical, null);
  assert.ok(canonical?.id == null, 'optional chaining must keep null working too');
});

test('a farm name that is only whitespace canonicalizes to null, so nothing is created', () => {
  const ctx = { vocab: { farms: { candidates: [], aliasIndex: new Map() } } };
  assert.equal(canonicalize('origin_farm_id', '   ', ctx), null);
});
