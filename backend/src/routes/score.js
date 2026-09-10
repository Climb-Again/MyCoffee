// POST /api/score -- the browsing score (#160, spec #159).
//
// Scores a coffee Radu is looking at on a shop website, from the page's own
// text. Radu's locked decisions (2026-09-04/05): the browser extension is the
// primary surface for evaluating a coffee while browsing, it scores the
// CURRENT page only, comparatively against his own tasted library, and roast
// date counts -- closer to today is better.
//
// Three things this route deliberately does NOT do:
//
//  1. **No LLM.** Radu's cost rule for this feature is explicit:
//     deterministic-first, "so a paid LLM voter can't fire on every page
//     view". This runs `extractRuleFields` -- the same free rules voter the
//     batch worker runs first -- and nothing else. `spentUsd` is always 0.
//     A shop listing is structured prose with the roaster and price written
//     plainly, which is the case the deterministic layer is best at; the LLM
//     ensemble exists for photographed bags, which this is not.
//
//  2. **No writes, and no photo rows.** Scoring is ephemeral. Note that
//     routing this through the existing upload path would have been actively
//     harmful, not merely wasteful: `POST /api/photos/manifest` leaves a photo
//     in `text_received`/`awaiting_text` (`routes/photos.js:156`) and
//     `claimBatch` claims exactly those states, so every page browsed would
//     become a coffee in the library via `upsertCoffeeBase`.
//
//  3. **No second scorer.** The blend, the shrinkage, the percentile and the
//     confidence gate all come from `lib/scoring.js` (#106) via
//     `lib/corpus.js`, so this endpoint and the in-app evaluate screen can
//     never disagree about the same bag. The only thing added here is roast
//     recency, which #106 never had -- bounded to 10 points because, unlike
//     the other four signals, it has no leave-one-out validation behind it.
import { createHash } from 'node:crypto';
import { requireAnyToken } from '../auth.js';
import { query } from '../db.js';
import { extractRuleFields } from '../lib/deterministic.js';
import { canonicalize } from '../lib/adjudicate.js';
import { loadSharedContext } from '../lib/worker.js';
import { loadScoringCorpus, groupsForCandidate, loadNovelty } from '../lib/corpus.js';
import { loadRoasterCoffees, rankMatches, diffFields, genericTokensFromVocab } from '../lib/enrich.js';
import { toEur } from '../lib/fx.js';
import { evaluateCoffee, ROAST_FRESH_DAYS } from '../lib/scoring.js';

// A product page that yields less than this is a nav shell or a cookie wall,
// not a listing -- scoring it would return a confident-looking global average.
const MIN_TEXT_CHARS = 40;
// Generous, but bounded: `extractRuleFields` runs several regex scans over the
// whole string and this is an unauthenticated-shaped payload from a browser.
const MAX_TEXT_CHARS = 200_000;

// Same page scored twice (a tab revisited, the popup reopened) reuses the
// result. Keyed by text, not URL: shop pages carry cart counts and session ids
// in the query string, and the text is what the score is actually a function
// of. Small and in-process on purpose -- Railway runs one container, and a
// cold start recomputing a few scores costs nothing.
const CACHE_MAX = 200;
const CACHE_TTL_MS = 10 * 60_000;
const _cache = new Map();

function cacheGet(key) {
  const hit = _cache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.at > CACHE_TTL_MS) {
    _cache.delete(key);
    return null;
  }
  // Refresh LRU position.
  _cache.delete(key);
  _cache.set(key, hit);
  return hit.value;
}

function cacheSet(key, value) {
  _cache.set(key, { at: Date.now(), value });
  while (_cache.size > CACHE_MAX) _cache.delete(_cache.keys().next().value);
}

export function clearScoreCache() {
  _cache.clear();
}

// Human-readable "why", built from the same numbers the breakdown carries so
// the sentence can never contradict the bars above it.
export function explain({ evaluation, recency, days, fields, names }) {
  const parts = [];
  const affinity = evaluation.components.affinity.score;

  if (names.roaster && fields.isNewRoaster != null) {
    parts.push(
      fields.isNewRoaster
        ? `${names.roaster} is a roaster you haven't bought from`
        : `you've bought ${names.roaster} before`,
    );
  }
  if (names.origin && fields.isNewOrigin != null) {
    parts.push(fields.isNewOrigin ? `${names.origin} is a new origin for you` : `${names.origin} is familiar ground`);
  }

  if (affinity >= 70) parts.push(`this profile sits in the top ${100 - affinity}% of what you rate well`);
  else if (affinity <= 30) parts.push(`this profile ranks below most of your library`);

  const value = evaluation.components.value;
  if (value == null) {
    parts.push(
      fields.pricePer100gEur == null
        ? 'no usable price on the page, so the value half is missing — and value is the half that carries the most weight'
        : 'too few rated bags at this price for a value read',
    );
  } else if (value.pillCount >= 4) parts.push('good value for what you normally pay at this price');
  else if (value.pillCount <= 2) parts.push('pricey next to bags you rate the same');

  if (recency != null) {
    if (days <= ROAST_FRESH_DAYS) parts.push(`roasted ${days} day${days === 1 ? '' : 's'} ago`);
    else parts.push(`roasted ${days} days ago`);
  }

  if (evaluation.score == null) {
    parts.push(
      evaluation.confidence === 'low'
        ? "too little history on this roaster, origin and process to put a number on it"
        : 'no headline number without a price',
    );
  }

  if (parts.length === 0) return 'Nothing on this page matched anything in your library.';
  return parts.join('; ').replace(/^./, (c) => c.toUpperCase()) + '.';
}

