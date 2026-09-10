# MyCoffee — Evaluate (Chrome extension)

Score a coffee against your own tasted library while you're on a roaster's shop
page. Backlog #159–#162; the score itself is #106's, reached through
`POST /api/score`.

## Install (2 minutes, no Web Store)

**Get the files as a git clone, not a ZIP** — auto-update below needs git, and
this way you only download the extension folder (~88 KB), not the whole repo:

```bash
git clone --filter=blob:none --sparse https://github.com/Climb-Again/MyCoffee.git mycoffee-ext
cd mycoffee-ext && git sparse-checkout set extension
```

(Already have the repo cloned for other work? Just `git pull` and use its
`extension/` folder.)

Then:

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. Click **Load unpacked** and pick the `extension/` folder (the one with
   `manifest.json` in it)
4. Click the extension's **Details → Extension options**
5. Paste your **read token** (`APP_TOKEN`) and hit **Save**, then **Test connection**

Pin it to the toolbar so the button is one click away. Then open any coffee
product page and click it.

## Auto-update (run once, then never think about it)

```bash
bash extension/install-autoupdate.sh
```

That installs a launchd agent that runs `git pull` in the checkout every hour
and at login. The extension checks GitHub for a newer version every three hours
and reloads itself when it finds one — and for an unpacked extension, reloading
re-reads every file from disk. Between the two, updates arrive on their own.

**Both halves are needed.** An unpacked extension cannot write its own files, so
something outside Chrome has to fetch them; and nothing outside Chrome can make
Chrome re-read them, so the extension has to reload itself. Neither works alone,
which is why the ZIP route can't auto-update at all.

Only a version *string* is ever fetched from GitHub — no code is downloaded or
executed. MV3 forbids remote code and this respects that: the only thing that
changes the extension's behaviour is a file `git pull` put on disk.

**Options → Updates** shows the state. If it says a version is available but
reloading isn't picking it up, the `git pull` half isn't running — check
`launchctl list | grep mycoffee` and `~/Library/Logs/mycoffee-extension-update.log`.

To undo:

```bash
launchctl bootout gui/$(id -u)/ro.climbagain.mycoffee.extension-update
rm ~/Library/LaunchAgents/ro.climbagain.mycoffee.extension-update.plist
```

> Use `APP_TOKEN`, **not** `INGEST_TOKEN`. Scoring never writes anything, so the
> extension only needs read access — and whatever token it carries lives in the
> browser profile, where anything that can read your disk can read it.
>
> There is a **second, optional "write token"** field. It is only needed to add
> missing details to a coffee you already own (below). Leave it blank and
> everything else still works.

Chrome forgets an unpacked extension's service worker between uses but keeps
your settings; you never need to re-enter the token, and an update never clears
them.

## What the number means

**Fit with what you buy — not a predicted rating.** #106 measured this against
the real 363-coffee corpus: origin, roaster, process and roaster-country each
carry r≈0.26–0.31, and blended they reach r≈0.39. That is a real signal but a
loose one, so the wording everywhere is "matches what you buy". Flavour notes
carry nothing measurable (LOO r=−0.01) and are deliberately not used.

Three components, shown with equal weight to the headline because they are the
part that is actually defensible:

| Component | Weight | What it is |
|---|---|---|
| **Affinity** | 50 | Shrunk means for roaster / origin / process / roaster-country, as a percentile within your own library. |
| **Freshness** | 20 | Roast recency — full marks to 14 days, decaying to zero at 180. |
| **Value** | 15 | Asking €/100 g against what you normally pay for bags you rate the same. |
| **Novelty** | 10 | **New scores higher**: new roaster +50, new origin +50. |

Those sum to 95, not 100 — deliberately. The blend renormalises over whichever
components are actually present, so the **ratios** are what matter, and these
are exactly the ratios asked for. In practice they land at 52.6 / 21.1 / 15.8 /
10.5.

**Past 40 days a further 10 points come off**, on top of the decay. You'll see
the drop as a step, not a slope — that's deliberate.

**A page with no roast date is judged on affinity and value alone**, with the
weights renormalised. It is never penalised for the gap — but a bag you can see
is fresh will out-score one you can't, which is the point.

**No headline number appears when** the roaster, origin and process are all
unseen or under ~5 rated bags (`low` confidence), or when the page gave no
usable price. Both are deliberate: the components are shown and the reason is
stated rather than a number being invented.

### Why these weights, and why novelty points the way it does

