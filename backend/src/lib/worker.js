// The extraction worker (PLAN.md §2): designed for a box that *will* be
// SIGTERM'd by an unrelated backend deploy (CLAUDE.md §12, "never push
// backend/** while a job is running" -- but the reaper below is what makes a
// SIGTERM survivable rather than merely disallowed).
//
//   - `pg_try_advisory_lock` (a distinct key from migrate.js's 4820_1975) so
//     only one worker process runs at a time even across a redeploy overlap.
//   - claim-with-lease: a short transaction stamps `photos.extraction_leased_*`
//     via FOR UPDATE SKIP LOCKED, then the slow network work happens outside
//     that transaction; a 10-minute-old lease is reaped on the next claim.
//   - concurrency 2 in-process, to leave Vertex quota for MyHealthOS.
//   - idempotent via `extractions.input_sha` -- a crash mid-record just means
//     the next run's first action (the input_sha lookup) is a cache hit for
//     whatever had already been paid for.
//
// `adjudicateAndApply()` is factored out from the voter-running loop so that
// `POST /api/admin/adjudicate` can re-run adjudication over already-stored
// `field_candidates` with new thresholds for $0 (PLAN.md §2) without
// re-running a single voter.
import { createHash, randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';

import { pool, query, withTransaction } from '../db.js';
import { config } from '../config.js';
import { derivativeAbsPath } from '../media.js';
import { adjudicateRecord } from './adjudicate.js';
import {
  loadCountryVocab,
  loadRoasterVocab,
  loadFarmVocab,
  validateOriginCountryIds,
  computeIsBlend,
} from './vocab.js';
import { toEur } from './fx.js';
import { runExtractA, runExtractB, runCritic, runReconciler, loadRulesVoter, PROMPT_VERSION } from './agents.js';

const REQUIRED_FIELDS = ['roaster_id', 'origin_country_ids', 'price', 'weight_g', 'rating'];

const ADJUDICATE_CTX_DEFAULTS = {
  thresholds: config.extraction.fieldThresholds,
  defaultThreshold: config.extraction.defaultThreshold,
  ruleVoterWeight: config.extraction.ruleVoterWeight,
  ruleVoterWeightedFields: config.extraction.ruleVoterWeightedFields,
  ruleVoterProseFields: config.extraction.ruleVoterProseFields,
  singleVoterPenalty: config.extraction.singleVoterPenalty,
  unanimousMinConfidence: config.extraction.unanimousMinConfidence,
  acceptShareThreshold: config.extraction.acceptShareThreshold,
  proseSpreadReviewChars: config.extraction.proseSpreadReviewChars,
};

function newPublicId() {
  return randomBytes(16).toString('base64url');
}

// ---- Pure helpers (no DB, no network -- unit-testable on their own) ----

export function computeInputSha({ agent, provider, model, promptVersion, imageSha, textSha, vocabVersion }) {
  return createHash('sha256')
    .update([agent, provider, model ?? '', promptVersion, imageSha ?? '', textSha ?? '', String(vocabVersion)].join('|'))
    .digest('hex');
}

export function buildRawText(photo, photoText) {
  return [photo?.title, photoText?.caption, photoText?.description].filter(Boolean).join('\n\n');
}

// Mirrors the SQL eligibility predicate in `claimBatch()` below, so the rule
// for "does this photo need an extraction pass" lives in one testable place
// even though the real claim runs it as SQL for the FOR UPDATE SKIP LOCKED.
export function isDueForExtraction(photo, now = new Date()) {
  if (!photo?.has_image || photo.state === 'processed') return false;
  if (photo.state === 'text_received') return true;
  if (photo.state === 'awaiting_text') {
    return Boolean(photo.text_wait_until) && new Date(photo.text_wait_until) <= now;
  }
  return false;
}

// Turns adjudicated field resolutions into the `coffees` column set to write.
// Pure -- `ctx` carries the already-loaded vocab/profile/fx data, no queries
// here -- so the field-to-column mapping is testable without a live Postgres.
export function buildCoffeeColumnUpdates(resolutions, ctx = {}) {
  const sets = [];
  const values = [];
  let i = 1;
  const push = (col, val) => {
    sets.push(`${col} = $${i++}`);
    values.push(val);
  };

  for (const [field, res] of Object.entries(resolutions ?? {})) {
    if (res.decision === 'review' || res.value == null) continue;
    switch (field) {
      case 'roaster_id': {
        push('roaster_id', res.value);
        const roaster = (ctx.vocab?.roasters?.candidates ?? []).find((r) => r.id === res.value);
        push('roaster_country_id', roaster?.country_id ?? null);
        break;
      }
      case 'origin_country_ids': {
        const { valid } = validateOriginCountryIds(res.value, ctx.vocab?.countries?.candidates);
        push('origin_country_ids', valid);
        push('is_blend', computeIsBlend(valid, ctx.vocab?.countries?.candidates));
        break;
      }
      case 'origin_farm_id':
        push('origin_farm_id', res.value);
        break;
      case 'altitude':
        push('altitude_min_m', res.value.min);
        push('altitude_max_m', res.value.max);
        break;
      case 'profile':
        push('profile_id', ctx.profileIdBySlug?.get(res.value.profileId) ?? null);
        push('profile_detail', res.value.detail ?? null);
        push('is_decaf', Boolean(res.value.isDecaf));
        break;
      case 'price': {
        push('price_original_amount', res.value.amount);
        push('price_original_currency', res.value.currency);
        const conv = toEur({ amount: res.value.amount, currency: res.value.currency, date: ctx.photoDate }, ctx.fxRates);
        push('price_eur', conv?.priceEur ?? null);
        push('fx_rate', conv?.fxRate ?? null);
        push('fx_rate_period', conv?.fxRatePeriod ?? null);
        break;
      }
      case 'weight_g':
        push('weight_g', res.value);
        break;
      case 'rating':
        push('rating', res.value);
        break;
      case 'roasted_on':
        push('roasted_on', res.value);
        break;
      case 'desc_farm_lot':
      case 'desc_brew_guide':
      case 'desc_roaster_copy':
        push(field, res.value);
        break;
      default:
        break;
    }
  }
  return { sets, values };
}

async function withBackoff(fn, delays) {
  let lastErr;
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const wait = delays[attempt];
      if (wait === undefined) break;
      await new Promise((resolve) => setTimeout(resolve, wait * 1000));
    }
  }
  throw lastErr;
}

