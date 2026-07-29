-- 007_photos.sql — the ingestion unit. `photos` is the upsert target for the
-- Mac exporter's manifest; `photo_texts` is the versioned caption/description
-- history that drives the 4-5 day caption gap; `assets` holds the derivative
-- files (ocr/display/thumb) the PUT-image route generates via sharp.
-- coffees (migration 008) is *derived from* photos, not the other way round.

CREATE TABLE IF NOT EXISTS photos (
  id                BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Opaque id used in signed media URLs so the DB's internal id and the
  -- Photos-library source_id never leak into GET /media/:publicId/....
  public_id         TEXT        NOT NULL UNIQUE,

  -- (source, source_id) is the upsert key: stable across repeated exporter
  -- runs, so re-running the exporter never duplicates a photo.
  source            TEXT        NOT NULL DEFAULT 'photos_library',
  source_id         TEXT        NOT NULL,

  -- Change/duplicate detector: a changed hash on an existing source_id means
  -- the photo was edited and derivatives must be rebuilt; the same hash under
  -- a *different* source_id means the same bag was re-imported. Partial (not
  -- a plain UNIQUE) because a manifest-only row may arrive without one yet.
  content_sha256    CHAR(64),

  captured_at       TIMESTAMPTZ,
  -- Written explicitly by the app, never generated: `timestamptz AT TIME ZONE`
  -- is STABLE, not IMMUTABLE, so it cannot back a generated column.
  captured_on       DATE,

  title             TEXT,
  favorite          BOOLEAN     NOT NULL DEFAULT false,

  -- Caption-gap state machine (PLAN.md §3). Populated by the manifest route;
  -- the transitions themselves belong to the extraction worker (#24).
  state             TEXT        NOT NULL DEFAULT 'awaiting_text'
                                CHECK (state IN ('awaiting_text', 'text_received', 'processed')),
  text_wait_until   TIMESTAMPTZ,

  has_image         BOOLEAN     NOT NULL DEFAULT false,
  image_uploaded_at TIMESTAMPTZ,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (source, source_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_photos_content_sha256
  ON photos (content_sha256) WHERE content_sha256 IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_photos_state ON photos (state);

-- Versioned caption/description text. A new version lands only when the text
-- actually changes (text_sha256 differs from every prior version for this
-- photo) -- that's the re-extraction trigger. The unique pair means a resent,
-- unchanged manifest entry is a detectable no-op rather than a new version.
CREATE TABLE IF NOT EXISTS photo_texts (
  id           BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  photo_id     BIGINT      NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  version      INT         NOT NULL,
  title        TEXT,
  caption      TEXT,
  description  TEXT,
  text_sha256  CHAR(64)    NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (photo_id, version),
  UNIQUE (photo_id, text_sha256)
);

CREATE INDEX IF NOT EXISTS idx_photo_texts_photo ON photo_texts (photo_id, version DESC);

-- One row per stored derivative. storage_path is relative to DATA_DIR and
-- content-addressed by the derivative's own sha256, so a re-upload of
-- identical bytes is a guaranteed no-op write.
CREATE TABLE IF NOT EXISTS assets (
  id            BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  photo_id      BIGINT      NOT NULL REFERENCES photos (id) ON DELETE CASCADE,
  variant       TEXT        NOT NULL CHECK (variant IN ('ocr', 'display', 'thumb')),
  sha256        CHAR(64)    NOT NULL,
  width         INT,
  height        INT,
  bytes         INT         NOT NULL,
  storage_path  TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (photo_id, variant)
);
