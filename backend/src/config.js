// Centralized environment configuration for the MyCoffee backend.
// Read every env var here so the rest of the app never touches process.env directly.

// Resolve an env var tolerating whitespace in the KEY, not just the value.
//
// Why (issue #33): a variable can end up registered as "GOOGLE_PRIVATE_KEY\n" —
// a trailing newline captured into the *name* when it was pasted. Railway's UI
// renders that identically to the clean name and even collapses the two rows, so
// the operator sees 8 variables while the container receives 9: one correct-looking
// but empty, and one decorated holding the real 2.4 KB value. Nothing in the UI can
// reveal it. process.env['GOOGLE_PRIVATE_KEY'] then returns '' and the service looks
// unconfigured with no way to tell why.
//
// A config layer has no reason to care about stray whitespace in a variable name, so
// it now doesn't. Exact match wins; a trimmed-name match is the fallback, preferring
// a non-empty value when both a clean and a decorated key exist.
const envByTrimmedKey = new Map();
for (const [key, value] of Object.entries(process.env)) {
  const trimmed = key.trim();
  if (trimmed === key) continue; // clean keys are read directly
  const existing = envByTrimmedKey.get(trimmed);
  if (existing === undefined || (!existing && value)) envByTrimmedKey.set(trimmed, value);
}

function rawEnv(name) {
  const direct = process.env[name];
  if (direct !== undefined && direct !== '') return direct;
  const recovered = envByTrimmedKey.get(name);
  return recovered !== undefined && recovered !== '' ? recovered : direct;
}

function int(name, fallback) {
  const raw = rawEnv(name);
  if (raw === undefined || raw === '') return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) ? n : fallback;
}

function str(name, fallback = '') {
  const raw = rawEnv(name);
  return raw === undefined || raw === '' ? fallback : raw;
}

// Exported for tests only (issue #33 regression coverage).
export const readEnvForTest = rawEnv;

export const config = {
  env: str('NODE_ENV', 'development'),
  host: str('HOST', '0.0.0.0'),
  port: int('PORT', 3000),

  // DATABASE_URL is required. We don't hard-exit here (config is imported by
  // tooling too); server.js validates it at boot.
  databaseUrl: str('DATABASE_URL'),
  pgssl: str('PGSSL'),

  ingestToken: str('INGEST_TOKEN'),
  appToken: str('APP_TOKEN'),

  dataDir: str('DATA_DIR', '/data'),
  maxUploadBytes: int('MAX_UPLOAD_BYTES', 100 * 1024 * 1024),

  rateLimitMax: int('RATE_LIMIT_MAX', 300),
  rateLimitWindowMs: int('RATE_LIMIT_WINDOW_MS', 60_000),
  // Override for PUT /api/photos/:sourceId/image — a cold backfill run is
  // ~900 requests, which would otherwise take ~3.5 min of 429-dodging at the
  // global 300/min cap.
  ingestRateLimitMax: int('INGEST_RATE_LIMIT_MAX', 1200),

  // HMAC key for signed GET /media/:publicId/:variant.jpg URLs. Empty by
  // default: media.js falls back to HMAC(APP_TOKEN, 'media') so this adds no
  // required env var.
  mediaSigningKey: str('MEDIA_SIGNING_KEY'),

  vertex: {
    projectId: str('GOOGLE_PROJECT_ID'),
    serviceAccountEmail: str('GOOGLE_SERVICE_ACCOUNT_EMAIL'),
    privateKey: str('GOOGLE_PRIVATE_KEY'),
    privateKeyId: str('GOOGLE_PRIVATE_KEY_ID'),
    clientId: str('GOOGLE_CLIENT_ID'),
    region: str('VERTEX_AI_REGION', 'us-central1'),
    model: str('VERTEX_MODEL', 'gemini-2.5-pro'),
    // Hard per-request ceiling. gaxios (via google-auth-library) defaults to NO
    // timeout, so a request that is never answered hangs the caller forever —
    // and in the extraction worker that means hanging while holding the
    // `pg_advisory_lock`, which silently blocks every subsequent job with no
    // error anywhere. Generous enough for a thinking-heavy 2.5-pro call on an
    // image (those can run minutes), but finite.
    timeoutMs: int('VERTEX_TIMEOUT_MS', 180000),
  },

  // Adjudication + worker tuning (PLAN.md §2, §11). Kept here rather than in
  // a migration so it's "tunable without a migration" — re-adjudicating the
  // whole corpus after a tweak costs $0 (adjudicate.js reads only stored
  // `field_candidates` rows). Accept-by-default (PLAN.md §11): confidence no
  // longer gates the accept/review decision, so there is no field-threshold
  // table here any more -- only a genuine cluster split routes to review.
  extraction: {
    // P3 (rules) carries 1.5x weight on numeric/unit fields -- it's better
    // than any LLM at exactly these -- and 0 on prose, which it never attempts.
    ruleVoterWeight: 1.5,
    ruleVoterWeightedFields: ['altitude', 'price', 'weight_g', 'rating', 'roasted_on'],
    ruleVoterProseFields: ['desc_farm_lot', 'desc_brew_guide', 'desc_roaster_copy'],
    // A prose cluster's boundary spread wider than this forces review even
    // when voters otherwise agree (PLAN.md §2 point 6).
    proseSpreadReviewChars: 80,
    // Bumped by the data lane when the vocabulary changes meaningfully
    // enough that a stored extraction should be treated as a new question.
    vocabVersion: int('EXTRACTION_VOCAB_VERSION', 1),
    worker: {
      advisoryLockKey: 48201976,
      leaseMinutes: 10,
      concurrency: 2,
      backoffSeconds: [2, 5, 15, 45, 120],
    },
  },
};

export function isProd() {
  return config.env === 'production';
}
