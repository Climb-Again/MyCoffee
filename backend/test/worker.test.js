// worker.js's DB-touching orchestration (claim/lease, process a photo,
// run the SIGTERM-safe loop) needs a live Postgres, same as the manual
// end-to-end verification done for #19/#21 (see status/backend.md) -- it
// isn't part of this committed suite because CI has no DATABASE_URL
// (railway-deploy.yml's test job only runs `npm test` with none set, same as
// every other backend/test/*.test.js file). What's pure -- input_sha hashing,
// the extraction-due predicate, and the field-to-coffees-column mapping --
// is fully unit-tested here without any DB.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  computeInputSha,
  isDueForExtraction,
  shouldUseImage,
  buildCoffeeColumnUpdates,
  buildSearchBlobs,
  lightVoters,
  pickRawExtractedValue,
  runLightExtraction,
  buildFlavorNotesText,
} from '../src/lib/worker.js';

test('computeInputSha is deterministic and content-derived, not photo-id-derived', () => {
  const opts = {
    agent: 'extract_a',
    provider: 'vertex',
    model: 'gemini-2.5-pro',
    promptVersion: 'v1',
    imageSha: 'aaa',
    textSha: 'bbb',
    vocabVersion: 1,
  };
  assert.equal(computeInputSha(opts), computeInputSha({ ...opts }));
  assert.notEqual(computeInputSha(opts), computeInputSha({ ...opts, textSha: 'ccc' }));
  assert.notEqual(computeInputSha(opts), computeInputSha({ ...opts, vocabVersion: 2 }));
});

test('isDueForExtraction: a processed photo is never due again', () => {
  assert.equal(isDueForExtraction({ has_image: true, state: 'processed' }), false);
});

test('isDueForExtraction: no image yet is never due', () => {
  assert.equal(isDueForExtraction({ has_image: false, state: 'text_received' }), false);
});

test('isDueForExtraction: text_received with an image is due immediately', () => {
  assert.equal(isDueForExtraction({ has_image: true, state: 'text_received' }), true);
});

test('isDueForExtraction: awaiting_text is due only once the 10-day deadline passes', () => {
  const now = new Date('2026-01-15T00:00:00Z');
  const notYet = { has_image: true, state: 'awaiting_text', text_wait_until: '2026-01-20T00:00:00Z' };
  const overdue = { has_image: true, state: 'awaiting_text', text_wait_until: '2026-01-10T00:00:00Z' };
  assert.equal(isDueForExtraction(notYet, now), false);
  assert.equal(isDueForExtraction(overdue, now), true);
});

test('shouldUseImage: text_received respects the job-level includeImages flag', () => {
  assert.equal(shouldUseImage({ state: 'text_received' }, false), false);
  assert.equal(shouldUseImage({ state: 'text_received' }, true), true);
});

test('shouldUseImage: awaiting_text always uses its image, even in a text-only job (#69)', () => {
  assert.equal(shouldUseImage({ state: 'awaiting_text' }, false), true);
  assert.equal(shouldUseImage({ state: 'awaiting_text' }, true), true);
});

const vocabCtx = {
  vocab: {
    roasters: { candidates: [{ id: 1, name: 'DAK', country_id: 5 }] },
    countries: {
      candidates: [
        { id: 10, name: 'Ethiopia', is_origin: true },
        { id: 99, name: 'Blend', is_origin: true, kind: 'pseudo' },
      ],
    },
  },
  profileIdBySlug: new Map([['washed', 2]]),
  fxRates: [{ currency: 'RON', period: '2020-05-01', rateToEur: 0.2 }],
  photoDate: '2020-05-15',
};

test('buildCoffeeColumnUpdates: a bare-scalar field decided "absent" explicitly retracts the column (#49)', () => {
  // Regression for #49: re-adjudication can flip a field from a stale prior
  // `accepted` to `absent` (e.g. #39's new altitude/weight/rating sanity
  // envelopes rejecting a value a previous, looser pass had accepted). The
  // column must be SET to NULL, not silently left holding the old value.
  const { sets, values } = buildCoffeeColumnUpdates(
    { rating: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['rating = $1']);
  assert.deepEqual(values, [null]);
});

test('buildCoffeeColumnUpdates: flavor_notes writes the bare string to the column (#79 edit path)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { flavor_notes: { decision: 'accepted', value: 'dark chocolate, cherry, dried plum' } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['flavor_notes = $1']);
  assert.deepEqual(values, ['dark chocolate, cherry, dried plum']);
});

