-- 038: backfill roaster blurbs from staged content (#207).
--
-- Radu pasted these blurbs in chat over #132/#133; they were staged verbatim in
-- ops/roaster-assets/blurbs.md but only migrations 029 (13) + 030 (2) ever wrote
-- any to the DB, so the app showed 95/110 roasters blurb-less while CHECKLIST.md
-- reported all provided. This applies the remaining already-approved text.
--
-- Idempotent + non-destructive: each UPDATE fires only where blurb IS NULL, so a
-- re-run is a no-op and a human/in-app edit (#153) is never overwritten. Text is
-- verbatim from blurbs.md, matching the shaping of the existing 029/030 blurbs.
-- Generated for 49 roasters; slugs with null blurb and no staged text are
-- left for the content-sourcing tail of #207.

UPDATE roasters SET blurb = 'Man Versus Machine (MVSM) is Munich''s flagship specialty coffee brand and one of
the most influential forces in Germany''s third-wave movement. Founded in Munich in
2014 by Marco and Cornelia Mehrwald, the roastery is 100% independent and
family-run, free from outside investors. The name symbolises the synergy between
human agricultural craftsmanship and technical roasting precision.

Core philosophies & roasting style:

- **Quality before growth** — sources nothing but the highest grade 100% Arabica
  (80+ SCA), prioritising meticulous batch quality over commercial volume.
- **Data-driven Loring roasting** — from their Maxvorstadt HQ they run a precise,
  energy-efficient 35 kg Loring Kestrel convection roaster that eliminates smoke
  defects and delivers a balanced, sweet, clean cup.
- **The "coffee-dō" approach** — inspired partly by martial-arts (Kendo)
  philosophy, the team keeps a rigorous daily cupping discipline, adjusting
  profiles from real-time tasting rather than automation.
- **Global design aesthetic** — a cult following for its minimalist crocodile-emblem
  identity and editorial product design, with collaborations spanning brands like
  Nudie Jeans and Artek.'
  WHERE slug = 'man-vs-machine' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Origo Coffee is a foundational pioneer of the Romanian third-wave coffee movement.
Opened in 2013, it was the first specialty coffee shop and roastery in Bucharest to
brew and roast high-grade micro-lots, redefining local coffee culture and setting
standards for sourcing, brewing precision, and barista education that helped make
the capital one of Europe''s notable specialty-coffee cities.

Brand concept & roasting style:

- **Dual identity (café & cocktail bar)** — Origo transforms through the day: a
  minimalist espresso and filter haven from morning to late afternoon, then at
  5 PM the lighting shifts, the ceramic cups above the bar glow, and it becomes an
  artisan cocktail bar serving signature drinks.
- **Terroir-driven roasting** — fully traceable, seasonal micro-lots from around
  the world, rotating with the harvests and showcasing crisp, clean fruit
  sweetness and regional acidity.
- **Roastery & academy** — beyond retail, Origo runs its own production hub and
  hosts certified barista training and public cupping classes to nurture the
  community.'
  WHERE slug = 'origo' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Sumo Coffee Roasters is an acclaimed specialty coffee roastery based in Dublin,
Ireland, founded in 2020 by Daniel Horbat and his partner Alexandra. Daniel is the
2019 World Cup Tasters Champion (plus a three-time Irish Cup Tasters Champion and
Irish Brewers Cup Champion), and Sumo has built a reputation for competition-level
precision, radical transparency, and an adventurous flavour catalogue. Daniel is
originally from Romania, so Sumo has deep roots in the Bucharest coffee community.

Brand DNA & sourcing:

- **The "Sumo" ethos** — named for the values of sumo wrestling (respect,
  dedication, perseverance); they approach roasting as a discipline that honours
  the farmers'' agricultural craft.
- **World-class palate precision** — with a world-champion taster at the helm,
  green sourcing is ultra-curated: extraordinary high-scoring micro-lots from clean
  classic profiles to wild yeast-inoculated and anaerobic thermal-shock lots.
- **Direct & fair trade** — short supply chains and premium direct-trade prices to
  elite producers (such as Finca Las Flores in Colombia) to help sustain farming
  ecosystems.'
  WHERE slug = 'sumo-coffee-roasters' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Father''s Coffee Roastery is a cherished, family-run specialty roastery based in
Ostrava, Czech Republic. Founded in 2018 by husband-and-wife duo Petr Kvasnička
and Marie Kvasničková, it lives by the motto "Dad honestly roasts, mom passionately
tastes, and the children enthusiastically watch," and has earned a strong Central
European reputation for clean, origin-driven roasting, sustainability, and
producer-first transparency.

Core philosophies & roasting style:

- **From Berlin baristas to roasters** — Petr and Marie trained and ran a coffee
  bar at Berlin''s legendary Five Elephant before bringing that foundation home to
  launch their own roastery.
- **Clean & balanced profile** — on a fine-tuned Diedrich IR-5, Petr builds
  profiles that highlight native terroir, crisp acidity, and natural sweetness
  while avoiding over-roast defects; each batch is Q-grader scored.
- **The Mother''s Blend** — alongside rotating single origins, their signature
  Mother''s Espresso Blend (the "Mothership") is a fan favourite: creamy body, milk
  chocolate, subtle floral notes.
- **Eco-conscious operations** — a strong focus on low-waste packaging and
  eco-minded business decisions.'
  WHERE slug = 'father-s-coffee-roastery' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Onyx Coffee Lab is a titan of the global specialty coffee movement. Founded in 2012
by Jon and Andrea Allen in Northwest Arkansas, USA, Onyx has grown from a single
neighbourhood café into one of the most celebrated and awarded craft coffee brands
in the world. Under the motto "Join us in the pilgrimage to find the truth in
coffee," it treats coffee with scientific precision, radical financial
transparency, and exceptional design standards.

Core philosophies & roasting style:

- **Competition-grade excellence** — the Onyx team has dominated US and
  international competitions for over a decade; co-founder Andrea Allen took 2nd at
  the 2021 World Barista Championship, and figures like Lance Hedrick honed their
  craft within the Onyx framework.
- **Radical transparency pricing** — every bag publishes a full financial
  breakdown: the exact price paid to the farmer (often far above Fair Trade
  minimums), green-coffee scores, and operational logistics.
- **Solar-powered innovation** — their 30,000 sq ft flagship HQ, a converted 1907
  building in downtown Rogers, Arkansas, runs its roasting operation on a large
  custom solar array.
- **International roasting collective** — to serve Europe with fresh coffee and
  lower freight impact, Onyx roasts in Rotterdam, sharing facilities with Manhattan
  Coffee Roasters.'
  WHERE slug = 'onyx' AND blurb IS NULL;

UPDATE roasters SET blurb = 'elbgold is a foundational pioneer of the specialty coffee movement in Hamburg,
Germany. Founded in 2004 by Annika Taschinski and Thomas Kliefoth, it is one of
Germany''s earliest and most respected third-wave brands, grown from a single café
into a local powerhouse running several beautifully designed locations and
processing over 110 tonnes of high-grade green coffee a year.

Core philosophies & roasting style:

- **Deep direct-trade roots** — the founders visit origins like Ethiopia,
  Honduras, and Costa Rica personally, building farmer partnerships that often span
  a decade, bypassing commodity markets and paying premiums locked to cup quality.
- **Vintage Probat craftsmanship** — balancing data with traditional artistry, the
  team develops custom profiles on a restored 1930s Probat G45 drum roaster in
  their Schanzenviertel facility.
- **The "coffee-laboratory" concept** — their flagship features a 6.5 m bluestone
  and brass counter and works as an experimental destination with vacuum syphons,
  slow cold-drips, and nitro brew.
- **In-house patisserie** — a dedicated pastry kitchen led by award-winning chefs
  bakes artisanal biscuits, cakes, and sweets daily for a complete experience.'
  WHERE slug = 'elbgold' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Goriffee Coffee Roasters is a progressive, social-impact specialty roastery based
in Bratislava, Slovakia. Founded in 2012 by Erik Šimšík, Matej Hambalko, and Amir
Al Jabri, it anchors the Slovak third-wave scene and is respected across Central
Europe for its dedication to direct trade, social responsibility, and full
farm-to-cup transparency.

Story & concept:

- **The African spark** — the brand was born from a trip to Africa where Erik fell
  in love with Rwandan Arabica; the name blends "Gorilla" (Rwanda''s endangered
  Virunga mountain gorillas) with "Coffee."
- **The Giesen foundation** — from an industrial warehouse in Bratislava, Goriffee
  fresh-roasts weekly small batches on a Dutch Giesen W15A integrated with Cropster
  analytics for tight control across the roast spectrum.
- **Beyond the bean (cascara pioneers)** — an eco-conscious drive to use the whole
  coffee tree: cascara (tea from dried coffee cherries) and antioxidant teas from
  dried coffee leaves.
- **Goriffee Lab** — a dedicated innovation and exchange platform where farmers
  collaborate directly on post-harvest development and experimental processing.'
  WHERE slug = 'goriffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Frukt Coffee Roasters is a progressive, contemporary specialty roastery based in
Turku, Finland. Founded in 2018 by Samuli Pääkkönen — who honed his craft at
Finland''s Turun Kahvipaahtimo and Denmark''s Coffee Collective — alongside
co-founder Kyle Papai, Frukt has built an international following for its
commitment to micro-lots, traceability, and a "less but better" philosophy.

Core philosophies & roasting style:

- **Loring convection precision** — roasts seasonal small batches on a Loring S7
  Nighthawk, using recirculated superheated air to eliminate drum smoke defects and
  amplify native sweetness and crisp fruit clarity.
- **The omni-roast principle** — every coffee is developed as an omni-roast,
  highlighting authentic terroir and natural fruit sugars so it works across brew
  methods rather than forcing separate espresso/filter profiles.
- **The "resting" requirement** — because the roasts are so clean and light, Frukt
  recommends resting beans two to four weeks from roast date before brewing so the
  profiles open up fully.
- **Prestigious culinary footprint** — the exclusive coffee partner of Turku''s
  Michelin-starred restaurant Kaskis since 2020.'
  WHERE slug = 'frukt' AND blurb IS NULL;

UPDATE roasters SET blurb = '> ⚠️ DB has this roaster''s country as **Netherlands**, but it roasts in Bucharest,
> Romania (per Radu / the brand). #133 should correct `roasters.country_id`.

Legendary Everyday is an innovative specialty coffee roastery founded by Ben
Morrow, one of the original co-founders of Manhattan Coffee Roasters — now based
and roasting in Bucharest, Romania. After years helping shape Manhattan into a
global benchmark, Ben stepped away to build his own path, designing Legendary
Everyday as a masterclass in approachable, ego-free excellence.

Brand DNA & roasting philosophy:

- **Ben Morrow''s legacy** — a former multi-time international competitor (notably a
  New York Coffee Masters winner), Ben channels three decades of collective
  industry mastery into his roast profiles.
- **Ego-free sourcing** — stripping away third-wave pretense, the brand skips
  overly complicated techniques and jargon to prioritise raw material quality,
  buying standout lots directly from trusted producers (such as Colombia''s Finca
  Las Flores).
- **Dependable, balanced profiles** — roasted with clean precision every Thursday,
  the beans are consistent, deeply sweet, and easy to brew at home, removing the
  stress of perfect technique.'
  WHERE slug = 'legendary-everyday' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Spojka Roastery Company is an artistic, community-driven specialty coffee roastery
based in Prešov, Slovakia. Founded in December 2022 by head roaster and former
barista Viktor Štefančík, its name comes from the Slovak word for "connection" or
"clutch" — symbolising a mission to unite producers, roasters, and coffee lovers.
It has quickly caught the European third-wave community''s attention for its
street-art style and intense focus on single-origin micro-lots.

Brand DNA & roasting style:

- **Street art & hand-painted packaging** — Spojka treats packaging as artistic
  expression, hand-spray-painting each bag with graffiti aesthetics and stapling a
  raw info card on top; this award-winning setup lets them launch rare small-batch
  micro-lots fast.
- **High-scoring single origins** — targeting exceptional coffees at SCA 85+, with
  exclusive auction lots from esteemed family estates in Colombia, Indonesia, and
  Ethiopia.
- **The "Brewtiful" community ethos** — under the catchphrase "Brewtiful People —
  let''s unite, not divide," Spojka prioritises building a diverse community around
  approachable yet technically executed coffee.'
  WHERE slug = 'spojka' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Three Marks Coffee is a popular, design-minded specialty roastery and café in
Barcelona, Spain. Founded in 2018 in the Fort Pienc neighbourhood, its clever name
comes from three co-founders who all share variations of the same first name: Marc
Aguyé (shop management), Marco Paccagnella (brand marketing), and Marco De Rebotti
(roasting and sourcing). It''s now recognised as one of Spain''s top specialty
roasteries.

Core philosophies & roasting style:

- **The Nømad heritage** — before launching Three Marks, Marc Aguyé and Marco De
  Rebotti honed their craft for years at Nømad Coffee, one of Barcelona''s
  foundational third-wave pioneers.
- **Juicy & clean Loring roast** — the team roasts on a Loring convection machine,
  favouring its hot-air style to capture extreme sweetness and highlight juicy
  fruit sugars and crisp acidity while eliminating sharp, smoky defects.
- **Producer-first sourcing** — a highly seasonal, transparent sourcing program
  working closely with independent family farms in regions like Colombia,
  Ethiopia, and Kenya.'
  WHERE slug = 'three-marks-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Sprout Coffee Roasters is a modern, fun-loving specialty roastery and café in
Eindhoven, Netherlands. Founded in 2019 by brothers Daniell and Ruben — born in
Eindhoven but raised in Perth, Australia — the brand bridges vibrant Australian
café culture with European roasting precision, earning a passionate following for
its playful persona, sustainability focus, and flavour-forward coffees.

Core philosophies & roasting style:

- **Playful, animal-themed identity** — each label features a unique animal
  illustration and colour scheme chosen to symbolise the environment, country, and
  culture where the coffee was grown.
- **Bold, descriptive flavour naming** — much like DAK, Sprout ditches elitist
  jargon for hyper-descriptive names: Superpunch, Cool Cat, Mellow Fellow, Bloody
  Boozy Orange, Lasso Lassi.
- **Experimental post-harvest sourcing** — partnering with cutting-edge producers
  (notably Nestor Lasso of Finca El Diviso, Huila, Colombia) for ultra-complex,
  co-fermented, yeast-inoculated micro-lots with intense candy and fruit profiles.
- **Community-led events** — at home base they treat coffee as a lifestyle, hosting
  energetic "Latte Night Live" throwdowns with local DJs, street food, and
  late-night latte-art competitions.'
  WHERE slug = 'sprout-coffee-roasters' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Taf Coffee is a titan of the Mediterranean and European third-wave coffee movement.
Founded as a family business in Athens, Greece in the 1990s by Yiannis Taloumis
(an SCAE Lifetime Achievement Award recipient), Taf transitioned in the late 2000s
into a globally revered specialty roastery and educator, widely credited with
pioneering the modern specialty wave across Greece.

Core philosophies & roasting style:

- **The "hand-crafted" ethos** — Taf prefers "hand-crafted" to "specialty,"
  highlighting a trilogy of care: sourcing extreme-quality beans, meticulous
  roasting craftsmanship, and brewing that explicitly educates the customer.
- **Direct relationship program** — decades of short, transparent supply chains;
  Yiannis travels to origins annually to buy sustainable, high-scoring
  single-estate micro-lots traceable to the exact field plot.
- **Competition dominance** — Taf''s training and green coffees fuelled famous
  competitors like Stefanos Domatiotis (2014 World Brewers Cup Champion) and Chris
  Loukakis (WBC finalist).
- **Scientific quality control** — a state-of-the-art lab and certified SCA Premier
  Training Campus in Attica test and profile every incoming crop to showcase native
  fruit sugars, sweetness, and floral aromas.'
  WHERE slug = 'taf' AND blurb IS NULL;

UPDATE roasters SET blurb = 'La Cabra Coffee Roasters is one of the most recognisable and influential icons of
modern specialty coffee. Founded in Aarhus, Denmark in 2012, it has grown from an
ambitious out-of-the-way coffee shop into a global powerhouse — exporting to over
60 countries and running celebrated flagship cafés and bakeries from Copenhagen to
New York and Bangkok. La Cabra is revered for its "white-bag minimalism" and an
uncompromisingly clean approach to coffee.

Core philosophies & roasting style:

- **The single-roast philosophy** — rather than separate roast depths for espresso
  and filter, La Cabra roasts each coffee to one optimal expression, highlighting
  brightness, clarity, and natural fruit sweetness while staying versatile for any
  method.
- **Translucent & terroir-driven** — their Scandinavian style yields cups so light
  and precise they read as translucent, treating roasting as a lens to reveal what
  the soil and processing already hold rather than a tool to add flavour.
- **Elite sourcing strategy** — a short, hyper-seasonal rotation favouring washed
  Ethiopians, high-altitude Kenyan peaberries, and clean experimental
  fermentations, with direct partnerships with world-class producers like Juan Peña
  of Hacienda La Papaya in Ecuador.'
  WHERE slug = 'la-cabra' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Koppi Fine Coffee Roasters is a respected pioneer of the Scandinavian third-wave
movement. Founded in 2007 in Helsingborg, Sweden by Anne Lunell and Charles
Nystrand, it''s internationally revered for precision, long-standing producer
relationships, and dedication to the Nordic light-roast style. Both founders are
decorated champions — with multiple Swedish Barista and Brewers Cup titles — and
that competition background shows in the roasts.

Core philosophies & roasting style:

- **The pure Nordic profile** — roasted exceptionally lightly on Diedrich machines
  to eliminate smoky defects, so each cup is a crystal-clear reflection of terroir,
  highlighting elegant fruit sugars, crisp acidity, and natural sweetness.
- **Long-term direct trade** — an intimate circle of small-scale producers in
  Costa Rica, Colombia, and Honduras, buying from the same estates year after year
  to build sustainable, higher-value partnerships.
- **Evolution into production focus** — what began as a popular Helsingborg coffee
  bar with an in-store roaster shifted in 2016 to a dedicated industrial HQ,
  focusing entirely on roasting freshness and wholesale.
- **Signature espresso** — beyond seasonal micro-lots, they''re famous for core
  espresso concepts like One Finger Snap, celebrated for thick molasses sweetness
  and juicy berry notes.'
  WHERE slug = 'koppi' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Public Coffee Roasters is a popular, modern specialty roastery based in the
maritime city of Hamburg, Germany. Working from the belief that coffee is a
multifaceted culinary art form, the brand has carved out a distinct northern-German
identity built on direct sourcing, strict transparency, and local community
outreach.

Sourcing & roasting philosophies:

- **Hanseatic houseboat heritage** — Public originally rose to prominence
  hand-roasting small batches inside a converted floating houseboat anchored on
  Hamburg''s Elbe River.
- **The "Public" promise** — the name stands for generating public interest in
  specialty coffee''s flavour diversity and maintaining complete public transparency
  on supply chains, grower premiums, and environmental benchmarks.
- **Clean drum-roasting precision** — partnering directly with progressive estates
  and boutique importers, they tailor small-batch profiles to maximise natural
  fruit sweetness and crisp cleanliness, avoiding heavy dark-roast defects.
- **Eco-conscious formats** — they engineered their own line of 100% compostable
  coffee capsules made entirely from wood fibres.'
  WHERE slug = 'public-coffee-roasters' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Cupping Room Coffee Roasters is an acclaimed, multi-award-winning specialty
roastery and café chain based in Hong Kong. Founded in 2011 by Kapo Chiu, it''s
widely credited with sparking Hong Kong''s modern third-wave movement, and stands
out for bridging champion-level competition standards with accessible, beautifully
curated retail.

Core philosophies & roasting style:

- **The pursuit of the "clean cup"** — a strict light-roasting philosophy that
  avoids deep, smoky roasts to maximise aroma, natural sweetness, and cup clarity,
  letting the authentic fruit, floral notes, and regional acidity come through.
- **Competition-pedigree roots** — founder Kapo Chiu is a three-time Hong Kong
  Barista Champion and a twice top-three finisher at the World Barista Championship;
  that analytical rigour is embedded in the roastery.
- **Prestigious micro-lots** — a rotating seasonal menu of rare, world-renowned
  single origins, including lots from Gesha Village (Ethiopia) and Granja La
  Esperanza (Colombia).
- **Innovative product formats** — early specialty adopters of high-end coffee
  capsules and nitrogen-sealed drip bags using the same premium micro-lots poured
  on their bars.'
  WHERE slug = 'cupping-room' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Rum Baba Coffee Roasters is a vibrant, popular independent specialty roastery and
bakery in Amsterdam, Netherlands. Founded in 2013 by Jeroen Keyzer and his partner
Marielusan Drost — emerging from Amsterdam-Oost''s pioneering café Coffee Bru — the
brand is revered for an unpretentious, high-energy approach that brings quality
craft coffee into everyday life.

Core philosophies & roasting style:

- **The "everyday specialty" focus** — rather than treating specialty as an
  intimidating occasional luxury, Rum Baba makes its high-end lots accessible, fun,
  and part of a normal daily routine.
- **Bright & clean profiles** — a transparent rotation of seasonal micro-lots
  profiled for natural fruit sugars, crisp clarity, and balance: vibrant filter
  roasts alongside complex, creamy espresso.
- **Aesthetic 80s packaging** — playfully bright, colour-blocked bags with 80s New
  Wave design and bold retro typography.
- **Integrated artisan bakery** — a fully functional pastry house famous across
  Amsterdam for its marble cakes, American-style pies, and sweet pastries.'
  WHERE slug = 'rumbaba' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Tanat Coffee (formerly Kawa Coffee Roasters) is an ultra-modern, innovative
specialty roaster based in Paris, France. Founded in 2016 by Alexis and recently
rebranded from Kawa to Tanat, it''s internationally revered as a pioneer of
experimental post-harvest fermentations and "funky" flavour profiles in the French
and European third-wave scenes.

Core philosophies & roasting style:

- **Conscious & progressive innovation** — direct, multi-year producer
  relationships for fully traceable micro-lots, with active co-fermentation
  research in Colombia and collaborations with farmers in Ethiopia.
- **Vibrant & fruity roasting** — light, meticulous roasts that highlight intense
  fruit sugars, floral aromas, and structural clarity, reading closer to intricate
  desserts or fine wine than traditional heavy roasts.
- **Anti-capsule manifesto** — honouring "living coffee," Tanat takes a firm stance
  against aluminium and plastic pods as the antithesis of artisanal extraction.
- **Social-impact framework** — uses its scale for social projects, e.g. directing
  a portion of sales from its pink-packaged Rwanda bags into breast-cancer
  initiatives.'
  WHERE slug = 'tanat-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'HAYB Speciality Coffee is a progressive, internationally celebrated third-wave
roastery based in Warsaw, Poland. A play on "How Are You Brewing?", it was launched
by a family-and-friends team led by the father-and-son Borowski duo, and has built
a cult following by pairing rigorous standards with its motto: "Effortless
Speciality."

Core philosophies & roasting style:

- **The "effortless" anti-elitist vision** — HAYB rejects intimidating jargon,
  designing every interaction as a warm invitation to explore flavour rather than a
  lecture, making premium coffee accessible, understandable, and fun.
- **Seasonality over house style** — profiles are optimised to bring out each
  harvest lot''s authentic genetic potential rather than forcing a uniform house
  style, sourcing for peak ripeness and small-farm lots.
- **Award-winning aesthetic** — tall, colour-blocked packaging with abstract
  graphics that won The Coffeevine''s Best Packaging award; year-round filters are
  categorised by dominant profile — Kwiat (floral), Tropik (tropical), Owoc (fruit).
- **Socially conscious supply chains** — direct-trade partnerships with boutique
  importers like 1000 Hills in Rwanda, plus seasonal roasts dedicated to charity
  causes.'
  WHERE slug = 'hayb-speciality-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'The Naughty Dog is a playful, top-tier specialty roastery based in Jílové u Prahy
(about 40 minutes from Prague), Czech Republic. Founded in October 2018, it''s owned
by an elite third-wave couple: Gwilym Davies (2009 World Barista Champion and
co-founder of London''s Prufrock Cafe) and Petra Davies Veselá (a multiple national
champion, SCA trainer, and author of *The Big Book of Coffee*). The name is
inspired by their two sausage dogs, Jenny and Mája.

Sourcing & roasting philosophies:

- **Convection roasting consistency** — small batches on an Italian IMF convection
  machine whose hybrid hot-air-and-drum tech gives exceptional heat stability,
  eliminating smoky defects for clean, sweet, bright profiles.
- **Playful & transparent sourcing** — Petra selects traceable micro-lots from
  Africa and Central/South America (especially Ethiopia, Colombia, Costa Rica),
  with seasonal picks descriptively colour-coded by dog illustrations.
- **Creative barrel-aging & blends** — famous for quirky concepts like whiskey- and
  rum-barrel-aged coffees (Jenny''s Barrel Coffee) and versatile espresso blends
  like the Pawffice Blend (dark chocolate and pralines).'
  WHERE slug = 'the-naughty-dog' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Nowhere Future Coffee Roasters is a hip, avant-garde specialty micro-roastery and
café concept in Milan, Italy. Founded in 2021, it quickly became one of Milan''s
definitive specialty destinations, defying Italy''s deep-rooted traditional espresso
culture with a hyper-modern approach to light roasting.

Brand DNA & roasting style:

- **The "millennial pink" aesthetic** — an iconic flagship instantly recognisable
  for its clean, minimalist industrial-chic layout inspired by Australian café
  culture.
- **Strict single-origin manifesto** — zero commercial blending; only high-scoring
  seasonal single origins, roasted to preserve and amplify each farm and terroir.
- **The "no sugar" policy** — the bar enforces a no-sugar rule to push drinkers to
  experience the natural sugars, fruit notes, and clarity of the coffee itself.
- **Nordic-style bakery & food** — a praised in-house culinary program, locally
  famous for cardamom buns, cinnamon rolls, and Scandinavian-inspired baked goods.'
  WHERE slug = 'nowhere' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Jonas Reindl Coffee Roasters is a defining anchor of Vienna''s modern specialty
coffee scene. Founded in 2014 by Philip Feyer, it was part of Vienna''s "second
wave," challenging the city''s historic but often bitter coffee-house culture with
ultra-transparent, lighter-style roasting. The name is Viennese insider lore: the
nearby Schottentor transport hub — built under 1961 mayor Franz Jonas — has a
circular layout resembling a cooking pan (a "Reindl"), so locals dubbed it "Jonas''
Pan."

Core philosophies & roasting style:

- **Barista-to-roaster progression** — after running multi-roaster spaces, Philip
  moved into self-taught roasting in 2018, mapping custom batches with Cropster
  analytics for tight profile consistency.
- **Dedicated direct trade** — a core relationship with Finca Las Alpujarras in
  Nicaragua yields over 70% of the sweet, chocolatey base for their main seasonal
  espresso offerings.
- **Viennese heritage meets third-wave tech** — a modern light-to-medium roastery
  whose cafés still serve classic Austrian styles like the Melange alongside
  single-origin pour-overs.
- **The ROWAC aesthetic** — photogenic, minimalist vintage-industrial cafés
  furnished with genuine 100-year-old ROWAC steel stools, the same brand Gropius
  used in the original Bauhaus workshops.'
  WHERE slug = 'jonas-reindl' AND blurb IS NULL;

UPDATE roasters SET blurb = 'BeBerry Coffee is a progressive, precision-focused specialty roastery based in
Prague, Czech Republic. Founded in 2021 by certified Q-Grader Tomáš Laca and his
partner Karin (a two-time Slovak Cup Tasting Champion), it lives by a simple core
message — "Coffee is a fruit" — and is respected across Central Europe for lively,
intensely sweet, fruit-forward profiles.

Core philosophies & roasting style:

- **The "golden mean" roast** — positioned between hyper-light Scandinavian styles
  and traditional darker roasts, each profile is tailored to highlight natural
  sugars, terroir, and processing notes while keeping low bitterness and pleasant
  acidity.
- **A focus on the fruit** — mirroring the name and berry-shaped logo, they select
  lots that showcase juicy, fruity character: vibrant washes alongside complex
  anaerobic naturals and anaerobic honeys.
- **Versatile omni-roasts** — many lower-acidity single origins are developed as
  omni-roasts, versatile for both high-clarity V60 and vibrant modern espresso.'
  WHERE slug = 'beberry-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Coffeein is a prominent direct-trade specialty roastery from Slovakia. Established
in 2011 by Peter Szabó as an online store for Italian coffee, it pivoted fully to
third-wave coffee and opened its own roasting HQ in Šahy in 2015. It''s now a
regional favourite, known for its educational focus, crop freshness, and extensive
direct-trade farm relationships.

Core philosophies & roasting style:

- **The direct-trade journey** — the team travels to origins annually to visit
  family micro-farms in Brazil, Colombia, and Honduras, skipping commodity pricing
  for farm-level sustainability.
- **Massive rotating catalog** — sourcing from the top tier of global production,
  they roast 40+ single origins and micro-lots a year, every bag carrying harvest
  year, variety, and processing data.
- **The "Zrnko" subscription** — a popular Central European subscription that
  matches freshly roasted single origins to each drinker''s brewing habits.
- **Exploratory sourcing** — beyond classic Arabica terroirs, they''re known for
  hunting unusual botanicals, including complex fruit-forward Liberica from
  Southeast Asia.'
  WHERE slug = 'coffeein' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Kofi Microroastery is an acclaimed independent specialty roastery and café concept
in Ioannina, Greece. Launched in the late 2010s, it''s well regarded in the Greek
third-wave community for its hyper-focused "laboratory" approach — artisanal
in-house roasting paired with a striking mid-century architectural identity.

Core philosophies & roasting style:

- **The "in situ" lab concept** — designed by vp architectural studio, the space
  works as a visual production lab: roasting happens in the heart of the café so
  guests watch small-batch transformations up close.
- **Traceable, innovative micro-lots** — a green program targeting exceptional
  seasonal harvests (honey-processed Colombian Geishas, vibrant Kenyans), focused
  on fruit ripeness and clean, controlled fermentations.
- **Small-batch conformance** — roasting only in small batches keeps hyper-precise
  attention to detail, highlighting each crop''s sweetness and terroir without smoky
  defects.
- **Mindful community framework** — an environmentally and socially conscious
  mindset, paying premiums to independent farms and connecting the local community
  to each cup''s agricultural backstory.'
  WHERE slug = 'kofi-microroastery' AND blurb IS NULL;

UPDATE roasters SET blurb = 'D·Origen Coffee Roasters is an influential, award-winning pioneer of Spain''s
specialty coffee movement. Founded in 2012 by Michael Uhlig in El Albir (Alicante)
on the Costa Blanca, it was among the first roasteries in Spain dedicated to
specialty-grade lots. Its unusual standing in Europe: they don''t just source coffee
— they grow it, managing their own family estate in Central America.

Core philosophies & vertical sourcing:

- **From farm to cup** — the family acquired its own farm, Barú Black Mountain, in
  Panama''s high-altitude volcanic terroir, giving total agricultural control to
  experiment with varietals and post-harvest fermentations from the soil up.
- **Spain''s best espresso winners** — the roasting team has won "Best Espresso in
  Spain" three times (2014, 2016, 2023).
- **Meticulous packaging tiers** — the catalogue is segmented into curated Packs,
  balanced Blends engineered for vibrant sweetness, and ultra-premium Rare Editions
  showcasing experimental micro-lots and unusual botanical varietals.'
  WHERE slug = 'd-origen' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Right Side Coffee Roasters is an award-winning pioneer specialty roastery based in
Barcelona, Spain. Founded in 2012 by Joaquín Parra, it has spent over a decade as a
benchmark for direct-trade sourcing, roasting mastery, and transparent
partnerships, earning the local moniker "Spanish Roaster Champ" among purists.

Core philosophies & roasting style:

- **"Chefs with one ingredient"** — the team treats roasting through a culinary
  lens, seeing themselves as chefs dedicated to mastering one raw agricultural
  material: coffee.
- **100% vertical direct trade** — they handle all their own green imports,
  travelling to origins each season to build long-term, ethical relationships with
  small-scale farmers at premium farm-gate prices.
- **Vintage restorations & convection precision** — from their Castelldefels
  facility they restore and fine-tune classic roasting machinery, focusing on
  flavour clarity, clean extractions, and terroir over smoky defects.'
  WHERE slug = 'right-side' AND blurb IS NULL;

UPDATE roasters SET blurb = '> Note: Kawa rebranded to **Tanat** in early 2025 (see the `tanat-coffee` entry).
> This coffee is in the library under the older "Kawa" name, so the blurb is kept
> here too.

Kawa Coffee Roasters was a highly influential specialty roastery based in Paris,
France. Founded in 2016 by Alexis Gagnaire — a 3rd-place finisher at the 2019 World
AeroPress Championship and silver medallist at the 2021 French Roasting
Championship — it became known across Europe for progressive, fruit-forward
post-harvest fermentations. In early 2025, ahead of its 10th anniversary, the team
rebranded from Kawa to Tanat Coffee.

Core philosophies & roasting style:

- **Terroir-driven expression** — precise, consistent light roasts that highlight
  each terroir''s genetic sweetness and floral notes and extract cleanly.
- **Anti-capsule movement** — a vocal stance against aluminium and plastic pods on
  grounds of cost, waste, and poor traceability.
- **Experimental green partnerships** — direct collaborations with forward-thinking
  producers (e.g. Jamison Savage in Panama and advanced Colombian farms) for
  competition-level lots.'
  WHERE slug = 'kawa' AND blurb IS NULL;

UPDATE roasters SET blurb = '> ⚠️ Country mismatch for #133: the DB row `felix-kaffee` is seeded as **Germany**,
> but this roastery is in **St. Pölten, Austria**. Correct `roasters.country_id`
> when populating.

Kaffeelix (historically founded and long known as **Felix Kaffee**) is an elite,
internationally decorated specialty coffee roastery based in St. Pölten, Austria.
Founded in 2012 by Felix Teiretzbacher, it won the 2022 World Coffee Roasting
Championship in Milan — the first Austrian ever to claim the world title.

Core philosophies & roasting style:

- **Terroir-driven purism** — clean, transparent roasting that lets each origin''s
  natural sweetness and character show through.
- **Exceptional quality floor** — sources and roasts only high-scoring lots
  (80+ SCA), with no filler in the range.
- **Precision hybrid setup** — two Coffeetool drum roasters (7.5 kg and 30 kg)
  alongside a Giesen W1A, giving both sample-scale control and production capacity.'
  WHERE slug = 'felix-kaffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Sentido Speciality Coffee is a praised, intimate pioneer of the specialty coffee
scene in Kyoto, Japan. Tucked down a quiet side street in Nakagyo Ward, it blends
Australian café culture with precise Japanese hospitality. Founded by owner-barista
Itsumi Doi — who honed his craft in Australia''s coffee scene — Sentido is a relaxed,
minimalist sanctuary for coffee purists.

Core experience & style:

- **Free tasting station** — a dedicated counter lets guests sample 5–6 coffees for
  free via french press before ordering, so they can pick the profile that matches
  their palate.
- **Clean Loring roasting** — rotating single-origins (e.g. their Costa Rica Farami
  Geisha Red Honey) are developed on a Loring S7 Nighthawk convection roaster in a
  sweet, light-roasting style that preserves fruit terroir.
- **Industrial-minimalist space** — a 16-seat room of smooth concrete, pale pine,
  and abundant natural light.
- **Early-bird haven** — a rare early opener in a city where specialty shops open
  late, welcoming guests from 7:00 AM on weekdays.'
  WHERE slug = 'sentido' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Drop Coffee Roasters is a pioneering force in the third-wave coffee movement.
Founded in Stockholm, Sweden in 2009 as a small coffee bar by Mariatorget, it has
grown into one of Europe''s most decorated independent micro-roasteries. Under
co-owner and managing director Joanna Alm — a three-time Swedish Coffee Roasting
Champion and silver medallist at the World Coffee Roasting Championship — it was
named "Sweden''s Roastery of the Year 2026".

Core philosophies & roasting style:

- **The "zero-blends" manifesto** — a strict purist stance on integrity: they
  stopped roasting blends in 2010, and the entire catalogue is 100% traceable,
  single-origin coffees scoring 87+ on the SCA scale.
- **Nordic light roasting** — on a 25 kg Diedrich drum roaster, roasting three
  times a week for a bright, sweet, highly acidic cup that strips away smoky roast
  defects and lets the terroir shine.
- **Certified organic & direct trade** — sourced directly from tight-knit producer
  networks in Central/South America and East Africa, roasted at a fully certified
  organic facility in Rosersberg, north of Stockholm.
- **A new packaging era** — long known for signature minimalist cardboard boxes,
  the brand has since debuted a vibrant, colourful new bag line.'
  WHERE slug = 'drop-coffee-roaster' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Living Food Lab was a popular vegan café, co-working space, and culinary education
laboratory based in Bali, Indonesia. Founded by raw-food chef Avara Yaron, it built
a community around conscious eating and holistic living. Its physical spaces — the
flagship locations in Canggu and Ubud — have since permanently closed, though the
brand stays active online with global classes, workshops, and vegan catering.

What it was known for:

- **The menu** — 100% plant-based and mostly raw gourmet food: custom granola bars,
  raw pizzas, green smoothies, avocado wraps, and vegan blueberry cheesecakes, plus
  a superfood-loaded "cosmic coffee".
- **A multi-concept space** — more than a restaurant: an air-conditioned co-working
  hub with free Wi-Fi for digital nomads, a teaching kitchen, and an "elixir bar"
  aimed at memory and focus.
- **Education & events** — cooking classes with international guest chefs, holistic
  healing and spirituality workshops, and expeditions to their farm in Kintamani.'
  WHERE slug = 'livingfoodlab' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Mission Coffee Works is an independent, progressive force in British specialty
coffee. Founded in London in 2012 as a single mobile espresso van on the streets of
Peckham, it has grown into one of East London''s most respected independent
roasteries, working from its roasting hub in Hackney Wick. Its guiding philosophy is
extreme accessibility — proving high-end coffee can be fun, supportive, and
approachable rather than elitist — and it took multiple accolades at the Great Taste
Awards 2026.

Core philosophies & roasting style:

- **Award-winning blends & rotations** — everyday consistency paired with
  experimental micro-lots; signature staples the Bells House Blend and Pivot Single
  Origin both earned top honours at the Great Taste Awards 2026.
- **Seasonal sourcing & espresso versatility** — under Head of Coffee Edgaras, three
  to four single origins run at a time, rotating quarterly with regional harvests
  and crafted to shine equally as espresso and filter.
- **Ethical supply & ecosystem care** — fair, transparent pricing with direct-trade
  loops in Central America and East Africa, plus sustainability commitments and tree
  planting via the Eden Reforestation Project.
- **Storytelling & accessible packaging** — bold, illustrated bags that mirror the
  emotional feeling of each brew, fully eco-friendly and 100% recyclable.'
  WHERE slug = 'mission-coffee-works' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Uncommon is a pioneering force in Amsterdam''s modern specialty coffee scene.
Co-founded in 2018 by Claye Tobin, Josh Cotton, and Nina Tromp — all veterans of
the Dutch coffee landscape — it has grown from a local project into one of Europe''s
most revered independent roasteries: a progressive, human-centric roasting house
built to honour the farmers behind each coffee, pairing award-winning curation with
a calming design aesthetic and transparent sourcing.

Core philosophies & roasting style:

- **The "uncommon story" manifesto** — a purist stance on origin identity: every
  farm, interaction, and coffee has an "uncommon" story. They bypass generic
  commercial sourcing for rare, high-scoring micro-lots — unusual processing,
  distinct micro-climates, and sought-after varieties like Sudan Rume, Tabi, and
  Pink Bourbon.
- **Nordic-influenced roasting** — a transparent, sweet profile roasted to precise
  parameters that emphasise origin clarity over smoky roast character, letting the
  terroir and variety guide the cup.
- **Direct trade & ecosystem impact** — organic-certified or sustainably grown
  coffees via deep direct-trade partnerships across East Africa, Central America, and
  Colombia, funding tree-replanting, clean-water systems, and steady income for
  processing workers.
- **"Warm minimalism" spaces** — the Uncommon Cafe and Uncommon Bar in Amsterdam''s
  Oud West: calming community hubs pairing rotating seasonal coffees with wild
  pastries, fermented morning dishes, and handcrafted ceramics.'
  WHERE slug = 'uncommon' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Radical Coffee is an independent, uncompromising force in Romania''s modern specialty
coffee scene. Founded in Oradea, Bihor County, it has grown from a passionate local
venture into one of the country''s most fiercely purist independent micro-roasteries,
working from its espresso bar and production house on Strada Iuliu Maniu and serving
as a regional benchmark for precise, artisanal roasting.

Core philosophies & roasting style:

- **The no-sugar manifesto** — an intense purist stance on beverage integrity: no
  added sugars, flavoured syrups, or heavily modified drink requests. They believe
  carefully cultivated beans need no masking agents and brew to highlight the crop''s
  native notes.
- **100% manual craftsmanship** — a strictly manual operation; founder Andrei and
  the team stand by the machine for every batch, adjusting heat by hand to keep
  profile clarity across micro-lot variations.
- **Ultra-seasonal sourcing** — green selection rotates strictly with global harvest
  cycles, sourcing high-scoring lots (e.g. complex anaerobics from Brazil, clean
  single origins from Costa Rica) and cycling the catalogue rapidly for peak
  freshness.
- **The "slow down" flagship space** — a warm, minimalist Oradea tasting bar built
  to strip away fast-casual distractions, functioning as an educational hub for
  cupping flights and unpretentious, expert-led tasting.'
  WHERE slug = 'radical-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Mere Black Coffee is an emerging, accessibility-driven brand in the Central and
Eastern European specialty market. Its core mission is to remove the high financial
barriers often tied to premium coffee culture, delivering 100% Arabica beans
optimised for daily offices and home automatic espresso systems. With deep roots
across Poland and Romania, it has scaled largely through major e-commerce platforms
like eMAG and Allegro rather than a café network.

Core philosophies & roasting style:

- **The everyday-ritual manifesto** — coffee as a functional, universal daily ritual
  for workplace productivity and personal pleasure, without third-wave elitism or
  intimidating price tags.
- **Balanced medium roasting** — a uniform medium roast targeting low acidity,
  balanced body, and a smooth, familiar mouthfeel, calibrated to run cleanly through
  bean-to-cup machines and stove-top moka pots rather than Nordic-light profiles.
- **Single-origin traceability** — clean single origins from Honduras, Brazil,
  Guatemala, Peru, and Colombia, spotlighting classic chocolatey, nutty, and
  stone-fruit profiles.
- **Digital-first wholesale supply** — no traditional retail café storefront;
  foil-lined 250 g and 1 kg bags aimed at breakrooms, distribution partnerships, and
  direct-to-door retail.'
  WHERE slug = 'mere-black-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'BirdSong Coffee is an independent, sustainability-driven roastery in Prague, Czech
Republic. Grown from an ecological initiative into one of the country''s most
respected independent micro-roasteries, its ethos of environmental stewardship traces
to a formative origin trip to Ethiopia. It works from its roastery and cosy espresso
bar on Radlická 47 in Prague 5.

Core philosophies & roasting style:

- **The forest-grown manifesto** — a purist stance on biodiversity: no monoculture
  clear-cut sun plantations, only 100% shade-grown Arabica under natural forest
  canopy, preserving avian habitats, preventing soil erosion, and supporting organic
  smallholder livelihoods.
- **Smithsonian Bird Friendly® certified** — multiple coffees carry the Bird
  Friendly® certification, the strictest biodiversity gold standard in coffee; most
  of the rest is fully organic, with complex lots from hand-selected origins like
  Uganda and Bolivia.
- **Precision in-house craftsmanship** — fully vertical control on their own Diedrich
  IR-12 drum roaster, with clean, balanced medium-light to medium profiles that
  maximise the natural sweetness, clarity, and fruit of forest-grown terroirs.
- **The calm espresso bar** — a quiet, minimalist Prague pocket bar and educational
  sanctuary offering precision batch brews, plant-based alternatives at no surcharge,
  and freshly roasted whole-bean bags.'
  WHERE slug = 'birdsong-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Keen Coffee is a pioneering force in Dutch specialty coffee. Founded in Utrecht,
Netherlands in 2016 by baristas driven to "keenly learn about coffee," it has grown
into one of the country''s most respected independent roasters. Under co-founder Bonne
Postma it has crafted coffees for global competitive stages — including the beans
behind a third-place finish at the World Barista Championship.

Core philosophies & roasting style:

- **The flavour-forward manifesto** — a purist stance on origin clarity under the
  motto "Explore. Taste. Repeat." They focus entirely on unique lots with distinct
  geographical identity — coffees so pristine they claim you can taste the exact GPS
  coordinates they came from.
- **Precision Loring roasting** — advanced, eco-friendly Loring drum roasters for a
  smoke-free, energy-efficient process, aiming at a clean, balanced light-to-medium
  style that maximises natural sweetness and eliminates bitter roast defects.
- **Direct trade & quality sourcing** — sourcing directly from small-scale farmers
  worldwide and paying premiums well above market to fund farm-level projects; a
  rotating menu of elite single origins, standout anaerobics (e.g. El Diamante Maria
  from Costa Rica), and rare Geishas.
- **The immersive tasting era** — the Keen Coffee Bar at Ganzenmarkt 30 runs as an
  omakase-style U-shaped tasting room with personalised sensory note cards, paired
  with an expanded industrial Roastery Café & Shop in Utrecht''s Werkspoor Quarter.'
  WHERE slug = 'keen-coffee' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Sloane Coffee Roastery is a pioneering force in Romania''s modern specialty coffee
scene. Founded in Bucharest in 2016 by Teodora Pitiș — Romania''s first female
Q-Grader — alongside Cosmin Mihailov, it has grown from a boutique project into one
of Eastern Europe''s most revered independent roasting houses, known for uncompromising
green-coffee curation, a sharp retail identity, and sensory focus. It is named after
Sir Hans Sloane, a historic coffee enthusiast.

Core philosophies & roasting style:

- **The no-alteration manifesto** — a purist stance on beverage integrity: no sugar,
  syrups, or artificial sweeteners across their espresso bars. Out of respect for the
  farmers, cuppers, and roasters in the chain, each lot is presented exactly as it is
  to preserve its native flavour compounds.
- **Terroir- and lot-driven roasting** — every lot treated as a distinct masterpiece
  rather than blended toward a generic consistency, emphasising green-bean
  transparency, clean processing, and distinct acidity tuned to each origin''s
  micro-climate.
- **Experimental & high-scoring batches** — a catalogue split into Classic Profiles,
  Premium Lots, and rare Experimental runs, featuring complex processing like 120-hour
  anaerobic macerations and skin-contact naturals from leading farms across Latin
  America and East Africa.
- **Dual flagship experiences** — an industrial Roastery, Kitchen & Shop on Splaiul
  Independenței 287 (specialty brunch and an open garden) and the high-vibe Sloane
  Specialty Coffee bar on Calea Victoriei 31, both with extensive retail lines and
  coffee flights.'
  WHERE slug = 'sloane' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Guido Coffee is a pioneering force in Romania''s modern specialty coffee scene.
Founded in Bucharest in 2014 by Floriana Vlaicu — one of the country''s premier
certified Q-Graders — alongside Adrian Simion, it has grown into one of the nation''s
most respected independent roasting houses and educational institutions, a key
catalyst for Bucharest''s third-wave boom and a trainer of the country''s competitive
baristas. It works from its roastery, shop, and tasting academy on Strada Mihai
Eminescu 182.

Core philosophies & roasting style:

- **The educational manifesto** — a tri-fold identity of "Coffee Shop, Roastery, and
  Coffee School" focused on bridging professional sensory experts and home brewers,
  with weekly public cupping flights and sensory wheels for local enthusiasts.
- **"Core" vs. "Explore" curation** — a Core Line of accessible, low-acidity coffees
  with chocolate and caramel notes tuned for smooth home extraction, and an Explore
  Line of high-scoring anaerobics, rare geishas, and bright fruity lots for advanced
  filter methods.
- **Precision profile integrity** — each coffee profiled to its genetic character and
  terroir, roasted multiple times a week to precise parameters so every bag ships at
  peak freshness with clean, lively acidity and no smoky defects.
- **The academy & tasting hub** — the flagship on Strada Mihai Eminescu runs as an
  interactive tasting bar and professional classroom with espresso profiles and siphon
  systems, hosting certified masterclasses in brewing, espresso, and latte art.'
  WHERE slug = 'guido' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Maggma Beans is an independent, progressive roastery in the Scandinavian specialty
coffee scene. Founded in the "beautifully uneventful" city of Västerås, Sweden, and
built on over 15 years of coffee and hospitality expertise, it has spread across
European specialty networks and earned a following among coffee geeks for playful
branding — humbly billing itself as "one more boring coffee roastery" — while
delivering deeply complex, award-winning lots.

Core philosophies & roasting style:

- **The "interesting coffee" manifesto** — a defiant stance against safe, predictable
  choices; they bypass mass-market lots to chase unusual origins, experimental
  processing, and rare botanical varieties.
- **Structured sensory tiering** — three clear tiers to help home brewers navigate an
  unconventional catalogue: **Base** (sweet, balanced, low-acidity lots celebrating
  origin terroir), **Explore** (funky, juicy, experimental micro-lots), and **Rare**
  (exceptionally limited elite quantities of the rarest varieties).
- **Transparent wholesale sourcing** — full-transparency micro-lots from tight-knit
  global networks, from yeast-inoculated anaerobic Pink Bourbons in Brazil to clean
  rare naturals from East Africa and Panama, each roasted to let origin and processing
  shine without heavy defects.
- **Digital-first Nordic distribution** — an agile, direct-to-consumer model, a
  regular fixture in specialty subscription boxes and curated European multi-roaster
  boutiques.'
  WHERE slug = 'maggma-beans' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Koff & Bun Coffee Roasters is a boundary-pushing force in Thailand''s modern specialty
coffee scene. Grown from an industrial micro-roastery in Bangkok''s Bang Khae district
into one of the capital''s most celebrated independent coffee houses, it earned major
prestige after winning the Thailand National Roasting Championship, blending serious
coffee pedigree with local heritage.

Core philosophies & roasting style:

- **Specialty coffee & fluffy bao** — a deliberate break from Western café concepts,
  bridging third-wave coffee with local street-food heritage by pairing precision
  roasts with traditional Chinese steamed buns (bao) and dim sum — fillings from
  savoury minced pork to sweet custard, black sesame, and salted egg.
- **Award-winning espresso profiling** — an in-house facility favouring deep
  complexity and smooth consistency over bright Nordic styles: heavy sweetness, rich
  body, and chocolate-caramel notes. Flagship blends like the Brazil-Laos and the 2449
  Thailand house roast are calibrated to anchor milk-based drinks and automated
  extraction.
- **Elite micro-lot collaborations** — strong ties to competitive coffee circles,
  hosting high-end sensory events (e.g. the limited "Brew for Next" series) showcasing
  ultra-rare award-winning lots like Finca Sophia Piedra Washed.
- **The historic Song Wat expansion** — a flagship in a converted old shophouse in
  Bangkok''s Chinatown, pairing warm minimalism with exposed brick and loft accents
  where old-world trading heritage meets contemporary extraction.'
  WHERE slug = 'koff-bun' AND blurb IS NULL;

UPDATE roasters SET blurb = '> Note: this is the **Slovakian** KAFFA (Považská Bystrica) — the roaster in the
> library. Not to be confused with Finland''s Kaffa Roastery (Helsinki), which isn''t
> in the catalogue.

KAFFA Specialty Coffee is an independent, progressive roastery in Slovakia''s modern
specialty scene. Founded in 2018 in Považská Bystrica, in the country''s northwest, it
set out to explore and showcase the highest-tier flavours raw coffee can offer, and
has become a prominent fixture in Central European specialty networks — known for
merging advanced barista training with meticulous micro-lot roasting.

Core philosophies & roasting style:

- **The farmer-centric manifesto** — named after the ancient Ethiopian word and
  historic birthplace of coffee, KAFFA bypasses generic commercial imports for green
  coffees whose distinct profiles reflect the region, variety, and the individual
  farmer''s production philosophy.
- **Flavour-driven roasting** — an expressive catalogue steering clear of smoky
  defects for clean, sweet, complex batches that preserve terroir across both espresso
  and filter.
- **The synesthetic packaging system** — coffee-bean-shaped labels whose colour
  combinations forecast the flavour profile (bright reds, oranges, greens for fruit
  tones), paired with "scattered" typography symbolising rising aromas — making the
  high-end market approachable at a glance.
- **The professional barista ecosystem** — more than an e-commerce supplier: a fully
  equipped barista training centre and sensory school (partnering with names like
  Faema) that elevates regional brewing standards and supports café partners.'
  WHERE slug = 'kaffa' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Manufaktura – The Coffee Shop Restaurant is an independent, multi-concept force in
Romania''s premium coffee and dining scene. Founded in Bucharest (roots back to 2014),
it has become one of the country''s most celebrated hybrid establishments, built on a
"coffee shop restaurant" blueprint that treats artisan brewing and gourmet bistro
cuisine with equal weight. It operates across high-profile hubs including Promenada
Mall, Mega Mall, and Aviatorilor.

Core philosophies & style:

- **The fresh-grind manifesto** — a specialised custom grinding line lets guests
  dictate the whole coffee journey on the spot, from selecting the lot down to the
  extraction profile and alternative brew method.
- **Gourmet single-origin rotations** — a curated catalogue of high-quality single
  origins and specialty coffees over mass-market blends, highlighting precise terroirs
  (fruit-forward Ethiopias, smooth Brazils) via both espresso and manual methods.
- **The dual-ecosystem hybrid menu** — premium origin coffee paired with world
  breakfasts, French-Italian bistro classics (fresh pastas, salads, artisan
  sandwiches), and natural Italian gelato sourced by Menodiciotto.
- **The "connoisseur hub" era** — a departure from transactional mall kiosks: striking
  wood paneling, open floor plans, and ambient lighting make each outpost a
  neighbourhood sanctuary for discovering new sensory profiles.'
  WHERE slug = 'manufaktura' AND blurb IS NULL;

UPDATE roasters SET blurb = '> ⚠️ Country mismatch for #133: the DB row `root-branch` is seeded as **Ireland**,
> but Root & Branch is in **Belfast, Northern Ireland (United Kingdom)**. Decide the
> correct `country_id` when populating.

Root & Branch Coffee is a pioneering force in Northern Ireland''s modern specialty
coffee scene. Founded in Belfast in 2016 by Simon Johnston and Ben Craig, it grew from
a backstreet brew bar into one of the industry''s most creative independent
micro-roasteries — Belfast''s first dedicated specialty micro-roaster — and was named
among the World''s Top 50 Coffee Roasters by Roastful.

Core philosophies & roasting style:

- **Direct trade & disruption** — an activist stance on value transparency: formed to
  bypass commodity brokers that squeeze farmer margins, building pure direct-trade
  relationships with organic producers in Ethiopia, Colombia, and El Salvador, with a
  portfolio of highly seasonal, traceable single origins.
- **Artisanal micro-roasting control** — roasting on a small high-precision Giesen
  drum roaster in East Belfast''s historic Portview Trade Centre, chasing light-to-
  medium profiles for terroir clarity, sweetness, and delicate fruit acids without
  smoky defects.
- **The craft-can revolution** — pioneered nitrogen-flushed, 100% recyclable aluminium
  cans over foil-lined plastic bags (inspired by craft beer, frustrated by
  "greenwashed" compostable bags), locking in freshness for global shipping; also an
  early integrator of advanced payment rails like Bitcoin.
- **Immersive community & food** — spaces known for live acoustic courtyard sessions
  and a food menu celebrating Irish culinary history through a modern lens, pairing
  pour-overs and espresso with local artisanal baked goods and dishes.'
  WHERE slug = 'root-branch' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Monmouth Coffee Company is a pioneering force in the global specialty coffee movement.
Founded in London in 1978 by Anita Le Roy and Nicholas Saunders as a basement roasting
operation on Monmouth Street in Covent Garden, it has grown over nearly five decades
into one of the world''s most revered independent roasters and a cornerstone of London
café culture — laying down the blueprint of "third-wave coffee" decades before the
term existed.

Core philosophies & roasting style:

- **Direct sourcing** — running direct-trade loops long before they were widespread,
  travelling to build long-term relationships with individual producers and
  cooperatives (e.g. Huila, Colombia), with a catalogue that turns over entirely by
  season to mirror crop cycles.
- **Precision eco-roasting** — now roasting in five converted Victorian railway arches
  at Spa Terminus in Bermondsey on hyper-efficient Loring drum roasters, favouring
  crisp sweetness and clean origin character over burnt, generic roasts.
- **The anti-paper-cup stance** — single-use paper cups banned entirely: on-site
  drinks in ceramic mugs, takeaway via a personal flask or a deposit-based reusable
  cup scheme.
- **Communal brick-and-mortar spaces** — three sought-after hubs (the original
  Monmouth Street flagship, the historic Borough Market counter, and Dockley Road),
  famous for winding queues, communal wooden tables, hand-brewed cone-filter stations,
  and open loose-bean baskets.'
  WHERE slug = 'monmouth' AND blurb IS NULL;

UPDATE roasters SET blurb = 'Dos Mundos is an independent, progressive roastery in Central Europe''s specialty
coffee scene. Founded in Prague in 2014 by partners Lukáš and Adéla, it has grown from
a boutique project into one of the Czech Republic''s most respected micro-roasteries.
Its name — Spanish for "Two Worlds" — marks the handshake where green coffee meets
master roasting, and it runs several flagship cafés across Prague.

Core philosophies & roasting style:

- **The "Two Worlds" sourcing manifesto** — bypassing commercial brokers to run up to
  ten rotating single origins at once, in fair, transparent partnerships with
  smallholder farmers across Latin America, East Africa, and the Pacific, each lot
  chosen to showcase its terroir.
- **Terroir-driven light roasting** — a Prague facility favouring clean, transparent
  light-to-medium profiles that avoid smoky defects, letting native acidity, crisp
  sweetness, and processing character guide the cup.
- **Immersive neighbourhood hubs** — Dos Mundos Café in Letná (Prague 7), a bright
  landmark famous for indoor wooden swing seats, and the Dos Mundos Coffee Roastery in
  Vinohrady (Prague 2), a cosy tasting sanctuary around a communal table and open
  retail wall.
- **Culinary synergy & education** — daily filter (custom V60s, batch brew) served
  with natural wines, brunches, and homemade Czech cakes including sought-after vegan
  pastries, plus a dedicated barista training school for the public.'
  WHERE slug = 'dos-mundos' AND blurb IS NULL;

UPDATE roasters SET blurb = '17g Coffee is an independent, social-impact-driven roastery in Switzerland''s specialty
coffee scene. Founded in 2020 as an educational project at Collège Alpin Beau Soleil
in Villars-sur-Ollon, it grew from an experimental school café into a professional,
internationally recognised, fully student-led non-profit micro-roastery. Its name
comes from the traditional 17-gram dose for a double espresso; SCA-certified, its young
team recently showcased at World of Coffee Geneva.

Core philosophies & roasting style:

- **The not-for-profit manifesto** — a 100% non-profit structure channelling all net
  proceeds back into origin-level development, improving living standards,
  infrastructure, and tools for smallholder communities, with a focus on direct-trade
  networks in Kenya.
- **Student-led precision roasting** — a trained team of high-school students controls
  everything from quality analysis to production logistics, roasting small precise
  batches in the Swiss Alps toward a clean profile that maximises sweetness and
  varietal character across filter and espresso.
- **Traceable micro-lot selection** — sourced on transparency, seasonality, and
  sustainability: high-scoring single origins and select blends that tell a clear
  geographic story, prioritising clean, defect-free lots.
- **The "learning by doing" ecosystem** — a production facility and espresso hub where
  certified student baristas serve the campus community, with fully recyclable retail
  packaging and an eco-conscious direct-to-consumer shop alongside wholesale supply.'
  WHERE slug = '17g-coffee' AND blurb IS NULL;