Affinity leads because it is the only component ever measured **as a predictor**
of your ratings — leave-one-out r≈0.39 (#106). Value was called "reliable" in
that study, but that meant deterministic and low-noise: it is a price
comparison, never validated as a rating predictor. So putting the measured
predictor first follows the evidence rather than departing from it.

**Novelty is directional: new scores higher.** #106 deliberately left it neutral
("new is neither good nor bad"), and that was right while it carried no weight —
but a weighted term has to point somewhere, or it just drags every score toward
the middle. It points at the unfamiliar because this is a tool for deciding what
to buy *next*. The useful side effect is a tension with affinity: affinity says
"you like this kind", novelty says "but you've already had this one", so the two
together favour **new bags within styles you like**.

Roast recency remains the one factor with **no leave-one-out validation** behind
it: the corpus carries too few roast dates to measure it the way the others were.

## Why the price matters more than anything else on the page

`pricePer100gEur` needs **an amount and a recognised currency and a weight** —
all three, or the value half (0.50 of the headline) is gone. Five of the ten
samples in `status/backend.md`'s review produced no headline for exactly this
reason.

A shop page is the best input this feature will ever get: the price is usually
in JSON-LD, and the grams are usually in the variant name. The scraper reads the
**selected variant** for that reason — take the base product and the grams
vanish. When something is missing the popup says which, rather than quietly
scoring on affinity alone.

## How it works

```
toolbar click
   └─ scrape.js      injected into the active tab (activeTab, on click only)
        │            JSON-LD Product → OpenGraph → selected variant → visible text
        ▼
   └─ background.js  service worker; POSTs {url, text} to /api/score
        │            the fetch lives here so no CORS is needed — see below
        ▼
   └─ popup.js       renders score, components, extracted fields, gaps
```

Three deliberate choices:

- **`activeTab`, not a content script.** The extension reads a page only after
  you click the button, so it needs no standing permission over every shop site
  you visit. `host_permissions` covers the API host and nothing else.
- **The fetch is in the service worker.** An MV3 service-worker fetch covered by
  `host_permissions` is exempt from CORS, so the backend needs no
  `@fastify/cors` and no allow-origin header for shop domains. Move that fetch
  into the page and it breaks.
- **No per-retailer parsers.** The scraper gathers generously; the server's
  deterministic pipeline — the same free rules voter the batch worker runs
  first — does the parsing. No LLM call is made, so scoring a page costs $0 and
  takes no thinking-token budget.

## When you already own the coffee

If the page is a coffee that's already in your library, the popup leads with
**that** rather than a score — *"You have this one · May 2018 · 4.0★"* — because
a fit score for a bag you already own answers the wrong question. It always says
**why** it matched (*"matched on sopacdi"*), because the match can be wrong and a
match you can't sanity-check is one you can't correct.

Underneath, it lists what the page could **add** to your stored record — roast
date, weight, price, altitude, process, origin, farm — one tap each. **If the
page adds nothing, nothing is shown.**

Three rules it follows:

- **Fill blanks only.** A field you already have is never offered, and nothing
  is ever overwritten. Accepts go through the same edit endpoint the iOS edit
  sheet uses, so anything you've decided by hand is untouchable, and each
  accepted field lands human-locked — correct, since you tapped it.
- **Matching is deliberately conservative.** The roaster must match exactly, and
  beyond that at least one *distinctive* word must be shared. Origin and process
  agreeing is not enough: "Gardelli Ethiopia Washed" describes plenty of
  different bags. A false "you own this" would invite you to write page data
  onto the wrong record, so the matcher would rather say nothing.
- **No "Add as new".** New bags are still added in the iOS app. This is only for
  coffees already in the library.

## Your last 10 days, ranked

Every coffee you evaluate is saved, and the popup always carries a **Top
coffees** section — the highest-scoring pages from the last **10 days**, best
first. Anything older is discarded automatically. Revisiting a page updates its
entry rather than adding a second one, so the ranking stays "best coffees", not
"pages I refreshed most".

Each row is the app's listing row: image · **ROASTER** / title / origin ·
score, €/100g and the value pills on the right — with the **fit score in the
rating's slot**, since that's the number this surface knows. **Why?** opens the
evaluator note. Clicking the title opens the shop page again.

Under each one: **roast age, colour-coded** — green under two weeks, ramping to
red past 40 days — and **when you looked at it**. Those two belong together,
because the age shown is the age *at the time of the visit*, matching the score
that was saved with it. A bag that was 30 days old when you saw it last week is
a different bag today.

The section and the notes both start collapsed, because ten rows plus the
current page doesn't fit a popup. Your choice is remembered.

It's always there — open the popup on any tab, even a non-coffee one, and the
top 10 is still the bottom half of the panel.

Coffees with no headline score (no price on the page) are still saved but can't
be ranked, so they're counted at the bottom rather than sorted as if they were
zero.

**This lives in the browser, not the backend** — it needs no token and no
round-trip, and it stays on this machine. The tradeoff is that it doesn't reach
the iOS app; say so if you'd rather it did.

## Limits

- Chrome refuses injection on `chrome://` pages, the Web Store, and PDFs.
- The roaster must be in your vocab to be recognised. An unknown roaster isn't
  an error — it scores as novel, with lower confidence.
- Identical page text is cached for 10 minutes server-side; the popup says
  "cached result" when you're seeing one.
- "Add as new" is not built and is not planned here — the iOS app stays how new
  bags are added.
- History is per-browser and per-profile. Clearing Chrome's site data for the
  extension clears it; it does not sync to another machine or to the app.
- Enrichment needs a page title and a recognised roaster. Without both, matching
  would be guesswork, so the popup just shows the score.
- **Prices in RON, CZK or PLN are currently dropped** — the parser knows the
  symbols (`lei`, `kč`, `zł`) but not those ISO codes, and JSON-LD always uses
  codes. On those shops you get affinity but no value half. Backlog #185.
