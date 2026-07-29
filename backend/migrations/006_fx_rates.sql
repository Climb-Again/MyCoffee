-- 006_fx_rates.sql — monthly FX rates to EUR, so a historical price is
-- converted at the rate that applied when it was paid rather than today's
-- rate (PLAN.md §1: RON/EUR alone moved ~11% from 2015 to 2026).
--
-- Structure only — no rows. The seed (ECB monthly averages for RON, CZK, PLN,
-- HUF, SEK, DKK, NOK, GBP, USD, CHF back to the corpus's earliest purchase)
-- needs real published rates, which this migration must not fabricate.
-- src/lib/fx.js (backend, item #14) reads this table; loading the seed is
-- tracked separately so a wrong guess never silently reaches price_eur.

CREATE TABLE IF NOT EXISTS fx_rates (
  id         BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  currency   CHAR(3)     NOT NULL,             -- ISO 4217, e.g. 'RON'
  period     DATE        NOT NULL,             -- first-of-month marker for the averaging period
  rate_to_eur NUMERIC(14, 6) NOT NULL,         -- 1 <currency> = rate_to_eur EUR
  source     TEXT        NOT NULL DEFAULT 'ecb',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (currency, period)
);

CREATE INDEX IF NOT EXISTS idx_fx_rates_currency_period ON fx_rates (currency, period DESC);
