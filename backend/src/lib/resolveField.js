// A human decision applied to one (photo, field) pair -- shared by the review
// resolve route (`routes/review.js`) and the generic edit endpoint (PLAN.md
// §12 #40, `routes/coffees.js`). Both write the exact same
// `locked`/`decided_by='human'` field_resolutions row so no later
// adjudication pass -- including the monthly incremental run -- ever
// silently undoes either kind of human decision (PLAN.md §1).
import { query } from '../db.js';
import { canonicalize, denormalize } from './adjudicate.js';
import { normalizeVocabString, parsePrice } from './normalize.js';

// A human typing a bare number for price (e.g. "95" via the review "Other…"
// box) knows the currency in their head; default it rather than 422. The corpus
// is RON-dominant and such amounts sit squarely in RON range (95 EUR/GBP for a
// bag is absurd), so RON is the safe default; type "95 eur" to override. Only
// the human resolve/edit path reaches resolveField — the automated extraction
// pipeline never does — so this never makes the pipeline guess a currency.
const DEFAULT_PRICE_CURRENCY = (process.env.DEFAULT_PRICE_CURRENCY || 'RON').trim();

// The app's review UI (ReviewField, ios/.../Features/Review) only understands
// these fields; map each DB field name onto the client enum's raw value.
// `roaster_country_id` is intentionally absent here: it's derived from the
// roaster during normal extraction and has no review card of its own --
// EDIT_FIELD_TO_CLIENT below is the superset the generic edit endpoint uses.
export const FIELD_TO_CLIENT = {
  origin_country_ids: 'originCountry',
  roaster_id: 'roaster',
  origin_farm_id: 'farm',
  profile: 'profile',
  altitude: 'altitude',
  weight_g: 'weight',
  price: 'price',
};

// The generic edit endpoint (#40) can touch any core field, not just the ones
// the review feed's card UI knows how to render -- rating, roasted_on, and a
// direct roaster-country edit all have a dedicated control in #42's edit
// sheet, so they're editable even though `POST /api/review/:id` never surfaces
// them as a review item.
export const EDIT_FIELD_TO_CLIENT = {
  ...FIELD_TO_CLIENT,
  roaster_country_id: 'roasterCountry',
  rating: 'rating',
  roasted_on: 'roastedOn',
};

// Fields whose stored value is a structured/id shape, not a bare string: a
// human's accepted value must be canonicalised back into that shape before it
// can be written, or it would corrupt the coffees row.
export const STRUCTURED_FIELDS = new Set([
  'roaster_id', 'origin_farm_id', 'origin_country_ids', 'roaster_country_id',
  'altitude', 'price', 'weight_g', 'rating', 'roasted_on', 'profile',
]);

// Countries stay a closed set (PLAN.md §11 #36), but farms and roasters are
// inherently open-ended -- 0 farms are seeded, and new roasters appear over a
// ten-year corpus. When a human accepts/enters a name `canonicalize()` can't
// resolve, that's an explicit confirmation, so create the vocab row (plus an
// alias so every future import resolves it for free) instead of 422ing.
export const VOCAB_GET_OR_CREATE = {
  roaster_id: { table: 'roasters', aliasTable: 'roaster_aliases', aliasFk: 'roaster_id', slugged: true },
  origin_farm_id: { table: 'farms', aliasTable: 'farm_aliases', aliasFk: 'farm_id', slugged: false },
};

// Exported for tests only -- the rest of getOrCreateVocabEntry needs a live DB.
export function slugify(name) {
  return String(name).trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'roaster';
}

async function insertAlias(spec, id, rawName, aliasNorm) {
  await query(
    `INSERT INTO ${spec.aliasTable} (${spec.aliasFk}, alias, alias_norm) VALUES ($1, $2, $3)
     ON CONFLICT (alias_norm) DO NOTHING`,
    [id, rawName, aliasNorm],
  );
}

