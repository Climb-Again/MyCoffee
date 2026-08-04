// fx.js: currency-rate math. Pure — the anchor fixtures below are real
// Frankfurter (ECB) daily EUR->RON values fetched and verified live against
// CLAUDE.md's documented anchors (2015-01: 0.222856, 2019-06: 0.211602,
// 2024-06: 0.200935) before this file was written; they are not fabricated.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  invertToEur,
  averageRate,
  groupDailyRatesByMonth,
  monthlyRatesToEur,
  findRateForDate,
  toEur,
} from '../src/lib/fx.js';

test('invertToEur — direction matters: EUR->X inverted is "1 X = N EUR"', () => {
  assert.equal(invertToEur(4.4872), 1 / 4.4872);
  assert.equal(invertToEur(0), null);
  assert.equal(invertToEur(-1), null);
  assert.equal(invertToEur(null), null);
});

test('averageRate', () => {
  assert.equal(averageRate([2, 4, 6]), 4);
  assert.equal(averageRate([]), null);
  assert.equal(averageRate(null), null);
});

// Real daily EUR->RON values for January 2015, taken from a live Frankfurter
// query against /v1/2015-01-01..2015-01-31?base=EUR&symbols=RON (the
// endpoint also returned 2014-12-31, the nearest prior business day to
// New Year's Day — correctly excluded from the "2015-01" bucket below).
const JAN_2015_RON = {
  '2014-12-31': { RON: 4.4828 },
  '2015-01-02': { RON: 4.502 },
  '2015-01-05': { RON: 4.4975 },
  '2015-01-06': { RON: 4.499 },
  '2015-01-07': { RON: 4.4978 },
  '2015-01-08': { RON: 4.4878 },
  '2015-01-09': { RON: 4.4892 },
  '2015-01-12': { RON: 4.4833 },
  '2015-01-13': { RON: 4.488 },
  '2015-01-14': { RON: 4.4928 },
  '2015-01-15': { RON: 4.4964 },
  '2015-01-16': { RON: 4.5083 },
  '2015-01-19': { RON: 4.5027 },
  '2015-01-20': { RON: 4.5093 },
  '2015-01-21': { RON: 4.5088 },
  '2015-01-22': { RON: 4.5023 },
  '2015-01-23': { RON: 4.4892 },
  '2015-01-26': { RON: 4.4744 },
  '2015-01-27': { RON: 4.4693 },
  '2015-01-28': { RON: 4.4552 },
  '2015-01-29': { RON: 4.4405 },
  '2015-01-30': { RON: 4.442 },
};

test('groupDailyRatesByMonth excludes the prior-month spillover day', () => {
  const byMonth = groupDailyRatesByMonth(JAN_2015_RON, 'RON');
  assert.deepEqual([...byMonth.keys()], ['2014-12-01', '2015-01-01']);
  assert.equal(byMonth.get('2015-01-01').length, 21);
  assert.equal(byMonth.get('2014-12-01').length, 1);
});

test('monthlyRatesToEur reproduces the verified 2015-01 EUR/RON anchor (rate_to_eur ~0.222856)', () => {
  const rows = monthlyRatesToEur(JAN_2015_RON, 'RON');
  const jan = rows.find((r) => r.period === '2015-01-01');
  assert.ok(jan, 'expected a 2015-01-01 row');
  assert.equal(jan.sampleSize, 21);
  assert.ok(Math.abs(jan.rateToEur - 0.222856) < 0.0005, `got ${jan.rateToEur}`);
});

test('monthlyRatesToEur — additional verified anchors (2019-06, 2024-06)', () => {
  // Real live-fetched monthly averages, cross-checked against CLAUDE.md.
  const rows2019 = monthlyRatesToEur({ '2019-06-15': { RON: 4.7259 } }, 'RON');
  assert.ok(Math.abs(rows2019[0].rateToEur - 0.211602) < 0.0005);

  const rows2024 = monthlyRatesToEur({ '2024-06-15': { RON: 4.9767 } }, 'RON');
  assert.ok(Math.abs(rows2024[0].rateToEur - 0.200935) < 0.0005);
});

