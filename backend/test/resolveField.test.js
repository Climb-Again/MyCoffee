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

test('every EDIT_FIELD_TO_CLIENT key that denormalizes to a structured shape is in STRUCTURED_FIELDS', () => {
  for (const dbField of Object.keys(EDIT_FIELD_TO_CLIENT)) {
    assert.ok(STRUCTURED_FIELDS.has(dbField), `${dbField} should be structured`);
  }
});