async function runWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  async function pump() {
    while (next < items.length) {
      const idx = next++;
      results[idx] = await worker(items[idx], idx);
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, pump));
  return results;
}

// ---- Voter assembly ----
//
// P3 (rules) is the data lane's `src/lib/deterministic.js` (#25) -- absent
// until that lands, in which case it's simply left out (agents.js's
// `loadRulesVoter()` resolves to null rather than throwing).
export async function defaultVoters() {
  const voters = [
    { agent: 'extract_a', provider: 'vertex', model: 'gemini-2.5-pro', run: runExtractA },
    { agent: 'extract_b', provider: 'vertex', model: 'gemini-2.5-flash', run: runExtractB },
  ];
  const rulesVoter = await loadRulesVoter();
  if (rulesVoter) voters.push(rulesVoter);
  voters.push({ agent: 'critic', provider: 'vertex', model: 'gemini-2.5-flash', run: runCritic, isCritic: true });
  voters.push({ agent: 'reconciler', provider: 'vertex', model: 'gemini-2.5-pro', run: runReconciler });
  return voters;
}

// ---- DB-touching helpers ----

export async function claimBatch(limit, { leaseMinutes, workerId } = {}) {
  const minutes = leaseMinutes ?? config.extraction.worker.leaseMinutes;
  return withTransaction(async (client) => {
    // Reap stale leases first -- what recovers a SIGTERM'd worker.
    await client.query(
      `UPDATE photos SET extraction_leased_until = NULL, extraction_leased_by = NULL
       WHERE extraction_leased_until IS NOT NULL AND extraction_leased_until < now()`,
    );
    const { rows } = await client.query(
      `SELECT * FROM photos
       WHERE has_image
         AND state <> 'processed'
         AND (state = 'text_received' OR (state = 'awaiting_text' AND text_wait_until <= now()))
         AND extraction_leased_until IS NULL
       ORDER BY id
       LIMIT $1
       FOR UPDATE SKIP LOCKED`,
      [limit],
    );
    if (rows.length > 0) {
      const ids = rows.map((r) => r.id);
      await client.query(
        `UPDATE photos SET extraction_leased_until = now() + ($2 || ' minutes')::interval, extraction_leased_by = $3
         WHERE id = ANY($1)`,
        [ids, String(minutes), workerId ?? 'worker'],
      );
    }
    return rows;
  });
}

