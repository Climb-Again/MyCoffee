# Lane: Data extract + validate

Branch: `main` · Ownership + protocol: `status/README.md` · Work items: `PLAN.md`

## Claimed

- [2026-08-01 01:40 UTC] #14 `src/lib/vocab.js` — resolution (exact alias + fuzzy
  fallback) against the 004_vocab.sql tables, plus origin_country_ids array
  referential-integrity enforcement — branch `claude/peaceful-mccarthy-rwi2ql`

## Done

- [2026-07-31 07:30 UTC] #12 + #13 + #34 — **consolidated onto `main`** from three
  stranded fired-session branches that each redid the same work in isolation because
  `main` never advanced (see the "un-integrated prior work" rule in `status/README.md`).
  Rebuilt cleanly on current `main` and validated end-to-end against a real Postgres
  16 (migrations 001→007 applied, fx seed loaded, full `node --test` suite 59/59 green):
  - **#12 — `backend/migrations/005_vocab_seed.sql`** (from `claude/peaceful-mccarthy-o8kxxo`,
    orig `63598f7`). Seeds against the real `004_vocab.sql` schema: **42 countries**
    (26 origin), **89 roasters**, 47 country aliases, 101 roaster aliases. Values
    extracted from `brief/MyCoffee app.docx` in `Climb-Again/mycoffee-private` — the
    docx itself is never copied here (public-repo rule).
  - **#13 — `backend/src/lib/normalize.js` + `fuzzy.js` + tests** (o8kxxo, orig `119362c`).
    Pure parsers/matchers; `normalize.test.js` + `fuzzy.test.js` table-driven, all green.
    This branch's API is now the contract downstream (#14 vocab.js, extraction) builds on:
    `normalize` exports `normalizeVocabString/foldDiacritics/parseNumber/parseAltitude/`
    `parsePrice/parseWeight/parseRating/parseDate/parseProfile/parseFarm/resolveCityCountry`;
    `fuzzy` exports `levenshteinDistance/normalizedLevenshteinSimilarity/trigramSimilarity/matchVocab`.
  - **#34 — `ops/fx_rates_seed.sql` + `ops/seed-fx-rates.mjs`** (o8kxxo, orig `79f654f`)
    **plus `backend/src/lib/fx.js` + `test/fx.test.js`** (from `claude/peaceful-mccarthy-toj6mv`,
    orig `eb2ffa4` — the only branch with the tested conversion helper). Seed loads
    **1510 rows** (10 currencies × 151 ECB monthly averages). **Inversion direction
    verified live** against `BACKLOG.md`'s anchors — RON `rate_to_eur`: 2015-01 =
    `0.222845`, 2019-06 = `0.211640`, 2024-06 = `0.200935` (i.e. ~0.22, not ~4.49);
    all 10 currencies land in sane EUR ranges. The seed is applied manually
    (`psql -f ops/fx_rates_seed.sql`), **not** in the auto-run migration chain, per
    006's own comment.
  - `fx.js` satisfies the `fx.js` half of backend #14 (data lane owns `src/lib/fx.js`
    per the ownership table); #14 now needs only `vocab.js`. — branch `main`

## Superseded / to delete

The three source branches below are now fully consolidated onto `main` and hold no
unique un-landed work. Safe for Radu to delete once this lands:
`claude/peaceful-mccarthy-o8kxxo`, `claude/peaceful-mccarthy-toj6mv`,
`claude/peaceful-mccarthy-n4nt4i` (n4nt4i was a strict subset — #12 + #13 only, no fx).

## Abandoned

_none_
