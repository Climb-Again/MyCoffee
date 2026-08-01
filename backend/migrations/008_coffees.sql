-- 008_coffees.sql — the record the whole app is about. Derived from `photos`
-- (one coffee per photo, once extraction produces one — PLAN.md §1), never the
-- other way round. Structure only: no extraction pipeline exists yet (#23/#24),
-- so every field below is written either by a future backfill or left NULL.
--
-- Generated-column note (CLAUDE.md §12 / PLAN.md §1): `EXTRACT(... FROM date)`,
-- array subscripting, and `round(numeric, int)` are all IMMUTABLE, so
-- `purchased_year/month`, `origin_country_id`, and `altitude_mid_m` /
-- `price_per_100g_eur` are legal generated columns. `is_blend` is NOT generated
-- — the "even a single id can be the Blend pseudo-country" rule (PLAN.md §1)
-- needs a lookup into `countries`, which a generated column can't do; it's
-- computed by `src/lib/vocab.js`'s `computeIsBlend` (data lane) and written
-- explicitly, same as `roaster_country_id`.

CREATE TABLE IF NOT EXISTS coffees (
  id                       BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Opaque id for the client and for URLs — same pattern as photos.public_id.
  public_id                TEXT        NOT NULL UNIQUE,
  -- One coffee per photo. ON DELETE RESTRICT: a photo can't disappear out from
  -- under an already-extracted coffee without an explicit decision.
  photo_id                 BIGINT      NOT NULL UNIQUE REFERENCES photos (id) ON DELETE RESTRICT,

  purchased_at             TIMESTAMPTZ,
  -- Written explicitly, never derived from purchased_at: `AT TIME ZONE` is
  -- STABLE, not IMMUTABLE (CLAUDE.md §12).
  purchased_on             DATE,
  purchased_year           SMALLINT    GENERATED ALWAYS AS (EXTRACT(YEAR FROM purchased_on)::SMALLINT) STORED,
  purchased_month          SMALLINT    GENERATED ALWAYS AS (EXTRACT(MONTH FROM purchased_on)::SMALLINT) STORED,

  roaster_id               INT         REFERENCES roasters (id),
  -- Denormalized copy of roasters.country_id at extraction time — not FK-
  -- generatable (generated columns can't subquery another table).
  roaster_country_id       SMALLINT    REFERENCES countries (id),

  -- Array, not two FK columns: subscripting is IMMUTABLE (so origin_country_id
  -- can be generated), `@>` is GIN-indexable, and unnest() makes the origin
  -- facet a one-liner that counts a blend in both member countries. No FK
  -- integrity on array members — src/lib/vocab.js's validateOriginCountryIds
  -- enforces it (data lane, PLAN.md §1).
  origin_country_ids       SMALLINT[]  NOT NULL DEFAULT '{}',
  origin_country_id        SMALLINT    GENERATED ALWAYS AS (origin_country_ids[1]) STORED,
  is_blend                 BOOLEAN     NOT NULL DEFAULT false,
  origin_farm_id           INT         REFERENCES farms (id),

  altitude_min_m           INT,
  altitude_max_m           INT,
  altitude_mid_m            INT GENERATED ALWAYS AS (
                              CASE
                                WHEN altitude_min_m IS NOT NULL AND altitude_max_m IS NOT NULL
                                  THEN (altitude_min_m + altitude_max_m) / 2
                                ELSE COALESCE(altitude_max_m, altitude_min_m)
                              END
                            ) STORED,

  profile_id                SMALLINT   REFERENCES profiles (id),
  -- Literal term kept verbatim (e.g. "Yellow Honey") even when profile_id
  -- folds it into Experimental — PLAN.md §2's honey ruling.
  profile_detail             TEXT,
  is_decaf                   BOOLEAN    NOT NULL DEFAULT false,
  roasted_on                 DATE,

  price_original_amount      NUMERIC(10, 2),
  price_original_currency    CHAR(3),
  price_eur                  NUMERIC(10, 2),
  -- The fx_rates row actually applied, so a price is reproducible without
  -- re-deriving which monthly average was used.
  fx_rate                    NUMERIC(14, 6),
  fx_rate_period              DATE,
  weight_g                    INT,
  price_per_100g_eur           NUMERIC(10, 2) GENERATED ALWAYS AS (
                                CASE
                                  WHEN weight_g > 0 AND price_eur IS NOT NULL
                                    THEN round(price_eur / weight_g * 100, 2)
                                  ELSE NULL
                                END
                              ) STORED,

  rating                       NUMERIC(2, 1) CHECK (rating IS NULL OR (rating BETWEEN 0 AND 5)),
  is_favorite                  BOOLEAN NOT NULL DEFAULT false,
  -- Sticky when human: a later incremental extraction run must never flip a
  -- favorite Radu set by hand back off (the `locked` invariant, PLAN.md §1).
  favorite_set_by              TEXT CHECK (favorite_set_by IS NULL OR favorite_set_by IN ('human', 'system')),

  -- The three note blocks on the detail page (PLAN.md §6.3): farm/lot and brew
  -- guide shown expanded, roaster copy collapsed. Sliced from the raw text by
  -- character offset, never rewritten (PLAN.md §2 point 6 — "prose is
  -- selected, not voted").
  desc_farm_lot                TEXT,
  desc_brew_guide              TEXT,
  desc_roaster_copy            TEXT,

  -- Verbatim source text, kept alongside the sliced parts above so a review
  -- decision always has the original to fall back on.
  raw_title                    TEXT,
  raw_caption                  TEXT,
  raw_description              TEXT,

  review_state                 TEXT NOT NULL DEFAULT 'unextracted'
                                CHECK (review_state IN ('unextracted', 'needs_review', 'clean')),
  min_field_confidence          NUMERIC(3, 2),

  -- Soft delete: a coffee can be retired (e.g. merged into another record on a
  -- duplicate-photo resolution) without breaking a client's delta sync, which
  -- needs deleted ids rather than a row just vanishing (PLAN.md §4).
  deleted_at                    TIMESTAMPTZ,

  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coffees_purchased_on ON coffees (purchased_on DESC);
CREATE INDEX IF NOT EXISTS idx_coffees_roaster      ON coffees (roaster_id);
CREATE INDEX IF NOT EXISTS idx_coffees_origin_farm  ON coffees (origin_farm_id);
CREATE INDEX IF NOT EXISTS idx_coffees_rating       ON coffees (rating DESC);
CREATE INDEX IF NOT EXISTS idx_coffees_review_state ON coffees (review_state);
CREATE INDEX IF NOT EXISTS idx_coffees_updated_at   ON coffees (updated_at);
