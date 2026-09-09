# MyCoffee — Evaluate (Chrome extension)

Score a coffee against your own tasted library while you're on a roaster's shop
page. Backlog #159–#162; the score itself is #106's, reached through
`POST /api/score`.

## Install (2 minutes, no Web Store)

1. Open `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. Click **Load unpacked** and pick this `extension/` folder
4. Click the extension's **Details → Extension options**
5. Paste your **read token** (`APP_TOKEN`) and hit **Save**, then **Test connection**

Pin it to the toolbar so the button is one click away. Then open any coffee
product page and click it.

> Use `APP_TOKEN`, **not** `INGEST_TOKEN`. Scoring never writes anything, so the
> extension only needs read access — and whatever token it carries lives in the
> browser profile, where anything that can read your disk can read it.

Chrome forgets an unpacked extension's service worker between uses but keeps
your settings; you never need to re-enter the token.

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
| **Value** | 0.50 | Asking €/100 g against what you normally pay for bags you rate the same. The only genuinely reliable component. |
| **Affinity** | 0.35 | Shrunk means for origin / roaster / process / roaster-country, expressed as a percentile within your own library. |
| **Novelty** | 0.15 | Enters as a fixed neutral 50 — "new" is neither good nor bad — and surfaces as a tag. |
| **Freshness** | ±10 pts | Roast recency, on top of the blend. See the caveat below. |

**No headline number appears when** the roaster, origin and process are all
unseen or under ~5 rated bags (`low` confidence), or when the page gave no
usable price. Both are deliberate: the components are shown and the reason is
stated rather than a number being invented.

### The freshness caveat

Roast recency is the one factor with **no leave-one-out validation** behind it —
the corpus carries too few roast dates to measure it the way the other four were
measured. So it is capped at 10 points of a 0–100 score, and a page with no
roast date is treated as neutral, never penalised. The curve is full marks to 14
days, then linear decay to zero at 180.

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

## Limits

- Chrome refuses injection on `chrome://` pages, the Web Store, and PDFs.
- The roaster must be in your vocab to be recognised. An unknown roaster isn't
  an error — it scores as novel, with lower confidence.
- Identical page text is cached for 10 minutes server-side; the popup says
  "cached result" when you're seeing one.
- Evaluate only. "Add as new" and "Enrich existing" are #161/#162's second half
  and are not built yet.