test('buildCoffeeColumnUpdates: flavor_notes decided "absent" retracts the column (#79)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { flavor_notes: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['flavor_notes = $1']);
  assert.deepEqual(values, [null]);
});

test('buildFlavorNotesText: short text passes through unchanged, joined title/caption/description (#90)', () => {
  const text = buildFlavorNotesText({
    title: 'Bag front',
    caption: 'A lovely light roast',
    description: 'Notes: blackberry, nougat, silky.',
  });
  assert.equal(text, 'Bag front\n\nA lovely light roast\n\nNotes: blackberry, nougat, silky.');
});

test('buildFlavorNotesText: no OCR block, missing fields are skipped (#90)', () => {
  const text = buildFlavorNotesText({ title: null, caption: 'Only a caption', description: null });
  assert.equal(text, 'Only a caption');
});

test('buildFlavorNotesText: empty input returns an empty string (#90)', () => {
  assert.equal(buildFlavorNotesText(), '');
  assert.equal(buildFlavorNotesText({}), '');
});

test('buildFlavorNotesText: caps a long caption/description head, still includes the OCR block (#90)', () => {
  const longCaption = 'x'.repeat(5000);
  const ocrBlock = 'OCR text\n' + 'Tasting notes: dark chocolate, cherry, dried plum.';
  const text = buildFlavorNotesText({ title: null, caption: longCaption, description: ocrBlock });

  // The pre-OCR head (title+caption+preOcr) is capped, so the raw 5000-char
  // caption never reaches the model in full.
  assert.ok(text.length < 5000 + ocrBlock.length);
  // The OCR block -- where a bag's printed notes usually are -- survives the cap.
  assert.ok(text.includes('Tasting notes: dark chocolate, cherry, dried plum.'));
});

test('buildFlavorNotesText: caps a long OCR block to its own head, independent of the caption cap (#90)', () => {
  const caption = 'Short caption';
  const longOcrBody = 'Tasting notes: dark chocolate. ' + 'filler '.repeat(2000);
  const description = `OCR text\n${longOcrBody}`;
  const text = buildFlavorNotesText({ title: null, caption, description });

  assert.ok(text.includes('Short caption'));
  assert.ok(text.includes('OCR text\nTasting notes: dark chocolate.'));
  // The OCR body itself is capped well below its ~14K raw length.
  assert.ok(text.length < 3500);
});

test('buildFlavorNotesText: preserves prior raw_description text ahead of an appended OCR block (#90)', () => {
  const description = 'Existing Instagram caption text.\n\nOCR text\nBag-printed: cherry, floral.';
  const text = buildFlavorNotesText({ title: null, caption: null, description });
  assert.equal(text, 'Existing Instagram caption text.\n\nOCR text\nBag-printed: cherry, floral.');
});

test('buildCoffeeColumnUpdates: altitude decided "absent" retracts both min and max (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { altitude: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['altitude_min_m = $1', 'altitude_max_m = $2']);
  assert.deepEqual(values, [null, null]);
});

test('buildCoffeeColumnUpdates: weight_g decided "absent" retracts the column (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { weight_g: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['weight_g = $1']);
  assert.deepEqual(values, [null]);
});

test('buildCoffeeColumnUpdates: price decided "absent" retracts all five price columns, no EUR conversion attempted (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { price: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, [
    'price_original_amount = $1',
    'price_original_currency = $2',
    'price_eur = $3',
    'fx_rate = $4',
    'fx_rate_period = $5',
  ]);
  assert.deepEqual(values, [null, null, null, null, null]);
});

test('buildCoffeeColumnUpdates: roaster_id decided "absent" retracts both roaster_id and its derived country (#49)', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { roaster_id: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [null, null]);
});

