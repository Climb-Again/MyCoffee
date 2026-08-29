-- #98: merge near-duplicate farm rows created by get-or-create.
--
-- The same place was written two ways on two bags ("Banko Gotiti" on one,
-- "Banko Gotiti Washing Station" on the next), and farm resolution had no
-- alias or fuzzy coverage for facility affixes, so it minted a second row.
-- Surfaced live by #91's re-adjudication, which created two of these pairs
-- in one pass.
--
-- Radu's rule (2026-08-28): the BARE name is correct — no "station", "coop",
-- "farm" or any other prefix/suffix. So each pair keeps the short row and the
-- long one is merged away, NOT the other way round.
--
-- Deliberately NOT a blanket rename of every affixed farm. Names like
-- "Several small farmers" and "Ninety Plus Candela Estates" are real names
-- Radu wants kept verbatim, and a regex sweep would mangle them. Only these
-- four exact duplicate pairs are touched; the affix handling that stops new
-- duplicates appearing lives in `stripFarmAffixes` (comparison only).
--
-- Idempotent: every statement is a no-op once the losing row is gone.

DO $$
DECLARE
  pair RECORD;
BEGIN
  FOR pair IN
    SELECT * FROM (VALUES
      (185, 68),   -- keep 'Banko Gotiti'  <- merge 'Banko Gotiti Washing Station'
      (47, 186),   -- keep 'Nano Challa'   <- merge 'Nano Challa Cooperative'
      (23, 20),    -- keep 'Elida'         <- merge 'Elida Estate Farm'
      (77, 95)     -- keep 'el paraiso'    <- merge 'Finca El Paraiso'
    ) AS t(keep_id, drop_id)
  LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM farms WHERE id = pair.keep_id)
                OR NOT EXISTS (SELECT 1 FROM farms WHERE id = pair.drop_id);

    -- Keep the dropped spelling reachable, so a future caption using the long
    -- form resolves to the surviving row by exact alias instead of fuzzy match.
    INSERT INTO farm_aliases (farm_id, alias, alias_norm)
    SELECT pair.keep_id, f.name, lower(regexp_replace(btrim(f.name), '\s+', ' ', 'g'))
    FROM farms f
    WHERE f.id = pair.drop_id
    ON CONFLICT (alias_norm) DO NOTHING;

    -- Move the loser's own aliases across (skipping any that would collide).
    UPDATE farm_aliases a
       SET farm_id = pair.keep_id
     WHERE a.farm_id = pair.drop_id
       AND NOT EXISTS (
         SELECT 1 FROM farm_aliases b
          WHERE b.farm_id = pair.keep_id AND b.alias_norm = a.alias_norm
       );

    -- Repoint the coffees, then drop the row (remaining aliases cascade).
    UPDATE coffees SET origin_farm_id = pair.keep_id, updated_at = now()
     WHERE origin_farm_id = pair.drop_id;

    DELETE FROM farms WHERE id = pair.drop_id;
  END LOOP;
END $$;

-- 'el paraiso' was stored lowercase; the surviving row should read properly.
UPDATE farms SET name = 'El Paraiso'
 WHERE id = 77 AND name = 'el paraiso';