export default async function scoreRoutes(app) {
  // requireAnyToken, NOT requireIngestToken: scoring is read-only, and the
  // extension has to carry whatever token it calls with in `chrome.storage`,
  // readable by anything that can read the browser profile. There is no reason
  // for that to be the token that authorizes every write in the app.
  app.post('/api/score', { preHandler: requireAnyToken }, async (req, reply) => {
    const rawText = typeof req.body?.text === 'string' ? req.body.text : '';
    const url = typeof req.body?.url === 'string' ? req.body.url.slice(0, 2048) : null;
    // #161 matches on the page's own title. Optional: without it the score is
    // unchanged and only the "you already own this" half is skipped.
    const title = typeof req.body?.title === 'string' ? req.body.title.slice(0, 500).trim() : '';
    const text = rawText.slice(0, MAX_TEXT_CHARS).trim();

    if (text.length < MIN_TEXT_CHARS) {
      return reply.code(400).send({ error: 'missing_text', minChars: MIN_TEXT_CHARS });
    }

    const cacheKey = createHash('sha256').update(`${title}\u0000${text}`).digest('hex');
    const cached = cacheGet(cacheKey);
    if (cached) return { ...cached, cached: true };

    const shared = await loadSharedContext();
    const rules = extractRuleFields(text, {
      roasterVocab: shared.vocab.roasters,
      countryVocab: shared.vocab.countries,
    });

    // `photoDate` anchors relative/partial dates; a page is being read now, so
    // "now" is the honest anchor (the photo path uses the capture date).
    const ctx = { vocab: shared.vocab, rawText: text, photoDate: new Date() };
    const canon = (field) => canonicalize(field, rules[field]?.value ?? null, ctx);

    const roaster = canon('roaster_id');
    const origins = canon('origin_country_ids');
    const profile = canon('profile');
    const price = canon('price');
    const weight = canon('weight_g');
    const roasted = canon('roasted_on');
    // Extracted for #161's enrich diff rather than for the score: neither
    // altitude nor farm is a scoring signal (#106 measured altitude at
    // r=-0.02), but both are fields a shop page routinely has and a stored
    // record routinely lacks.
    const altitude = canon('altitude');
    const farm = canon('origin_farm_id');

    const roasterId = roaster?.id ?? null;
    const originCountryIds = origins?.ids ?? [];
    const originCountryId = originCountryIds[0] ?? null;
    // Slug -> SMALLINT: `coffees.profile_id` is numeric, `parseProfile` returns
    // a slug. Skipping this mapping is what silently disabled the process
    // signal on /api/coffees/evaluate (see that route's own note).
    const profileSlug = profile?.profileId ?? null;
    const profileDbId = profileSlug != null ? (shared.profileIdBySlug?.get(profileSlug) ?? null) : null;

    let roasterCountryId = null;
    if (roasterId != null) {
      const { rows } = await query(`SELECT country_id FROM roasters WHERE id = $1`, [roasterId]);
      roasterCountryId = rows[0]?.country_id ?? null;
    }

    // Price needs an amount AND a recognised currency AND a weight -- all
    // three, or there is no €/100g and the value half (0.50 of the headline)
    // is gone. Reported per-condition below so the extension can say which one
    // the page was missing instead of silently scoring on affinity alone.
    const weightG = weight?.grams ?? null;
    let pricePer100gEur = null;
    if (price?.amount != null && price?.currency && weightG > 0) {
      const conv = toEur({ amount: price.amount, currency: price.currency, date: new Date() }, shared.fxRates);
      if (conv?.priceEur != null) {
        pricePer100gEur = Math.round((conv.priceEur / weightG) * 100 * 100) / 100;
      }
    }

    const { globalMean, pricedRows, stats, affinitySamples } = await loadScoringCorpus();
    const groups = groupsForCandidate(stats, {
      roasterId,
      originCountryId,
      profileId: profileDbId,
      roasterCountryId,
    });
    const { isNewRoaster, isNewOrigin } = await loadNovelty({ roasterId, originCountryId });

    // Roast date goes INTO the scorer (#188), not on top of it: it is a
    // weighted term now, and keeping it inside `evaluateCoffee` is what stops
    // this endpoint and /api/coffees/evaluate drifting apart.
    const roastedOn = roasted?.date ?? null;
    const evaluation = evaluateCoffee({
      groups,
      globalMean,
      priced: pricedRows,
      affinitySamples,
      pricePer100gEur,
      isNewRoaster,
      isNewOrigin,
      roastedOn,
    });

    const score = evaluation.score;
    const days = evaluation.components.roast?.daysSinceRoast ?? null;
    const recency = evaluation.components.roast?.score ?? null;

    const names = {
      roaster: roasterId != null ? nameFrom(shared.vocab.roasters, roasterId) : null,
      origin: originCountryId != null ? nameFrom(shared.vocab.countries, originCountryId) : null,
    };

    // #161: is this a coffee he ALREADY owns, and if so what can the page add?
    //
    // Gated on a known roaster and a page title. Without both, matching would
    // be guesswork, and a false "you own this" is the one failure mode worth
    // designing against -- it would invite him to write page data onto the
    // wrong record. Costs one small query (a roaster has a handful of
    // coffees), and only when the roaster resolved.
    let match = null;
    let enrich = [];
    if (roasterId != null && title) {
      const candidates = await loadRoasterCoffees(roasterId);
      const ranked = rankMatches({ title, originCountryId }, candidates, {
        roasterName: names.roaster,
        genericTokens: genericTokensFromVocab(shared.vocab.countries),
      });
      const best = ranked[0];
      if (best) {
        const pageFields = {
          originCountryName: names.origin,
          farmName: farm?.name ?? (farm?.id != null ? nameFrom(shared.vocab.farms, farm.id) : null),
          profileId: profileSlug,
          profileDetail: profile?.detail ?? null,
          roastedOn: roasted?.date ?? null,
          weightG,
          priceAmount: price?.amount ?? null,
          priceCurrency: price?.currency ?? null,
          altitudeMin: altitude?.min ?? null,
          altitudeMax: altitude?.max ?? null,
          altitudeNeedsReview: Boolean(altitude?.needsReview),
        };
        enrich = diffFields(pageFields, best);
        match = {
          id: best.id,
          rawTitle: best.rawTitle,
          purchasedOn: best.purchasedOn,
          rating: best.rating,
          isFavorite: best.isFavorite,
          confidence: best.confidence,
          matchedOn: best.sharedTokens,
          originAgrees: best.originAgrees,
          alternatives: ranked.slice(1, 4).map((r) => ({
            id: r.id,
            rawTitle: r.rawTitle,
            purchasedOn: r.purchasedOn,
            rating: r.rating,
            matchedOn: r.sharedTokens,
          })),
        };
      }
    }

    const result = {
      url,
      score,
      confidence: evaluation.confidence,
      components: {
        ...evaluation.components,
        // `evaluateCoffee` coerces unknown novelty to false for the blend;
        // the response keeps the nullable truth so the UI can stay silent
        // about a field the page never gave us, rather than calling an
        // unreadable origin "new".
        novelty: { isNewRoaster, isNewOrigin },
      },
      fields: {
        roasterId,
        roasterName: names.roaster,
        originCountryIds,
        originName: names.origin,
        profileId: profileSlug,
        roasterCountryId,
        pricePer100gEur,
        weightG,
        priceAmount: price?.amount ?? null,
        priceCurrency: price?.currency ?? null,
        roastedOn,
      },
      // What the page failed to give us, so the UI can ask for it rather than
      // quietly returning a weaker number.
      missing: {
        price: price?.amount == null,
        currency: Boolean(price?.amount != null && !price?.currency),
        weight: !(weightG > 0),
        roastDate: roastedOn == null,
      },
      // #161. `match` is null when this is a coffee he does not own, and
      // `enrich` is [] when the page adds nothing to one he does -- the popup
      // must render that as silence, not as an empty panel.
      match,
      enrich,
      explanation: explain({
        evaluation,
        recency,
        days,
        fields: { pricePer100gEur, isNewRoaster, isNewOrigin },
        names,
      }),
      spentUsd: 0,
    };

    cacheSet(cacheKey, result);
    return { ...result, cached: false };
  });
}

function nameFrom(vocab, id) {
  return (vocab?.candidates ?? []).find((c) => c.id === id)?.name ?? null;
}