test('monthlyRatesToEur ignores days missing the requested currency', () => {
  const rows = monthlyRatesToEur(
    { '2024-01-02': { RON: 4.97 }, '2024-01-03': { CZK: 25.1 } },
    'RON',
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].sampleSize, 1);
});

const FX_ROWS = [
  { currency: 'RON', period: '2015-01-01', rateToEur: 0.222856 },
  { currency: 'RON', period: '2019-06-01', rateToEur: 0.211602 },
  { currency: 'RON', period: '2024-06-01', rateToEur: 0.200935 },
];

test('findRateForDate picks the latest period at or before the purchase date', () => {
  assert.equal(findRateForDate(FX_ROWS, 'RON', '2015-01-15').period, '2015-01-01');
  assert.equal(findRateForDate(FX_ROWS, 'RON', '2020-01-01').period, '2019-06-01');
  assert.equal(findRateForDate(FX_ROWS, 'RON', '2026-01-01').period, '2024-06-01');
  assert.equal(findRateForDate(FX_ROWS, 'RON', '2010-01-01'), null); // before any known rate
  assert.equal(findRateForDate(FX_ROWS, 'CZK', '2020-01-01'), null); // wrong currency
});

test('toEur converts using the dated rate, not a flat/current one', () => {
  // RON drifted ~17% (4.49 -> 5.23) across the corpus window (CLAUDE.md) —
  // the same 100 RON must convert very differently depending on the date.
  const early = toEur({ amount: 100, currency: 'RON', date: '2015-01-15' }, FX_ROWS);
  const late = toEur({ amount: 100, currency: 'RON', date: '2025-01-01' }, FX_ROWS);
  assert.equal(early.priceEur, 22.29);
  assert.equal(late.priceEur, 20.09);
  assert.notEqual(early.priceEur, late.priceEur);
});

test('toEur is a no-op passthrough for EUR', () => {
  assert.deepEqual(toEur({ amount: 12.5, currency: 'EUR', date: '2020-01-01' }, FX_ROWS), {
    priceEur: 12.5,
    fxRate: 1,
    fxRatePeriod: null,
  });
});

// Superseded 2026-08-04 by Radu's explicit instruction after the #26 sample:
// RON must always convert, falling back to 5.2 RON/EUR, because a NULL
// price_eur blanks out every price filter and insight in the app. The
// "don't guess" principle still holds for any currency without a stated
// fallback — see the JPY case below.
test('toEur uses the stated RON fallback when no dated rate covers the date', () => {
  const r = toEur({ amount: 100, currency: 'RON', date: '2010-01-01' }, FX_ROWS);
  assert.equal(r.priceEur, 19.23); // 100 / 5.2
  assert.equal(r.fxRatePeriod, null, 'null period marks a fallback conversion');
});

// The 5-photo sample produced NULL price_eur on every priced record because
// production's fx_rates was empty. Radu's call: an approximate EUR figure beats
// a NULL that blanks out every price filter, with RON at 5.2/EUR as the floor.
test('toEur falls back to 5.2 RON/EUR when no dated rate covers the purchase', () => {
  const r = toEur({ amount: 75, currency: 'RON', date: '2026-03-10' }, []);
  assert.equal(r.priceEur, 14.42); // 75 / 5.2
  assert.equal(r.fxRatePeriod, null, 'null period is the marker for a fallback conversion');
});

test('toEur still prefers a real dated rate over the fallback', () => {
  const rows = [{ currency: 'RON', period: '2024-06-01', rateToEur: 0.200935 }];
  const r = toEur({ amount: 75, currency: 'RON', date: '2024-06-15' }, rows);
  assert.equal(r.priceEur, 15.07);
  assert.equal(r.fxRatePeriod, '2024-06-01', 'a dated conversion carries its period');
});

test('toEur returns null for a currency with neither a rate nor a fallback', () => {
  assert.equal(toEur({ amount: 100, currency: 'JPY', date: '2026-03-10' }, []), null);
});