export async function releaseLease(photoId) {
  await query(
    `UPDATE photos SET extraction_leased_until = NULL, extraction_leased_by = NULL WHERE id = $1`,
    [photoId],
  );
}

async function fetchLatestText(photoId) {
  const { rows } = await query(
    `SELECT * FROM photo_texts WHERE photo_id = $1 ORDER BY version DESC LIMIT 1`,
    [photoId],
  );
  return rows[0] ?? null;
}

async function fetchImageBuffer(photo) {
  const { rows } = await query(`SELECT * FROM assets WHERE photo_id = $1 AND variant = 'ocr'`, [photo.id]);
  const asset = rows[0];
  if (!asset) return null;
  const buf = await readFile(derivativeAbsPath(asset.sha256, 'ocr'));
  return { mimeType: 'image/jpeg', dataBase64: buf.toString('base64'), sha256: asset.sha256 };
}

async function storeExtraction({ agent, provider, model, promptVersion, inputSha, response, usage, costUsd }) {
  const { rows } = await query(
    `INSERT INTO extractions (agent, provider, model, prompt_version, input_sha, response, usage, cost_usd)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (input_sha) DO NOTHING
     RETURNING *`,
    [agent, provider, model ?? null, promptVersion, inputSha, JSON.stringify(response), JSON.stringify(usage ?? null), costUsd ?? 0],
  );
  if (rows[0]) return { extraction: rows[0], reused: false };
  // Lost a race with a concurrent insert of the same input_sha.
  const { rows: reread } = await query(`SELECT * FROM extractions WHERE input_sha = $1`, [inputSha]);
  return { extraction: reread[0], reused: true };
}

async function getOrRunVoter(voter, inputSha, ctx) {
  const { rows: existing } = await query(`SELECT * FROM extractions WHERE input_sha = $1`, [inputSha]);
  if (existing[0]) return { extraction: existing[0], reused: true };

  const result = await withBackoff(() => voter.run(ctx), config.extraction.worker.backoffSeconds);
  const response = voter.isCritic ? { verdicts: result.verdicts } : { fields: result.fields };
  const { extraction, reused } = await storeExtraction({
    agent: voter.agent,
    provider: voter.provider,
    model: voter.model,
    promptVersion: voter.promptVersion ?? PROMPT_VERSION,
    inputSha,
    response,
    usage: result.usage,
    costUsd: result.costUsd,
  });
  return { extraction, reused };
}

async function storeFieldCandidates(photoId, extractionId, agent, fields) {
  for (const [field, cand] of Object.entries(fields ?? {})) {
    await query(
      `INSERT INTO field_candidates (photo_id, extraction_id, agent, field, value, confidence, evidence)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (photo_id, extraction_id, field) DO NOTHING`,
      [photoId, extractionId, agent, field, JSON.stringify(cand.value ?? null), cand.confidence ?? null, cand.evidence ?? null],
    );
  }
}

// Critic rows are stored too (agent='critic', value={refuted,reason,...}) so
// a later free re-adjudication pass can recover verdicts without re-running
// the critic. They're split out here rather than fed into adjudicateField's
// normal candidate clustering -- critic never proposes a value (PLAN.md §2).
async function fetchFieldData(photoId) {
  const { rows } = await query(
    `SELECT agent, field, value, confidence, evidence FROM field_candidates WHERE photo_id = $1`,
    [photoId],
  );
  const byField = {};
  const criticVerdicts = {};
  for (const row of rows) {
    if (row.agent === 'critic') {
      criticVerdicts[row.field] = row.value ?? {};
      continue;
    }
    (byField[row.field] ??= []).push({
      agent: row.agent,
      value: row.value,
      confidence: row.confidence != null ? Number(row.confidence) : null,
      evidence: row.evidence,
    });
  }
  return { byField, criticVerdicts };
}

async function fetchLockedFields(photoId) {
  const { rows } = await query(`SELECT field FROM field_resolutions WHERE photo_id = $1 AND locked = true`, [photoId]);
  return new Set(rows.map((r) => r.field));
}

async function storeResolutions(photoId, resolutions) {
  for (const [field, res] of Object.entries(resolutions)) {
    await query(
      `INSERT INTO field_resolutions (photo_id, field, value, confidence, agreement, voters, decided_by, locked)
       VALUES ($1,$2,$3,$4,$5,$6,'adjudication', false)
       ON CONFLICT (photo_id, field) DO UPDATE SET
         value = EXCLUDED.value, confidence = EXCLUDED.confidence, agreement = EXCLUDED.agreement,
         voters = EXCLUDED.voters, decided_at = now()
       WHERE field_resolutions.locked = false`,
      [photoId, field, JSON.stringify(res.value), res.confidence, res.agreement, res.voters],
    );
  }
}

