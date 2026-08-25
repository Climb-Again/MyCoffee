// resolveField() itself needs a live Postgres (it writes field_resolutions),
// same as every other DB-touching helper in worker.js/review.js -- not part
// of this committed suite. What's pure -- the field-name maps the generic
// edit endpoint (PLAN.md §12 #40) and the review feed both key off of -- is
// unit-tested here without any DB.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIELD_TO_CLIENT, EDIT_FIELD_TO_CLIENT, STRUCTURED_FIELDS } from '../src/lib/resolveField.js';

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