export async function getOrCreateVocabEntry(field, rawName) {
  const spec = VOCAB_GET_OR_CREATE[field];
  const aliasNorm = normalizeVocabString(rawName);
  if (!spec || !aliasNorm) return null;

  if (!spec.slugged) {
    // Check for an existing alias first -- farms have no uniqueness
    // constraint on `name` itself (unlike roasters' `slug`), so without this
    // check the same new farm name mentioned across several photos in one
    // worker batch (a single long-lived `sharedCtx.vocab.farms` snapshot,
    // PLAN.md §11 #44) would insert a duplicate `farms` row per mention --
    // only the first's alias insert would stick, and the rest would
    // silently no-op on the alias table's `alias_norm` uniqueness, leaving
    // orphan duplicate farms each still wired up to a real coffee.
    const { rows: existing } = await query(
      `SELECT ${spec.aliasFk} AS id FROM ${spec.aliasTable} WHERE alias_norm = $1`,
      [aliasNorm],
    );
    if (existing[0]) return existing[0].id;
    const { rows } = await query(`INSERT INTO farms (name) VALUES ($1) RETURNING id`, [rawName]);
    await insertAlias(spec, rows[0].id, rawName, aliasNorm);
    return rows[0].id;
  }

  const slugBase = slugify(rawName);
  for (let attempt = 0; attempt < 10; attempt++) {
    const slug = attempt === 0 ? slugBase : `${slugBase}-${attempt + 1}`;
    const { rows } = await query(
      `INSERT INTO roasters (name, slug) VALUES ($1, $2) ON CONFLICT (slug) DO NOTHING RETURNING id`,
      [rawName, slug],
    );
    if (rows[0]) {
      await insertAlias(spec, rows[0].id, rawName, aliasNorm);
      return rows[0].id;
    }
  }
  return null;
}

// Canonicalise a human-provided raw value for `field` and write a locked
// field_resolutions row -- everything `POST /api/review/:id`'s resolve branch
// and the generic edit endpoint both need, minus whatever's specific to their
// own request shape (a review-item lookup vs. a coffee lookup). Returns
// `{ value }` on success or `{ error }` when the value can't be resolved
// (caller decides the HTTP status -- always 422 today).
export async function resolveField(photoId, field, rawValue, ctx) {
  let value = rawValue;
  if (STRUCTURED_FIELDS.has(field)) {
    let canonical = canonicalize(field, value, ctx);
    if (!canonical && VOCAB_GET_OR_CREATE[field]) {
      // A human explicitly accepting/entering this name IS the confirmation
      // (PLAN.md §11 #36) -- get-or-create instead of 422ing. Countries have
      // no entry in VOCAB_GET_OR_CREATE, so an unknown country still 422s.
      const newId = await getOrCreateVocabEntry(field, String(value));
      if (newId != null) canonical = { id: newId, confidenceFactor: 1 };
    }
    // Bare human-entered price with no currency marker -> assume the default
    // currency instead of refusing (see DEFAULT_PRICE_CURRENCY above).
    if (!canonical && field === 'price') {
      const p = parsePrice(value);
      if (p && p.amount != null && p.currency == null) {
        canonical = { amount: p.amount, currency: DEFAULT_PRICE_CURRENCY, confidenceFactor: 0.9 };
      }
    }
    if (!canonical) return { error: 'unresolvable_value' };
    value = denormalize(field, canonical);
  }

  // `locked = true`, `decided_by = 'human'` -- PLAN.md §1's single most
  // important invariant: no later adjudication pass touches this field again.
  await query(
    `INSERT INTO field_resolutions (photo_id, field, value, confidence, agreement, voters, decided_by, locked)
     VALUES ($1, $2, $3, 1, 1, '{human}', 'human', true)
     ON CONFLICT (photo_id, field) DO UPDATE SET
       value = EXCLUDED.value, confidence = 1, agreement = 1, voters = '{human}',
       decided_by = 'human', locked = true, decided_at = now()`,
    [photoId, field, JSON.stringify(value)],
  );

  return { value };
}
