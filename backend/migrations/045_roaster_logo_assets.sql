-- 045 (#152 option A, Radu's pick): roaster logos get their own storage,
-- served from the Railway /data volume instead of raw.githubusercontent.com.
--
-- Why a separate table rather than widening `assets`: `assets` is
-- `photo_id BIGINT NOT NULL REFERENCES photos` with `UNIQUE (photo_id, variant)`
-- and a three-value variant CHECK. A logo has no photo, so holding one there
-- means dropping the NOT NULL and adding an owner discriminator — making the
-- photo pipeline's central table polymorphic to store one ~11 KB file per
-- roaster. This table is four columns and touches nothing that already works.
--
-- Keyed on roaster_id (not slug) so a roaster rename cannot orphan its logo;
-- the SERVING url uses the slug, which is the stable public key the app already
-- caches in the snapshot vocab.
CREATE TABLE IF NOT EXISTS roaster_logos (
  roaster_id   INTEGER     PRIMARY KEY REFERENCES roasters (id) ON DELETE CASCADE,
  sha256       CHAR(64)    NOT NULL,
  bytes        INT         NOT NULL,
  width        INT,
  height       INT,
  storage_path TEXT        NOT NULL,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Provenance, so "who set this logo" is answerable: 'ops' for the
-- chat/GitHub intake (#133), 'app' for an in-app upload (#153). Existing rows
-- all came from ops.
ALTER TABLE roasters
  ADD COLUMN IF NOT EXISTS content_source TEXT NOT NULL DEFAULT 'ops'
    CHECK (content_source IN ('ops', 'app'));
