// The "Brew lab" API (PLAN.md §14, backlog #155): a per-coffee tri-state
// checklist over four catalogues (recipe / device / grind / temp), with at most
// one winner per catalogue per coffee.
//
//   GET   /api/brew-options            requireAnyToken    every option, incl. archived
//   POST  /api/brew-options            requireIngestToken get-or-create a catalogue option
//   PATCH /api/brew-options/:id        requireIngestToken rename / re-value / archive
//   POST  /api/coffees/:publicId/brew  requireIngestToken set tri-state for one (coffee, option)
//
// A brew trial is a human display/preference field, not an extracted one — it
// mirrors POST /favorite and /rotation (no resolveField, no review queue); the
// `coffees.updated_at` bump carries it to every device via the delta sync.
import { requireAnyToken, requireIngestToken } from '../auth.js';
import { query, withTransaction } from '../db.js';
import { normalizeVocabString } from '../lib/normalize.js';
import { nextTrialRows, impliedTrials } from '../lib/brewState.js';

const BREW_KINDS = ['recipe', 'device', 'grind', 'temp'];
const BREW_STATES = ['untried', 'tried', 'best'];

// A brew_options row -> the client BrewOption shape. Recipe rows carry a nested
// `recipe` object (the six typed columns); non-recipe rows omit it.
function toBrewOption(row) {
  const opt = {
    id: row.id,
    kind: row.kind,
    label: row.label,
    detail: row.detail ?? null,
    valueNum: row.value_num != null ? Number(row.value_num) : null,
    sortOrder: row.sort_order,
    archived: row.archived_at != null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  if (row.kind === 'recipe') {
    opt.recipe = {
      doseG: row.dose_g != null ? Number(row.dose_g) : null,
      pours: row.pours,
      mlPerPour: row.ml_per_pour,
      totalWaterMl: row.total_water_ml,
      grindClicks: row.grind_clicks,
      waterTempC: row.water_temp_c,
    };
  }
  return opt;
}

// Every option in full (incl. archived), for `vocab.brewOptions` in the
// snapshot and for GET /api/brew-options. Defined here, not in lib/vocab.js
// (data-lane owned): the backend lane adds the loader only.
export async function loadBrewOptionVocab(queryFn) {
  const { rows } = await queryFn(
    `SELECT id, kind, label, label_norm, detail, value_num, dose_g, pours,
            ml_per_pour, total_water_ml, grind_clicks, water_temp_c,
            sort_order, archived_at, created_at, updated_at
     FROM brew_options
     ORDER BY kind, sort_order, value_num NULLS LAST, label`,
  );
  return rows.map(toBrewOption);
}

// grind/temp labels are server-generated from the value, so the client sends
// `valueNum` only and the same value always folds to the same label_norm.
function labelForValue(kind, valueNum) {
  if (kind === 'grind') return `${valueNum} clicks`;
  if (kind === 'temp') return `${valueNum} °C`;
  return null;
}

// temp: integer 60–100; grind: integer 1–60. Returns { value } or { error }.
function validateValueNum(kind, valueNum) {
  if (kind === 'temp') {
    if (!Number.isInteger(valueNum) || valueNum < 60 || valueNum > 100) {
      return { error: 'invalid_temperature' };
    }
    return { value: valueNum };
  }
  if (kind === 'grind') {
    if (!Number.isInteger(valueNum) || valueNum < 1 || valueNum > 60) {
      return { error: 'invalid_grind_clicks' };
    }
    return { value: valueNum };
  }
  return { value: null };
}

// A recipe body must be complete; `mlPerPour` is the only optional field, and
// when present `pours × mlPerPour` must be within ±5 % of `totalWaterMl` so the
// two can never silently disagree. Returns { value } or { error, field }.
function validateRecipe(recipe) {
  if (recipe == null || typeof recipe !== 'object') {
    return { error: 'invalid_recipe', field: 'recipe' };
  }
  const { doseG, pours, totalWaterMl, grindClicks, waterTempC } = recipe;
  const mlPerPour = recipe.mlPerPour ?? null;

  if (!(typeof doseG === 'number' && doseG > 0)) return { error: 'invalid_recipe', field: 'doseG' };
  if (!(Number.isInteger(pours) && pours >= 1 && pours <= 12)) return { error: 'invalid_recipe', field: 'pours' };
  if (!(Number.isInteger(totalWaterMl) && totalWaterMl > 0)) return { error: 'invalid_recipe', field: 'totalWaterMl' };
  if (!(Number.isInteger(grindClicks) && grindClicks >= 1 && grindClicks <= 60)) return { error: 'invalid_recipe', field: 'grindClicks' };
  if (!(Number.isInteger(waterTempC) && waterTempC >= 60 && waterTempC <= 100)) return { error: 'invalid_recipe', field: 'waterTempC' };

  if (mlPerPour != null) {
    if (!(Number.isInteger(mlPerPour) && mlPerPour > 0)) return { error: 'invalid_recipe', field: 'mlPerPour' };
    const implied = pours * mlPerPour;
    if (Math.abs(implied - totalWaterMl) > totalWaterMl * 0.05) {
      return { error: 'recipe_water_mismatch', field: 'mlPerPour' };
    }
  }
  return { value: { doseG, pours, mlPerPour, totalWaterMl, grindClicks, waterTempC } };
}

// get-or-create lookup: an option with the same (kind, label_norm) or, for
// grind/temp, the same (kind, value_num).
async function findExistingOption(queryFn, kind, labelNorm, valueNum) {
  const { rows } = await queryFn(
    `SELECT * FROM brew_options
     WHERE kind = $1 AND (label_norm = $2 OR ($3::numeric IS NOT NULL AND value_num = $3))
     LIMIT 1`,
    [kind, labelNorm, valueNum],
  );
  return rows[0] ?? null;
}

// get-or-create a grind/temp option by numeric value, inside a transaction —
// used by the recipe auto-tick to resolve "24 clicks" / "92 °C" by value.
async function getOrCreateNumericOption(client, kind, valueNum) {
  const label = labelForValue(kind, valueNum);
  const labelNorm = normalizeVocabString(label);
  const ins = await client.query(
    `INSERT INTO brew_options (kind, label, label_norm, value_num)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (kind, label_norm) DO NOTHING
     RETURNING *`,
    [kind, label, labelNorm, valueNum],
  );
  if (ins.rows[0]) return ins.rows[0];
  const sel = await client.query(
    `SELECT * FROM brew_options WHERE kind = $1 AND value_num = $2 LIMIT 1`,
    [kind, valueNum],
  );
  return sel.rows[0] ?? null;
}

// The whole brew state for one coffee: { brewTried:[int], brewBest:[int] }.
async function loadCoffeeBrewState(client, coffeeId) {
  const { rows } = await client.query(
    `SELECT
       coalesce(array_agg(option_id ORDER BY option_id), '{}')                        AS tried,
       coalesce(array_agg(option_id ORDER BY option_id) FILTER (WHERE is_best), '{}') AS best
     FROM coffee_brew_trials WHERE coffee_id = $1`,
    [coffeeId],
  );
  return { brewTried: rows[0].tried, brewBest: rows[0].best };
}

export default async function brewRoutes(app) {
  // Every option, including archived and recipe/grind/temp — the client needs
  // archived rows to render history greyed rather than dropping it.
  app.get('/api/brew-options', { preHandler: requireAnyToken }, async () => {
    const options = await loadBrewOptionVocab(query);
    return { options };
  });

  // get-or-create a catalogue option. 201 when created, 200 when an existing
  // row matches (dup label_norm within kind, or dup (kind, valueNum) for
  // grind/temp) — same "get-or-create" spirit as #36.
  app.post('/api/brew-options', { preHandler: requireIngestToken }, async (req, reply) => {
    const body = req.body ?? {};
    const kind = body.kind;
    if (!BREW_KINDS.includes(kind)) {
      return reply.code(400).send({ error: 'invalid_brew_kind', value: kind ?? null });
    }

    let label;
    let valueNum = null;
    let recipe = null;

    if (kind === 'grind' || kind === 'temp') {
      const v = validateValueNum(kind, body.valueNum);
      if (v.error) return reply.code(400).send({ error: v.error, value: body.valueNum ?? null });
      valueNum = v.value;
      label = labelForValue(kind, valueNum); // server-generated
    } else if (kind === 'recipe') {
      const r = validateRecipe(body.recipe);
      if (r.error) return reply.code(400).send({ error: r.error, field: r.field });
      recipe = r.value;
      label = typeof body.label === 'string' ? body.label.trim() : '';
      if (!label) return reply.code(400).send({ error: 'missing_label' });
    } else { // device
      label = typeof body.label === 'string' ? body.label.trim() : '';
      if (!label) return reply.code(400).send({ error: 'missing_label' });
    }

    const detail = typeof body.detail === 'string' && body.detail.trim() ? body.detail.trim() : null;
    const labelNorm = normalizeVocabString(label);

    const existing = await findExistingOption(query, kind, labelNorm, valueNum);
    if (existing) return reply.code(200).send(toBrewOption(existing));

    const { rows } = await query(
      `INSERT INTO brew_options (kind, label, label_norm, detail, value_num,
          dose_g, pours, ml_per_pour, total_water_ml, grind_clicks, water_temp_c)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (kind, label_norm) DO NOTHING
       RETURNING *`,
      [
        kind, label, labelNorm, detail, valueNum,
        recipe?.doseG ?? null, recipe?.pours ?? null, recipe?.mlPerPour ?? null,
        recipe?.totalWaterMl ?? null, recipe?.grindClicks ?? null, recipe?.waterTempC ?? null,
      ],
    );
    if (rows[0]) return reply.code(201).send(toBrewOption(rows[0]));

    // Lost a race (label_norm or the (kind,value_num) partial index) — re-fetch.
    const again = await findExistingOption(query, kind, labelNorm, valueNum);
    if (again) return reply.code(200).send(toBrewOption(again));
    return reply.code(409).send({ error: 'brew_option_conflict' });
  });

  // Rename / re-value / archive. A recipe object replaces all six recipe fields
  // (400 `not_a_recipe` unless the option's kind is recipe). Archive, never
  // delete — a trial always references a live or archived option.
  app.patch('/api/brew-options/:id', { preHandler: requireIngestToken }, async (req, reply) => {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isInteger(id)) return reply.code(400).send({ error: 'invalid_id' });

    const { rows: existRows } = await query('SELECT * FROM brew_options WHERE id = $1', [id]);
    const existing = existRows[0];
    if (!existing) return reply.code(404).send({ error: 'brew_option_not_found' });

    const body = req.body ?? {};
    const updates = {};

    if (body.recipe !== undefined) {
      if (existing.kind !== 'recipe') return reply.code(400).send({ error: 'not_a_recipe' });
      const r = validateRecipe(body.recipe);
      if (r.error) return reply.code(400).send({ error: r.error, field: r.field });
      updates.dose_g = r.value.doseG;
      updates.pours = r.value.pours;
      updates.ml_per_pour = r.value.mlPerPour;
      updates.total_water_ml = r.value.totalWaterMl;
      updates.grind_clicks = r.value.grindClicks;
      updates.water_temp_c = r.value.waterTempC;
    }

    if (body.valueNum !== undefined && (existing.kind === 'grind' || existing.kind === 'temp')) {
      const v = validateValueNum(existing.kind, body.valueNum);
      if (v.error) return reply.code(400).send({ error: v.error, value: body.valueNum });
      updates.value_num = v.value;
      updates.label = labelForValue(existing.kind, v.value);
      updates.label_norm = normalizeVocabString(updates.label);
    }

    if (body.label !== undefined && (existing.kind === 'device' || existing.kind === 'recipe')) {
      const label = typeof body.label === 'string' ? body.label.trim() : '';
      if (!label) return reply.code(400).send({ error: 'missing_label' });
      updates.label = label;
      updates.label_norm = normalizeVocabString(label);
    }

    if (body.detail !== undefined) {
      updates.detail = typeof body.detail === 'string' && body.detail.trim() ? body.detail.trim() : null;
    }

    if (body.sortOrder !== undefined) {
      const so = Number.parseInt(body.sortOrder, 10);
      if (!Number.isInteger(so)) return reply.code(400).send({ error: 'invalid_sort_order' });
      updates.sort_order = so;
    }

    if (body.archived !== undefined) {
      updates.archived_at = body.archived ? new Date().toISOString() : null;
    }

    const keys = Object.keys(updates);
    if (keys.length === 0) return reply.code(200).send(toBrewOption(existing));

    const setFrags = keys.map((k, i) => `${k} = $${i + 1}`);
    const vals = keys.map((k) => updates[k]);
    vals.push(id);
    setFrags.push('updated_at = now()');

    try {
      const { rows } = await query(
        `UPDATE brew_options SET ${setFrags.join(', ')} WHERE id = $${vals.length} RETURNING *`,
        vals,
      );
      return reply.code(200).send(toBrewOption(rows[0]));
    } catch (err) {
      if (err?.code === '23505') return reply.code(409).send({ error: 'brew_option_conflict' });
      throw err;
    }
  });

  // Set the tri-state for one (coffee, option), in one transaction. `best`
  // demotes the previous winner of that kind; a recipe set to tried/best also
  // ticks its nominal grind + temp (one-way). Responds with the coffee's WHOLE
  // brew state so the client replaces it atomically.
  app.post('/api/coffees/:publicId/brew', { preHandler: requireIngestToken }, async (req, reply) => {
    const body = req.body ?? {};
    const { optionId, state } = body;

    if (!BREW_STATES.includes(state)) {
      return reply.code(400).send({ error: 'invalid_brew_state', value: state ?? null });
    }
    if (!Number.isInteger(optionId)) {
      return reply.code(400).send({ error: 'invalid_option_id', value: optionId ?? null });
    }

    let result;
    try {
      result = await withTransaction(async (client) => {
        const { rows: coffeeRows } = await client.query(
          `SELECT id FROM coffees WHERE public_id = $1 AND deleted_at IS NULL`,
          [req.params.publicId],
        );
        const coffee = coffeeRows[0];
        if (!coffee) return { code: 404, body: { error: 'coffee_not_found' } };
        const coffeeId = coffee.id;

        const { rows: optRows } = await client.query('SELECT * FROM brew_options WHERE id = $1', [optionId]);
        const option = optRows[0];
        if (!option) return { code: 404, body: { error: 'brew_option_not_found' } };

        // Untrying an archived option is fine (you can always untick history);
        // trying/winning one that's been retired is not.
        if (state !== 'untried' && option.archived_at != null) {
          return { code: 409, body: { error: 'brew_option_archived' } };
        }

        // Current winner of this kind, to demote when a new best is set.
        const { rows: bestRows } = await client.query(
          `SELECT option_id FROM coffee_brew_trials
           WHERE coffee_id = $1 AND kind = $2 AND is_best LIMIT 1`,
          [coffeeId, option.kind],
        );
        const current = { bestOptionId: bestRows[0]?.option_id ?? null };

        const { mutations } = nextTrialRows(current, { id: option.id, kind: option.kind }, state);
        for (const m of mutations) {
          if (m.action === 'delete') {
            await client.query(
              'DELETE FROM coffee_brew_trials WHERE coffee_id = $1 AND option_id = $2',
              [coffeeId, m.optionId],
            );
          } else if (m.action === 'demote') {
            await client.query(
              'UPDATE coffee_brew_trials SET is_best = false WHERE coffee_id = $1 AND option_id = $2',
              [coffeeId, m.optionId],
            );
          } else if (m.action === 'upsert') {
            await client.query(
              `INSERT INTO coffee_brew_trials (coffee_id, option_id, kind, is_best)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (coffee_id, option_id) DO UPDATE SET is_best = EXCLUDED.is_best`,
              [coffeeId, m.optionId, m.kind, m.isBest],
            );
          }
        }

        // Recipe auto-tick: setting a recipe tried/best also ticks its nominal
        // grind + temp as `tried` (never best; one-way — untrying the recipe
        // leaves them). get-or-create the numeric options so the tick always
        // resolves.
        if (option.kind === 'recipe' && (state === 'tried' || state === 'best')) {
          const implied = impliedTrials({
            kind: option.kind,
            grindClicks: option.grind_clicks,
            waterTempC: option.water_temp_c,
          });
          for (const t of implied) {
            const numeric = await getOrCreateNumericOption(client, t.kind, t.valueNum);
            if (!numeric) continue;
            await client.query(
              `INSERT INTO coffee_brew_trials (coffee_id, option_id, kind, is_best)
               VALUES ($1, $2, $3, false)
               ON CONFLICT (coffee_id, option_id) DO NOTHING`,
              [coffeeId, numeric.id, t.kind],
            );
          }
        }

        await client.query('UPDATE coffees SET updated_at = now() WHERE id = $1', [coffeeId]);

        const brew = await loadCoffeeBrewState(client, coffeeId);
        return { code: 200, body: { id: req.params.publicId, ...brew } };
      });
    } catch (err) {
      req.log?.error?.(`[brew] setBrewState failed: ${err.message}`);
      throw err;
    }

    return reply.code(result.code).send(result.body);
  });
}
