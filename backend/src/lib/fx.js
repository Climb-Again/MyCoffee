// Currency-rate math (PLAN.md §1, "Currency must be dated"). Pure — no DB,
// no network. Callers (the ops/ seeding script, and later the runtime
// price-to-EUR lookup) supply the raw Frankfurter response or the stored
// `fx_rates` rows; nothing here fetches or persists anything itself.
//
// Frankfurter's time series is EUR-per-1-unit-of-quote (e.g. EUR->RON);
// `fx_rates.rate_to_eur` is defined the other way, "1 unit of X = N EUR", so
// every rate gets inverted exactly once, here, at seed time. Get the
// direction wrong and every historical RON/CZK/… price comes out roughly
// 4-25x too large — see the verified anchors in fx.test.js.

export function invertToEur(eurToQuoteRate) {
  if (typeof eurToQuoteRate !== 'number' || !(eurToQuoteRate > 0)) return null;
  return 1 / eurToQuoteRate;
}

export function averageRate(values) {
  if (!Array.isArray(values) || values.length === 0) return null;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

// Groups a Frankfurter EUR-base time series ({date: {CUR: value, ...}}) into
// a Map of first-of-month period -> [daily EUR->currency values].
export function groupDailyRatesByMonth(ratesByDate, currency) {
  const byMonth = new Map();
  for (const [date, dayRates] of Object.entries(ratesByDate ?? {})) {
    const value = dayRates?.[currency];
    if (typeof value !== 'number') continue;
    const period = `${date.slice(0, 7)}-01`;
    if (!byMonth.has(period)) byMonth.set(period, []);
    byMonth.get(period).push(value);
  }
  return byMonth;
}

// Full pipeline for one currency: Frankfurter's EUR-base time series ->
// [{ period, rateToEur, sampleSize }], sorted ascending by period. Only
// ECB business days are present in the source, so sampleSize is ~19-23 for
// a full month and smaller at the range's edges — never fabricated.
export function monthlyRatesToEur(ratesByDate, currency) {
  const byMonth = groupDailyRatesByMonth(ratesByDate, currency);
  return [...byMonth.entries()]
    .map(([period, values]) => ({
      period,
      rateToEur: invertToEur(averageRate(values)),
      sampleSize: values.length,
    }))
    .filter((row) => row.rateToEur != null)
    .sort((a, b) => (a.period < b.period ? -1 : a.period > b.period ? 1 : 0));
}

// Runtime lookup: the latest period at or before `dateStr` for `currency`.
// `rows` is whatever the caller already loaded from `fx_rates`, shaped
// { currency, period, rateToEur }. A purchase date within a given month
// uses that month's average rate.
export function findRateForDate(rows, currency, dateStr) {
  if (!dateStr) return null;
  const period = `${String(dateStr).slice(0, 7)}-01`;
  let best = null;
  for (const row of rows ?? []) {
    if (row.currency !== currency || row.period > period) continue;
    if (!best || row.period > best.period) best = row;
  }
  return best;
}

// { amount, currency, date } -> EUR, using the rate that applied when the
// coffee was actually bought — never today's rate (PLAN.md §1: a flat rate
// misprices a 2015 RON purchase by ~11%).
// Last-resort rates, used only when no dated ECB row covers the purchase.
// Radu's call: a price that exists must convert, so an approximate EUR figure
// beats a NULL that blanks out every price filter and insight in the app. RON
// at 5.2/EUR is his stated fallback. `fxRatePeriod: null` is the tell that a
// row was converted this way rather than from a dated rate — real rates always
// carry their period — so these are findable later if the seed lands.
export const FALLBACK_RATES_TO_EUR = {
  RON: 1 / 5.2,
};

export function toEur({ amount, currency, date }, rows) {
  if (typeof amount !== 'number') return null;
  if (currency === 'EUR') return { priceEur: amount, fxRate: 1, fxRatePeriod: null };

  const match = findRateForDate(rows, currency, date);
  if (match) {
    return {
      priceEur: Math.round(amount * match.rateToEur * 100) / 100,
      fxRate: match.rateToEur,
      fxRatePeriod: match.period,
    };
  }

  const fallback = FALLBACK_RATES_TO_EUR[currency];
  if (fallback == null) return null;
  return {
    priceEur: Math.round(amount * fallback * 100) / 100,
    fxRate: fallback,
    fxRatePeriod: null,
  };
}