test('buildCoffeeColumnUpdates: origin_country_ids decided "absent" retracts to the column\'s own NOT NULL defaults, not NULL (#49)', () => {
  // coffees.origin_country_ids/is_blend are NOT NULL DEFAULT '{}'/false
  // (008_coffees.sql) -- an UPDATE ... SET origin_country_ids = NULL violates
  // that constraint outright (caught live against production, not just by a
  // unit test: POST /api/admin/adjudicate 500'd with exactly this error the
  // first time this fix shipped).
  const { sets, values } = buildCoffeeColumnUpdates(
    { origin_country_ids: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['origin_country_ids = $1', 'is_blend = $2']);
  assert.deepEqual(values, [[], false]);
});

test('buildCoffeeColumnUpdates: profile decided "absent" retracts is_decaf to its NOT NULL default (false), profile_id/profile_detail to NULL (#49)', () => {
  // is_decaf is NOT NULL DEFAULT false (008_coffees.sql); profile_id and
  // profile_detail are plain nullable columns, so those two retract to NULL.
  const { sets, values } = buildCoffeeColumnUpdates(
    { profile: { decision: 'absent', value: null } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['profile_id = $1', 'profile_detail = $2', 'is_decaf = $3']);
  assert.deepEqual(values, [null, null, false]);
});

test('buildCoffeeColumnUpdates: a field that was never voted on this pass is not a key in resolutions at all, and stays untouched', () => {
  // This is the OTHER half of #49's distinction -- a field absent from
  // `resolutions` entirely (no candidates were ever stored for it, e.g. the
  // caption never mentioned weight) must not be confused with a field
  // present with `decision: 'absent'`. Passing an empty resolutions object
  // models that case directly: nothing gets set.
  const { sets, values } = buildCoffeeColumnUpdates({}, vocabCtx);
  assert.deepEqual(sets, []);
  assert.deepEqual(values, []);
});

test('buildCoffeeColumnUpdates applies a "split" decision\'s provisional value too -- it is not skipped', () => {
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'split', value: 1 } }, vocabCtx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: roaster_id also denormalizes the roaster\'s country', () => {
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'accepted', value: 1 } }, vocabCtx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: #51 a caption-stated roaster country beats the vocab-derived one', () => {
  // The Uncommon UK/NL bug (#48a/#48b): the vocab guessed UK (country 5, per
  // vocabCtx's roaster fixture), but the caption itself says "Olanda"
  // (Netherlands, id 35) -- that should win.
  const ctx = {
    ...vocabCtx,
    vocab: {
      ...vocabCtx.vocab,
      countries: {
        candidates: [
          { id: 5, name: 'United Kingdom', is_roaster: true },
          { id: 35, name: 'Netherlands', is_roaster: true },
        ],
        aliasIndex: new Map([['olanda', { id: 35, alias: 'Olanda' }]]),
      },
    },
    rawText: 'Prajitorie: Uncommon (Amsterdam, Olanda)',
  };
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'accepted', value: 1 } }, ctx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 35]);
});

test('buildCoffeeColumnUpdates: #51 falls back to the vocab-derived roaster country when the caption says nothing', () => {
  const ctx = {
    ...vocabCtx,
    vocab: {
      ...vocabCtx.vocab,
      countries: { candidates: [{ id: 5, name: 'United Kingdom', is_roaster: true }], aliasIndex: new Map() },
    },
    rawText: 'a caption that never names the roaster\'s own country',
  };
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'accepted', value: 1 } }, ctx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: #51 an ambiguous caption (two distinct roaster countries) also falls back to the vocab-derived one', () => {
  const ctx = {
    ...vocabCtx,
    vocab: {
      ...vocabCtx.vocab,
      countries: {
        candidates: [
          { id: 5, name: 'United Kingdom', is_roaster: true },
          { id: 35, name: 'Netherlands', is_roaster: true },
          { id: 40, name: 'Czech Republic', is_roaster: true },
        ],
        aliasIndex: new Map([
          ['olanda', { id: 35, alias: 'Olanda' }],
          ['cehia', { id: 40, alias: 'Cehia' }],
        ]),
      },
    },
    rawText: 'Roasted somewhere between Olanda and Cehia, not sure which',
  };
  const { sets, values } = buildCoffeeColumnUpdates({ roaster_id: { decision: 'accepted', value: 1 } }, ctx);
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 5]);
});

