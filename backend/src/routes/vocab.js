// POST /api/vocab/observations — #198: grow the VOCAB from browsing, never the
// coffee library.
//
// Radu, 2026-09-12: "add new items to database (not to my coffees!! just save to
// database so we have them later): roaster overview, origin/roaster country (if
// new country), roaster logo".
//
// Today `roasters` and `countries` only grow when a human accepts a review row
// (#36) or migration 034's self-heal fires. That is right for coffees — a page
// Radu merely looked at must never become a coffee — but needlessly cautious for
// the vocab itself: while browsing, the extension routinely sees a roaster's
// About page, a country in a bio, or a logo `<img>`, and there is no reason a
// later coffee should have to re-extract them.
//
// Three hard rules, each of which is a bug if broken:
//
//   1. **Nothing here ever touches `coffees`.** Not one statement in this file
//      writes that table. That is the literal text of the ask.
//   2. **An existing value is never overwritten.** Every write is guarded on
//      `IS NULL`. A blurb Radu edited in-app (#153) or a logo curated through
//      `ops/roaster-assets/` outranks anything a shop page says about itself.
//   3. **Countries stay a CLOSED list.** A country name that does not resolve
//      becomes nothing at all; a name that resolves but was spelled differently
//      becomes an ALIAS on the existing row. Minting `countries` rows from
//      scraped text is how you end up with Congo, DR Congo and DRC as three
//      origins — and CLAUDE.md §12's alias trap means a fresh country row with
//      no alias is invisible to extraction anyway.
import { requireIngestToken } from '../auth.js';
import { query } from '../db.js';
import { getOrCreateVocabEntry } from '../lib/resolveField.js';
import { loadCountryVocab, loadRoasterVocab } from '../lib/vocab.js';
import { canonicalize } from '../lib/adjudicate.js';
import { normalizeVocabString } from '../lib/normalize.js';

// A scraped string that is absurdly long is a scrape gone wrong (a whole page
// body caught by a bad selector), not a roaster name. Bound everything.
const MAX_NAME = 120;
const MAX_BLURB = 2000;
const MAX_URL = 1000;

function clean(value, max) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().replace(/\s+/g, ' ');
  if (!trimmed || trimmed.length > max) return null;
  return trimmed;
}

// Only ever an absolute http(s) URL: a relative or `javascript:` src scraped off
// a page must not reach `roasters.logo_url`, which the app renders directly.
function cleanHttpUrl(value) {
  const raw = clean(value, MAX_URL);
  if (!raw) return null;
  try {
    const u = new URL(raw);
    return /^https?:$/.test(u.protocol) ? u.toString() : null;
  } catch {
    return null;
  }
}

async function record(kind, { targetId = null, sourceUrl = null, value = null, applied = false }) {
  await query(
    `INSERT INTO vocab_observations (kind, target_id, source_url, extracted_value, applied)
     VALUES ($1, $2, $3, $4, $5)`,
    [kind, targetId, sourceUrl, value != null ? String(value).slice(0, MAX_BLURB) : null, applied],
  );
}

