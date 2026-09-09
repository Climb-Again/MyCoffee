-- 030: roaster blurbs for WatchHouse + BOO Modern Coffee (#133 content intake).
--
-- Radu pasted these blurbs in chat (2026-09-07). Staged in ops/roaster-assets/blurbs.md
-- and applied here, keyed by the stable roaster `slug`. Neither roaster has a logo yet
-- (blurb-only). Citation markers and markdown from the source text are stripped so the
-- text renders cleanly in the app's plain-text blurb section.
--
-- Idempotent: each UPDATE is a no-op once applied (guarded by IS DISTINCT FROM, keyed
-- by slug). watchhouse = roaster id 99, boo-modern-coffee = id 29 (verified live).

UPDATE roasters SET blurb = 'WatchHouse is an upscale specialty coffee roastery and hospitality brand founded in London in 2014 by Roland Horne. It began inside a tiny 19th-century watch house on Bermondsey Street that once sheltered guards protecting a local churchyard, and has since grown to more than 20 curated locations across the UK, plus an expansion into New York City.

Its "modern coffee" ethos gives equal weight to elite coffee quality, forward-thinking interior design, and exceptional food — an elevated experience that takes quality seriously but leaves ego elsewhere. Production is centralized at the Maltby Street Roastery, under a repurposed historic railway arch in London, where head roaster and certified Q-grader Nikol Novotná fresh-roasts seasonal lots on a refurbished 1959 Probat UG22.

Rather than supplying other cafes, WatchHouse funnels its coffee exclusively into its own houses and online shop. The coffees are organized into intuitive tiers: 1829 / Rituals (smooth, structured, balanced daily companions, ideal for milk drinks), Ventures (vibrant, fruit-forward single origins), and Horizons (bold, expressive, experimental processing).'
  WHERE slug = 'watchhouse' AND blurb IS DISTINCT FROM 'WatchHouse is an upscale specialty coffee roastery and hospitality brand founded in London in 2014 by Roland Horne. It began inside a tiny 19th-century watch house on Bermondsey Street that once sheltered guards protecting a local churchyard, and has since grown to more than 20 curated locations across the UK, plus an expansion into New York City.

Its "modern coffee" ethos gives equal weight to elite coffee quality, forward-thinking interior design, and exceptional food — an elevated experience that takes quality seriously but leaves ego elsewhere. Production is centralized at the Maltby Street Roastery, under a repurposed historic railway arch in London, where head roaster and certified Q-grader Nikol Novotná fresh-roasts seasonal lots on a refurbished 1959 Probat UG22.

Rather than supplying other cafes, WatchHouse funnels its coffee exclusively into its own houses and online shop. The coffees are organized into intuitive tiers: 1829 / Rituals (smooth, structured, balanced daily companions, ideal for milk drinks), Ventures (vibrant, fruit-forward single origins), and Horizons (bold, expressive, experimental processing).';

UPDATE roasters SET blurb = 'Boo Modern Coffee (formerly Boo! Coffee Roasters) is a fast-rising specialty coffee roastery based in Brussels, Belgium. It was founded in 2024 by friends Benoit and Benjamin inside a converted factory space, the COOP building, in Anderlecht, and reached global prominence when co-founder Benjamin won the 2026 World Coffee Roasting Championship — the first time a Belgian roaster took the title.

That attention to detail carries into daily production. Boo roasts on a precise 5kg Typhoon hot-air fluid-bed machine, which fluidizes the beans on hot-air currents to eliminate harsh, smoky bitterness and emphasize clean, crisp, bright flavour. The whole catalogue is roasted as an omni-roast, developing each single-origin lot to express its natural sweetness and vibrant acidity whether brewed as filter or espresso.

The team is competitive by nature: before the world roasting crown, Benoit won the 2024 Belgian AeroPress Championship, with Benjamin placing second.'
  WHERE slug = 'boo-modern-coffee' AND blurb IS DISTINCT FROM 'Boo Modern Coffee (formerly Boo! Coffee Roasters) is a fast-rising specialty coffee roastery based in Brussels, Belgium. It was founded in 2024 by friends Benoit and Benjamin inside a converted factory space, the COOP building, in Anderlecht, and reached global prominence when co-founder Benjamin won the 2026 World Coffee Roasting Championship — the first time a Belgian roaster took the title.

That attention to detail carries into daily production. Boo roasts on a precise 5kg Typhoon hot-air fluid-bed machine, which fluidizes the beans on hot-air currents to eliminate harsh, smoky bitterness and emphasize clean, crisp, bright flavour. The whole catalogue is roasted as an omni-roast, developing each single-origin lot to express its natural sweetness and vibrant acidity whether brewed as filter or espresso.

The team is competitive by nature: before the world roasting crown, Benoit won the 2024 Belgian AeroPress Championship, with Benjamin placing second.';