async function storeReviews(photoId, reviews) {
  for (const r of reviews) {
    const { rows } = await query(
      `UPDATE review_items SET candidates = $3, reason = $4
       WHERE photo_id = $1 AND field = $2 AND status = 'open' RETURNING id`,
      [photoId, r.field, JSON.stringify(r.candidates), r.reason],
    );
    if (rows.length === 0) {
      await query(
        `INSERT INTO review_items (photo_id, field, reason, candidates) VALUES ($1,$2,$3,$4)`,
        [photoId, r.field, r.reason, JSON.stringify(r.candidates)],
      );
    }
  }
}

// A field that used to need review but now resolves cleanly (e.g. a vocab
// alias got confirmed since the last pass) closes its own open review item.
async function closeStaleReviews(photoId, resolutions, reviewedFieldSet) {
  for (const [field, res] of Object.entries(resolutions)) {
    if (reviewedFieldSet.has(field)) continue;
    await query(
      `UPDATE review_items SET status = 'resolved', resolved_value = $3, resolved_at = now()
       WHERE photo_id = $1 AND field = $2 AND status = 'open'`,
      [photoId, field, JSON.stringify(res.value)],
    );
  }
}

export async function upsertCoffeeBase(photo, photoText) {
  const { rows: existing } = await query(`SELECT * FROM coffees WHERE photo_id = $1`, [photo.id]);
  if (existing[0]) return existing[0];
  const { rows } = await query(
    `INSERT INTO coffees (public_id, photo_id, purchased_at, purchased_on, is_favorite, favorite_set_by, raw_title, raw_caption, raw_description)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [
      newPublicId(),
      photo.id,
      photo.captured_at,
      photo.captured_on,
      photo.favorite,
      photo.favorite ? 'system' : null,
      photo.title,
      photoText?.caption ?? null,
      photoText?.description ?? null,
    ],
  );
  return rows[0];
}

async function finalizeCoffeeStatus(coffeeId, photoId) {
  const [{ rows: openRows }, { rows: confRows }] = await Promise.all([
    query(`SELECT 1 FROM review_items WHERE photo_id = $1 AND status = 'open' LIMIT 1`, [photoId]),
    query(
      `SELECT confidence FROM field_resolutions WHERE photo_id = $1 AND field = ANY($2) AND confidence IS NOT NULL`,
      [photoId, REQUIRED_FIELDS],
    ),
  ]);
  const reviewState = openRows.length > 0 ? 'needs_review' : 'clean';
  const confidences = confRows.map((r) => Number(r.confidence));
  const minConfidence = confidences.length ? Math.min(...confidences) : null;
  await query(`UPDATE coffees SET review_state = $1, min_field_confidence = $2, updated_at = now() WHERE id = $3`, [
    reviewState,
    minConfidence,
    coffeeId,
  ]);
}

// Writes decided (non-review) fields onto the coffees row and refreshes
// review_state/min_field_confidence. Shared by the live worker path and
// `POST /api/review/:id` (a human decision applies the exact same way a
// unanimous adjudication would).
export async function applyResolutionsToCoffee(coffeeId, photoId, resolutions, ctx) {
  const { sets, values } = buildCoffeeColumnUpdates(resolutions, ctx);
  if (sets.length > 0) {
    await query(`UPDATE coffees SET ${sets.join(', ')}, updated_at = now() WHERE id = $${values.length + 1}`, [
      ...values,
      coffeeId,
    ]);
  }
  await finalizeCoffeeStatus(coffeeId, photoId);
}

export async function loadSharedContext() {
  const [countries, roasters, farms, profilesResult, fxRows] = await Promise.all([
    loadCountryVocab(query),
    loadRoasterVocab(query),
    loadFarmVocab(query),
    query('SELECT id, slug FROM profiles'),
    query('SELECT currency, period, rate_to_eur AS "rateToEur" FROM fx_rates'),
  ]);
  return {
    vocab: { countries, roasters, farms },
    profileIdBySlug: new Map(profilesResult.rows.map((r) => [r.slug, r.id])),
    fxRates: fxRows.rows.map((r) => ({
      currency: r.currency,
      period: r.period instanceof Date ? r.period.toISOString().slice(0, 10) : r.period,
      rateToEur: Number(r.rateToEur),
    })),
    vocabVersion: config.extraction.vocabVersion,
  };
}

// Re-derives field_resolutions/review_items/coffees from whatever
// field_candidates are already stored -- no voter is run. This is the $0,
// ~instant re-adjudication path (PLAN.md §2) that both a fresh worker pass
// and `POST /api/admin/adjudicate` end in.
export async function adjudicateAndApply(photo, photoText, sharedCtx) {
  const rawText = buildRawText(photo, photoText);
  const { byField: candidatesByField, criticVerdicts } = await fetchFieldData(photo.id);
  const locked = await fetchLockedFields(photo.id);

  const { resolutions, reviews } = adjudicateRecord(candidatesByField, {
    ...ADJUDICATE_CTX_DEFAULTS,
    vocab: sharedCtx.vocab,
    locked,
    criticVerdicts,
    photoDate: photo.captured_on,
    rawText,
  });

  await storeResolutions(photo.id, resolutions);
  const reviewedFieldSet = new Set(reviews.map((r) => r.field));
  await storeReviews(photo.id, reviews);
  await closeStaleReviews(photo.id, resolutions, reviewedFieldSet);

  const coffee = await upsertCoffeeBase(photo, photoText);
  await query(
    `UPDATE coffees SET raw_title = $1, raw_caption = $2, raw_description = $3, updated_at = now() WHERE id = $4`,
    [photo.title, photoText?.caption ?? null, photoText?.description ?? null, coffee.id],
  );
  await applyResolutionsToCoffee(coffee.id, photo.id, resolutions, { ...sharedCtx, photoDate: photo.captured_on });

  return { photoId: photo.id, coffeeId: coffee.id, reviewCount: reviews.length };
}

// One photo, start to finish: run every voter (reusing any already-paid-for
// extraction by input_sha), then hand off to adjudicateAndApply().
export async function processPhoto(photo, voters, sharedCtx) {
  const photoText = await fetchLatestText(photo.id);
  const rawText = buildRawText(photo, photoText);
  const image = await fetchImageBuffer(photo);
  const vocabShortlist = (sharedCtx.vocab.roasters.candidates ?? []).slice(0, 50).map((r) => r.name);

  let spentUsd = 0;
  const candidatesByFieldSoFar = {}; // prompt context only -- this run's own voters

  for (const voter of voters) {
    const promptVersion = voter.promptVersion ?? PROMPT_VERSION;
    const inputSha = computeInputSha({
      agent: voter.agent,
      provider: voter.provider,
      model: voter.model,
      promptVersion,
      imageSha: image?.sha256,
      textSha: photoText?.text_sha256,
      vocabVersion: sharedCtx.vocabVersion,
    });

    const { extraction, reused } = await getOrRunVoter(voter, inputSha, {
      rawText,
      images: image ? [image] : [],
      vocabShortlist,
      candidatesByField: candidatesByFieldSoFar,
    });
    if (!reused) spentUsd += Number(extraction.cost_usd ?? 0);

    const fieldsToStore = voter.isCritic
      ? Object.fromEntries(
          Object.entries(extraction.response?.verdicts ?? {}).map(([field, verdict]) => [
            field,
            { value: verdict, confidence: 1, evidence: verdict?.evidenceSpan },
          ]),
        )
      : extraction.response?.fields ?? {};

    await storeFieldCandidates(photo.id, extraction.id, voter.agent, fieldsToStore);

    if (!voter.isCritic) {
      for (const [field, cand] of Object.entries(fieldsToStore)) {
        (candidatesByFieldSoFar[field] ??= []).push({ agent: voter.agent, value: cand.value, confidence: cand.confidence, evidence: cand.evidence });
      }
    }
  }

  const result = await adjudicateAndApply(photo, photoText, sharedCtx);

  await query(
    `UPDATE photos SET state = 'processed', extraction_leased_until = NULL, extraction_leased_by = NULL, updated_at = now() WHERE id = $1`,
    [photo.id],
  );

  return { ...result, spentUsd };
}

// The SIGTERM-safe loop. Guarded by a process-wide advisory lock so a
// redeploy overlap never runs two workers at once; `jobId` (an
// `extraction_jobs` row) is optional and only used for progress/pause
// tracking from `POST /api/admin/jobs`.
export async function runWorker({ voters, limit = 20, spendCapUsd, jobId, workerId, log = console } = {}) {
  const lockClient = await pool.connect();
  let locked = false;
  try {
    const { rows: lockRows } = await lockClient.query('SELECT pg_try_advisory_lock($1) AS ok', [
      config.extraction.worker.advisoryLockKey,
    ]);
    locked = lockRows[0]?.ok === true;
    if (!locked) {
      // Close the job row out instead of leaving it at status='running'
      // forever. A refused worker used to return silently here, so a job whose
      // lock was held by an earlier (hung) worker looked identical to a job
      // that was actively working: 'running', photos_done 0, last_error null.
      // 'done' + last_error is the same shape markJobFailed() uses, and the
      // status CHECK constraint allows no 'failed' value.
      if (jobId) {
        await query(
          `UPDATE extraction_jobs SET status = 'done', finished_at = now(), last_error = $2
           WHERE id = $1 AND status = 'running'`,
          [jobId, 'not started: another worker holds the extraction advisory lock'],
        ).catch(() => {});
      }
      return { started: false, reason: 'already_running' };
    }

    const resolvedVoters = voters ?? (await defaultVoters());
    const sharedCtx = await loadSharedContext();

    let spentUsd = 0;
    let photosDone = 0;
    let stopped = null;

    while (photosDone < limit) {
      if (spendCapUsd != null && spentUsd >= spendCapUsd) {
        stopped = 'spend_cap';
        break;
      }
      if (jobId) {
        const { rows: jobRows } = await query('SELECT status FROM extraction_jobs WHERE id = $1', [jobId]);
        if (jobRows[0]?.status === 'paused') {
          stopped = 'paused';
          break;
        }
      }

      const batchSize = Math.min(config.extraction.worker.concurrency, limit - photosDone);
      const batch = await claimBatch(batchSize, { workerId });
      if (batch.length === 0) {
        stopped = 'no_work';
        break;
      }

      const results = await runWithConcurrency(batch, config.extraction.worker.concurrency, async (photo) => {
        try {
          return await processPhoto(photo, resolvedVoters, sharedCtx);
        } catch (err) {
          log.error?.(`[worker] photo ${photo.id} failed: ${err.message}`);
          // Also persist it: a per-photo failure used to exist ONLY in the
          // platform log stream, so from the API a job burning through photos
          // that all fail looked exactly like a job doing nothing
          // (photos_done 0, spent 0, last_error null). Anyone without log
          // access — including every lane session — had no way to see why.
          if (jobId) {
            await query(
              `UPDATE extraction_jobs SET last_error = $2 WHERE id = $1`,
              [jobId, `photo ${photo.id}: ${err.message}`.slice(0, 2000)],
            ).catch(() => {});
          }
          await releaseLease(photo.id);
          return null;
        }
      });

      const roundSpend = results.reduce((s, r) => s + (r?.spentUsd ?? 0), 0);
      const roundDone = results.filter(Boolean).length;
      spentUsd += roundSpend;
      photosDone += roundDone;

      if (jobId) {
        await query('UPDATE extraction_jobs SET spent_usd = spent_usd + $1, photos_done = photos_done + $2 WHERE id = $3', [
          roundSpend,
          roundDone,
          jobId,
        ]);
      }
    }

    if (jobId) {
      await query(`UPDATE extraction_jobs SET status = 'done', finished_at = now() WHERE id = $1 AND status = 'running'`, [jobId]);
    }
    return { started: true, stopped, spentUsd, photosDone };
  } finally {
    if (locked) await lockClient.query('SELECT pg_advisory_unlock($1)', [config.extraction.worker.advisoryLockKey]);
    lockClient.release();
  }
}

// Re-adjudicates every photo that has at least one stored field_candidates
// row (i.e. has been through the worker at least once), or just `photoId`
// when given. No voter runs -- $0, per PLAN.md §2.
export async function readjudicateAll({ photoId } = {}) {
  const sharedCtx = await loadSharedContext();
  const { rows: photos } = await query(
    photoId
      ? `SELECT * FROM photos WHERE id = $1`
      : `SELECT DISTINCT p.* FROM photos p JOIN field_candidates fc ON fc.photo_id = p.id`,
    photoId ? [photoId] : [],
  );

  let count = 0;
  for (const photo of photos) {
    const photoText = await fetchLatestText(photo.id);
    await adjudicateAndApply(photo, photoText, sharedCtx);
    count += 1;
  }
  return { photosReadjudicated: count };
}