export default async function vocabRoutes(app) {
  app.post('/api/vocab/observations', { preHandler: requireIngestToken }, async (req, reply) => {
    const body = req.body;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return reply.code(400).send({ error: 'bad_observation' });
    }

    const sourceUrl = cleanHttpUrl(body.sourceUrl);
    const roasterIn = body.roaster && typeof body.roaster === 'object' ? body.roaster : null;
    const originCountryName = clean(body.originCountryName, MAX_NAME);

    if (!roasterIn && !originCountryName) {
      return reply.code(400).send({ error: 'nothing_to_observe' });
    }

    const [countryVocab, roasterVocab] = await Promise.all([loadCountryVocab(query), loadRoasterVocab(query)]);
    const ctx = { vocab: { countries: countryVocab, roasters: roasterVocab } };

    const result = { roasterId: null, created: [], updated: [], declined: [] };

    // ---- roaster ----
    if (roasterIn) {
      const name = clean(roasterIn.name, MAX_NAME);
      if (name) {
        const resolved = canonicalize('roaster_id', name, ctx);
        let roasterId = resolved?.id ?? null;
        if (roasterId == null) {
          // Same get-or-create a human accept uses (#36). This also inserts the
          // alias, without which the new roaster would be unmatchable from text
          // forever (CLAUDE.md §12).
          roasterId = await getOrCreateVocabEntry('roaster_id', name);
          if (roasterId != null) result.created.push('roaster');
        }
        result.roasterId = roasterId;
        await record('roaster', { targetId: roasterId, sourceUrl, value: name, applied: roasterId != null });

        if (roasterId != null) {
          const { rows } = await query(`SELECT blurb, logo_url, country_id FROM roasters WHERE id = $1`, [roasterId]);
          const current = rows[0] ?? {};

          const blurb = clean(roasterIn.description, MAX_BLURB);
          if (blurb) {
            // `blurb IS NULL` — rule 2. An in-app edit or a curated blurb wins.
            const { rowCount } = await query(
              `UPDATE roasters SET blurb = $1 WHERE id = $2 AND blurb IS NULL`,
              [blurb, roasterId],
            );
            if (rowCount) result.updated.push('blurb');
            else result.declined.push('blurb');
            await record('roaster_blurb', { targetId: roasterId, sourceUrl, value: blurb, applied: Boolean(rowCount) });
          }

          const logoUrl = cleanHttpUrl(roasterIn.logoUrl);
          if (logoUrl) {
            const { rowCount } = await query(
              `UPDATE roasters SET logo_url = $1 WHERE id = $2 AND logo_url IS NULL`,
              [logoUrl, roasterId],
            );
            if (rowCount) result.updated.push('logo');
            else result.declined.push('logo');
            await record('roaster_logo', { targetId: roasterId, sourceUrl, value: logoUrl, applied: Boolean(rowCount) });
          }

          const countryName = clean(roasterIn.countryName, MAX_NAME);
          if (countryName) {
            const country = canonicalize('roaster_country_id', countryName, ctx);
            const countryId = country?.id ?? null;
            if (countryId != null) {
              const { rowCount } = await query(
                `UPDATE roasters SET country_id = $1 WHERE id = $2 AND country_id IS NULL`,
                [countryId, roasterId],
              );
              if (rowCount) result.updated.push('country');
              else result.declined.push('country');
              await record('roaster_country', {
                targetId: roasterId,
                sourceUrl,
                value: countryName,
                applied: Boolean(rowCount),
              });
            } else {
              // Rule 3: an unresolvable country is declined, never created.
              result.declined.push('country');
              await record('roaster_country', { targetId: roasterId, sourceUrl, value: countryName, applied: false });
            }
          }
        }
      }
    }

    // ---- origin country: alias proposals only, never a new country row ----
    if (originCountryName) {
      const country = canonicalize('origin_country_ids', originCountryName, ctx);
      // canonicalize returns an array of ids for this field; a single scraped
      // mention resolving to exactly one country is the only case worth an
      // alias — two means the string was ambiguous, and ambiguity never
      // auto-resolves (the same rule #48(b)'s roaster-country override uses).
      const ids = Array.isArray(country?.ids) ? country.ids : [];
      const aliasNorm = normalizeVocabString(originCountryName);
      if (ids.length === 1 && aliasNorm) {
        const { rowCount } = await query(
          `INSERT INTO country_aliases (country_id, alias, alias_norm)
           VALUES ($1, $2, $3) ON CONFLICT (alias_norm) DO NOTHING`,
          [ids[0], originCountryName, aliasNorm],
        );
        if (rowCount) result.created.push('country_alias');
        await record('country_alias', {
          targetId: ids[0],
          sourceUrl,
          value: originCountryName,
          applied: Boolean(rowCount),
        });
      } else {
        result.declined.push('originCountry');
        await record('origin_country', { sourceUrl, value: originCountryName, applied: false });
      }
    }

    return result;
  });
}