test('buildCoffeeColumnUpdates: roaster_country_id can be set directly, without a roaster_id edit', () => {
  // The generic edit endpoint (PLAN.md §12 #40) can edit the roaster's country
  // on its own, unlike normal extraction where it's only ever a side effect
  // of resolving roaster_id.
  const { sets, values } = buildCoffeeColumnUpdates(
    { roaster_country_id: { decision: 'accepted', value: 10 } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_country_id = $1']);
  assert.deepEqual(values, [10]);
});

test('buildCoffeeColumnUpdates: a later roaster_country_id resolution overrides roaster_id\'s derived one, not both', () => {
  // A batch edit (roaster + roaster country together, #42's edit sheet) must
  // never emit "roaster_country_id = $1, roaster_country_id = $2" -- Postgres
  // rejects multiple assignments to the same column. Object key order is the
  // tiebreak: the explicit roaster_country_id resolution, listed second here,
  // wins over roaster_id's derived one.
  const { sets, values } = buildCoffeeColumnUpdates(
    {
      roaster_id: { decision: 'accepted', value: 1 },
      roaster_country_id: { decision: 'accepted', value: 10 },
    },
    vocabCtx,
  );
  assert.deepEqual(sets, ['roaster_id = $1', 'roaster_country_id = $2']);
  assert.deepEqual(values, [1, 10]);
});

test('buildCoffeeColumnUpdates: origin_country_ids also computes is_blend and drops invalid ids', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { origin_country_ids: { decision: 'accepted', value: [10, 12345] } }, // 12345 isn't a real country id
    vocabCtx,
  );
  assert.deepEqual(sets, ['origin_country_ids = $1', 'is_blend = $2']);
  assert.deepEqual(values[0], [10]);
  assert.equal(values[1], false);
});

test('buildCoffeeColumnUpdates: price converts to EUR using the purchase-date rate, not a flat rate', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { price: { decision: 'accepted', value: { amount: 45, currency: 'RON' } } },
    vocabCtx,
  );
  assert.deepEqual(sets, [
    'price_original_amount = $1',
    'price_original_currency = $2',
    'price_eur = $3',
    'fx_rate = $4',
    'fx_rate_period = $5',
  ]);
  assert.equal(values[0], 45);
  assert.equal(values[1], 'RON');
  assert.equal(values[2], 9); // 45 * 0.2
});

test('buildCoffeeColumnUpdates: profile writes id (via slug lookup), detail, and is_decaf together', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { profile: { decision: 'accepted', value: { profileId: 'washed', isDecaf: false, detail: null } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['profile_id = $1', 'profile_detail = $2', 'is_decaf = $3']);
  assert.deepEqual(values, [2, null, false]);
});

test('buildCoffeeColumnUpdates: altitude writes both min and max', () => {
  const { sets, values } = buildCoffeeColumnUpdates(
    { altitude: { decision: 'accepted', value: { min: 1300, max: 1600 } } },
    vocabCtx,
  );
  assert.deepEqual(sets, ['altitude_min_m = $1', 'altitude_max_m = $2']);
  assert.deepEqual(values, [1300, 1600]);
});

// #56 -- search_labels_blob/search_prose_blob were declared in 009_search.sql
// but nothing ever wrote them.
const searchCtx = {
  vocab: {
    roasters: { candidates: [{ id: 1, name: 'DAK' }] },
    countries: {
      candidates: [
        { id: 5, name: 'Netherlands' },
        { id: 10, name: 'Ethiopia' },
        { id: 11, name: 'Panamá' },
      ],
    },
    farms: { candidates: [{ id: 7, name: 'Finca El Diamante' }] },
  },
  profileNameById: new Map([[2, 'Washed']]),
};

test('buildSearchBlobs: labels blob folds in roaster, roaster country, every origin, farm, profile name + detail', () => {
  const { labelsBlob } = buildSearchBlobs(
    {
      roaster_id: 1,
      roaster_country_id: 5,
      origin_country_ids: [10, 11],
      origin_farm_id: 7,
      profile_id: 2,
      profile_detail: 'Yellow Honey',
    },
    searchCtx,
  );
  assert.equal(labelsBlob, 'DAK Netherlands Ethiopia Panama Finca El Diamante Washed Yellow Honey');
});

test('buildSearchBlobs: prose blob joins raw title/caption/description, diacritic-folded', () => {
  const { proseBlob } = buildSearchBlobs(
    { raw_title: 'Prăjitorie Uncommon', raw_caption: 'Cafea din Panamá', raw_description: null },
    searchCtx,
  );
  assert.equal(proseBlob, 'Prajitorie Uncommon Cafea din Panama');
});

