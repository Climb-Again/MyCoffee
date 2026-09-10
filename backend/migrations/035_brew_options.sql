-- 035_brew_options.sql — the "Brew lab" (PLAN.md §14, backlog #155).
--
-- One catalogue table with a `kind` discriminator (recipe / device / grind /
-- temp), not four tables: one CRUD route, one Swift model, one snapshot block,
-- one checklist component. Per coffee, each catalogue is a tri-state checklist
-- in `coffee_brew_trials` — untried (no row) / tried / best — with at most one
-- winner per (coffee, kind) enforced by a partial unique index rather than a
-- route-level promise.
--
-- Named 035 (not 034 — that prefix is already used twice: 034_add_congo_… and
-- 034_wire_all_roaster_logos). Forward-only, advisory-locked runner; every
-- CREATE is IF NOT EXISTS and the seed is idempotent. No non-IMMUTABLE
-- expressions appear in any generated column (there are none here).

CREATE TABLE IF NOT EXISTS brew_options (
  id           INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind         TEXT        NOT NULL CHECK (kind IN ('recipe', 'device', 'grind', 'temp')),
  label        TEXT        NOT NULL,             -- "V60", "4:6 (Kasuya)", "24 clicks", "94 °C"
  label_norm   TEXT        NOT NULL,             -- normalize.js fold; UNIQUE per kind
  detail       TEXT,                             -- optional free note (recipe: "bloom 45 s"; device: model); else NULL
  value_num    NUMERIC(6,1),                     -- temp: °C; grind: Comandante clicks; recipe/device: NULL
  -- Recipe structure (Radu, 2026-09-09). NULL on every non-recipe row (CHECK below).
  dose_g          NUMERIC(5,1),                  -- coffee grams
  pours           SMALLINT,                      -- number of pours (1 = single pour / immersion)
  ml_per_pour     SMALLINT,                      -- NULL when pours are uneven; UI prefills total = pours × ml_per_pour
  total_water_ml  SMALLINT,                      -- stored, not generated: uneven pours make it non-derivable
  grind_clicks    SMALLINT,                      -- the recipe's nominal Comandante setting
  water_temp_c    SMALLINT,                      -- the recipe's nominal temperature
  sort_order   INT         NOT NULL DEFAULT 0,   -- manual order within kind; grind/temp sort by value_num
  archived_at  TIMESTAMPTZ,                      -- soft-hide from pickers; history stays intact
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (kind, label_norm),
  CONSTRAINT brew_options_recipe_fields CHECK (
    kind = 'recipe' OR (dose_g IS NULL AND pours IS NULL AND ml_per_pour IS NULL
                        AND total_water_ml IS NULL AND grind_clicks IS NULL AND water_temp_c IS NULL)
  ),
  CONSTRAINT brew_options_recipe_complete CHECK (
    kind <> 'recipe' OR (dose_g > 0 AND pours BETWEEN 1 AND 12 AND total_water_ml > 0
                         AND grind_clicks BETWEEN 1 AND 60 AND water_temp_c BETWEEN 60 AND 100)
  ),
  CONSTRAINT brew_options_numeric_kinds CHECK (
    (kind = 'temp'  AND value_num BETWEEN 60 AND 100) OR
    (kind = 'grind' AND value_num BETWEEN 1 AND 60)   OR
    (kind IN ('recipe', 'device') AND value_num IS NULL)
  )
);
-- One row per (kind, numeric value) for grind/temp so the recipe auto-tick
-- (routes/brew.js) can find "24 clicks" / "94 °C" by value, not by label spelling.
CREATE UNIQUE INDEX IF NOT EXISTS ux_brew_options_kind_value
  ON brew_options (kind, value_num) WHERE kind IN ('grind', 'temp');

CREATE TABLE IF NOT EXISTS coffee_brew_trials (
  coffee_id    BIGINT      NOT NULL REFERENCES coffees (id) ON DELETE CASCADE,
  option_id    INT         NOT NULL REFERENCES brew_options (id) ON DELETE RESTRICT,
  -- Denormalized copy of brew_options.kind so the one-winner rule is a
  -- partial unique index, not a route-level promise. Written by the route.
  kind         TEXT        NOT NULL CHECK (kind IN ('recipe', 'device', 'grind', 'temp')),
  is_best      BOOLEAN     NOT NULL DEFAULT false,
  tried_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (coffee_id, option_id)
);
-- At most one winner per (coffee, kind). Race-proof by construction.
CREATE UNIQUE INDEX IF NOT EXISTS ux_coffee_brew_best
  ON coffee_brew_trials (coffee_id, kind) WHERE is_best;
CREATE INDEX IF NOT EXISTS idx_coffee_brew_trials_option ON coffee_brew_trials (option_id);

-- ── Seed (idempotent) ──────────────────────────────────────────────────────
-- Starting points only; Radu adds/renames/archives from the app (#157).

-- Devices (10). label_norm is normalize.js's fold (lowercase, collapsed spaces).
INSERT INTO brew_options (kind, label, label_norm, sort_order) VALUES
  ('device', 'V60',            'v60',            1),
  ('device', 'Kalita Wave',    'kalita wave',    2),
  ('device', 'Origami',        'origami',        3),
  ('device', 'Chemex',         'chemex',         4),
  ('device', 'AeroPress',      'aeropress',      5),
  ('device', 'Clever Dripper', 'clever dripper', 6),
  ('device', 'French press',   'french press',   7),
  ('device', 'Moka pot',       'moka pot',       8),
  ('device', 'Espresso',       'espresso',       9),
  ('device', 'Cold brew',      'cold brew',      10)
ON CONFLICT (kind, label_norm) DO NOTHING;

-- Grind: Comandante clicks 16..36 (21 rows), label "n clicks", value_num = n.
INSERT INTO brew_options (kind, label, label_norm, value_num)
SELECT 'grind', n || ' clicks', n || ' clicks', n
FROM generate_series(16, 36) AS n
ON CONFLICT (kind, label_norm) DO NOTHING;

-- Temp: 85..100 °C in 1 °C steps (16 rows), label "n °C", value_num = n.
INSERT INTO brew_options (kind, label, label_norm, value_num)
SELECT 'temp', n || ' °C', n || ' °c', n
FROM generate_series(85, 100) AS n
ON CONFLICT (kind, label_norm) DO NOTHING;

-- Recipes: 5 structured templates. Every recipe's grind_clicks/water_temp_c
-- (24/28/20/32 clicks, 85/92/94/95/96 °C) exists as a grind/temp row above, so
-- the recipe auto-tick always resolves.
INSERT INTO brew_options
  (kind, label, label_norm, dose_g, pours, ml_per_pour, total_water_ml, grind_clicks, water_temp_c, sort_order)
VALUES
  ('recipe', 'V60 1-cup (Hoffmann)',   'v60 1-cup (hoffmann)',   15, 3, NULL, 250, 24, 95, 1),
  ('recipe', '4:6 (Kasuya)',           '4:6 (kasuya)',           20, 5, 60,   300, 28, 92, 2),
  ('recipe', 'AeroPress single pour',  'aeropress single pour',  15, 1, 200,  200, 20, 85, 3),
  ('recipe', 'Chemex 3-cup',           'chemex 3-cup',           30, 4, 125,  500, 28, 94, 4),
  ('recipe', 'French press 4 min',     'french press 4 min',     30, 1, 500,  500, 32, 96, 5)
ON CONFLICT (kind, label_norm) DO NOTHING;
