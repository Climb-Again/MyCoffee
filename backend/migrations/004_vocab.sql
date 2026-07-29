-- 004_vocab.sql — controlled vocabularies: countries, roasters, farms, cities,
-- roast profiles. Canonical row + a matching `*_aliases` table per kind, each
-- with a UNIQUE `alias_norm` so a normalized string resolves to exactly one
-- entity (src/lib/vocab.js owns resolution; src/lib/fuzzy.js owns matching).
--
-- This migration creates structure only. The docx-derived roaster/country
-- names and aliases are seeded by 005_vocab_seed.sql (Data lane). The few
-- fixed, non-docx rows below (the `Blend` pseudo-country and the five roast
-- profiles) are seeded here because they're part of the schema, not the data
-- extraction.

CREATE TABLE IF NOT EXISTS countries (
  id         SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT        NOT NULL UNIQUE,
  iso2       CHAR(2),                          -- NULL for the 'pseudo' Blend row
  is_origin  BOOLEAN     NOT NULL DEFAULT false,
  is_roaster BOOLEAN     NOT NULL DEFAULT false,
  kind       TEXT        NOT NULL DEFAULT 'country' CHECK (kind IN ('country', 'pseudo')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS country_aliases (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  country_id  SMALLINT NOT NULL REFERENCES countries (id) ON DELETE CASCADE,
  alias       TEXT     NOT NULL,
  alias_norm  TEXT     NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_country_aliases_country ON country_aliases (country_id);

CREATE TABLE IF NOT EXISTS roasters (
  id         INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT        NOT NULL,
  slug       TEXT        NOT NULL UNIQUE,
  country_id SMALLINT    REFERENCES countries (id),
  blurb      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roaster_aliases (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  roaster_id INT    NOT NULL REFERENCES roasters (id) ON DELETE CASCADE,
  alias      TEXT   NOT NULL,
  alias_norm TEXT   NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_roaster_aliases_roaster ON roaster_aliases (roaster_id);

CREATE TABLE IF NOT EXISTS farms (
  id         INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT        NOT NULL,
  kind       TEXT,                              -- finca / fazenda / producer / washing_station
  country_id SMALLINT    REFERENCES countries (id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS farm_aliases (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  farm_id    INT    NOT NULL REFERENCES farms (id) ON DELETE CASCADE,
  alias      TEXT   NOT NULL,
  alias_norm TEXT   NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_farm_aliases_farm ON farm_aliases (farm_id);

-- ~40 rows for city -> country inference (e.g. Amsterdam -> Netherlands).
-- `ambiguous` stops a name like "Cambridge" from auto-resolving.
CREATE TABLE IF NOT EXISTS cities (
  id         INT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       TEXT     NOT NULL,
  country_id SMALLINT NOT NULL REFERENCES countries (id),
  ambiguous  BOOLEAN  NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS city_aliases (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  city_id    INT    NOT NULL REFERENCES cities (id) ON DELETE CASCADE,
  alias      TEXT   NOT NULL,
  alias_norm TEXT   NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_city_aliases_city ON city_aliases (city_id);

-- Roast profile: Washed / Natural / Anaerobic / Co-fermented / Experimental.
-- Decaf is modeled as a separate `coffees.is_decaf BOOLEAN` (a decaf can be
-- washed) — never as a sixth profile. Fixed, small, seeded here.
CREATE TABLE IF NOT EXISTS profiles (
  id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug TEXT     NOT NULL UNIQUE,
  name TEXT     NOT NULL
);

INSERT INTO profiles (slug, name) VALUES
  ('washed',       'Washed'),
  ('natural',      'Natural'),
  ('anaerobic',    'Anaerobic'),
  ('co_fermented', 'Co-fermented'),
  ('experimental', 'Experimental')
ON CONFLICT (slug) DO NOTHING;

-- 'Blend' is a pseudo-country: origin isn't single-valued for a blended bag,
-- and the brief's data contains literal "Blend" entries. Fixed row, seeded
-- here rather than from the docx lists.
INSERT INTO countries (name, iso2, is_origin, is_roaster, kind) VALUES
  ('Blend', NULL, true, false, 'pseudo')
ON CONFLICT (name) DO NOTHING;

-- Trigram indexes speed up alias autocomplete once pg_trgm is available
-- (003_extensions.sql installs it best-effort; skip cleanly if it isn't).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
    CREATE INDEX IF NOT EXISTS idx_country_aliases_trgm ON country_aliases USING gin (alias_norm gin_trgm_ops);
    CREATE INDEX IF NOT EXISTS idx_roaster_aliases_trgm ON roaster_aliases USING gin (alias_norm gin_trgm_ops);
    CREATE INDEX IF NOT EXISTS idx_farm_aliases_trgm    ON farm_aliases    USING gin (alias_norm gin_trgm_ops);
    CREATE INDEX IF NOT EXISTS idx_city_aliases_trgm    ON city_aliases    USING gin (alias_norm gin_trgm_ops);
  END IF;
END $$;