test('buildSearchBlobs: an unresolved id or missing vocab entry is skipped, not "undefined"', () => {
  const { labelsBlob, proseBlob } = buildSearchBlobs(
    { roaster_id: 999, origin_country_ids: [], raw_title: null, raw_caption: null, raw_description: null },
    searchCtx,
  );
  assert.equal(labelsBlob, '');
  assert.equal(proseBlob, '');
});

test('buildSearchBlobs: a coffee with nothing resolved yet produces empty blobs, not a crash', () => {
  const { labelsBlob, proseBlob } = buildSearchBlobs({}, {});
  assert.equal(labelsBlob, '');
  assert.equal(proseBlob, '');
});

// ---- #75 (Add Coffee wizard) — the light-ensemble extraction path ----

test('lightVoters: extract_b + reconciler only, no extract_a and no critic', async () => {
  const voters = await lightVoters();
  const agents = voters.map((v) => v.agent);
  assert.ok(agents.includes('extract_b'));
  assert.ok(agents.includes('reconciler'));
  assert.ok(!agents.includes('extract_a'));
  assert.ok(!agents.includes('critic'));
});

test('pickRawExtractedValue: prefers the reconciler\'s raw value over other voters\'', () => {
  const candidatesByField = {
    roaster_id: [
      { agent: 'extract_b', value: 'Concept Coffee', confidence: 0.8 },
      { agent: 'reconciler', value: 'Concept Coffee Roasters', confidence: 0.9 },
    ],
  };
  assert.equal(pickRawExtractedValue('roaster_id', candidatesByField), 'Concept Coffee Roasters');
});

test('pickRawExtractedValue: falls back to the first candidate when no reconciler answered', () => {
  const candidatesByField = { weight_g: [{ agent: 'rules', value: '250g', confidence: 1 }] };
  assert.equal(pickRawExtractedValue('weight_g', candidatesByField), '250g');
});

test('pickRawExtractedValue: null for a field nothing proposed', () => {
  assert.equal(pickRawExtractedValue('rating', {}), null);
  assert.equal(pickRawExtractedValue('rating', { rating: [] }), null);
});

test('runLightExtraction: aggregates candidates across injected voters, adjudicates, and sums cost', async () => {
  const fakeVoters = [
    {
      agent: 'extract_b',
      run: async () => ({ fields: { rating: { value: '4.5', confidence: 0.9 }, weight_g: { value: '250g', confidence: 0.9 } }, costUsd: 0.01 }),
    },
    {
      agent: 'reconciler',
      run: async () => ({ fields: { rating: { value: '4.5', confidence: 0.95 } }, costUsd: 0.02 }),
    },
  ];

  const { resolutions, candidatesByField, spentUsd } = await runLightExtraction({
    rawText: 'Great coffee, 4.5/5, 250gr bag',
    images: [],
    vocabShortlist: [],
    voters: fakeVoters,
    vocab: {},
  });

  assert.equal(spentUsd, 0.03);
  assert.equal(candidatesByField.rating.length, 2);
  assert.equal(candidatesByField.weight_g.length, 1);
  // Both voters agreed on rating -> accepted, single-voter weight_g -> accepted too.
  assert.equal(resolutions.rating.decision, 'accepted');
  assert.equal(resolutions.rating.value, 4.5);
  assert.equal(resolutions.weight_g.value, 250);
});

test('runLightExtraction: a genuine cluster split still resolves (applied provisionally, decision "split")', async () => {
  const fakeVoters = [
    { agent: 'extract_b', run: async () => ({ fields: { rating: { value: '4', confidence: 0.9 } }, costUsd: 0 }) },
    { agent: 'reconciler', run: async () => ({ fields: { rating: { value: '5', confidence: 0.9 } }, costUsd: 0 }) },
  ];

  const { resolutions } = await runLightExtraction({
    rawText: '',
    images: [],
    vocabShortlist: [],
    voters: fakeVoters,
    vocab: {},
  });

  assert.equal(resolutions.rating.decision, 'split');
  assert.ok(resolutions.rating.value === 4 || resolutions.rating.value === 5);
});
