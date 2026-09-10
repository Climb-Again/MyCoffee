// The page scraper (#162). Injected into the active tab on demand via
// chrome.scripting.executeScript — NOT a content script. That is deliberate:
// `activeTab` means this only ever reads a page after Radu clicks the toolbar
// button, so the extension needs no standing permission over every shop site
// he visits, and pages he merely browses are never touched.
//
// The job here is to GATHER GENEROUSLY, NOT TO PARSE. The backend runs the
// same deterministic pipeline the batch worker's free rules voter uses
// (roaster vocab, origin vocab, price, weight, roast date, process) over
// whatever text this returns, so a per-retailer parser would be work the
// server already does better. Radu's call in #162: generic whole-page text, no
// per-retailer adapters.
//
// The one thing worth being precise about is PRICE and WEIGHT, because
// `pricePer100gEur` needs an amount AND a recognised currency AND grams, and
// without all three the value component — half the headline — is gone. Five of
// the ten samples in status/backend.md produced no headline for exactly this
// reason. So structured sources are read first, and the SELECTED VARIANT is
// preferred over the base product: the grams almost always live in the variant
// name ("250g", "1kg"), and taking the base product silently loses them.

export function scrapePage() {
  const MAX = 60_000;
  const out = [];
  const push = (label, value) => {
    if (value == null) return;
    const s = String(value).trim();
    if (s) out.push(label ? `${label}: ${s}` : s);
  };

  // --- 1. JSON-LD Product. Shopify and WooCommerce both emit it, which covers
  // most specialty roasters, and it carries price + currency structurally so
  // nothing has to be guessed out of prose.
  const seenOffers = new Set();
  const readOffer = (offer) => {
    if (!offer || typeof offer !== 'object') return;
    if (Array.isArray(offer)) return offer.forEach(readOffer);
    const price = offer.price ?? offer.lowPrice ?? offer.priceSpecification?.price;
    const currency =
      offer.priceCurrency ?? offer.priceSpecification?.priceCurrency ?? offer.priceSpecification?.currency;
    if (price == null) return;
    const key = `${price}|${currency ?? ''}`;
    if (seenOffers.has(key)) return;
    seenOffers.add(key);
    // Emit as "12.50 EUR" — a currency code next to the number is exactly what
    // the server's price regex is gated on.
    push('Price', currency ? `${price} ${currency}` : `${price}`);
  };

  const readProduct = (node) => {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) return node.forEach(readProduct);
    const type = node['@type'];
    const types = Array.isArray(type) ? type : [type];
    if (types.includes('Product') || types.includes('ProductGroup')) {
      push('Product', node.name);
      push('Brand', typeof node.brand === 'object' ? node.brand?.name : node.brand);
      push('Description', node.description);
      // Marker line, stripped before the text is sent (see the return below).
      const img = Array.isArray(node.image) ? node.image[0] : node.image;
      const imgUrl = typeof img === 'string' ? img : img?.url;
      if (imgUrl) out.push(`__IMAGE__:${imgUrl}`);
      push('Weight', node.weight?.value ? `${node.weight.value}${node.weight.unitText ?? ''}` : null);
      readOffer(node.offers);
      if (Array.isArray(node.hasVariant)) node.hasVariant.forEach(readProduct);
    }
    if (node['@graph']) readProduct(node['@graph']);
  };

  for (const el of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      readProduct(JSON.parse(el.textContent));
    } catch {
      // A malformed blob on one shop must never stop the scrape.
    }
  }

  // --- 2. OpenGraph / meta. Fills the price in when JSON-LD is absent.
  const meta = (sel) => document.querySelector(sel)?.getAttribute('content') ?? null;
  push('Title', meta('meta[property="og:title"]') || document.title);
  const ogPrice = meta('meta[property="product:price:amount"]') || meta('meta[property="og:price:amount"]');
  const ogCurrency = meta('meta[property="product:price:currency"]') || meta('meta[property="og:price:currency"]');
  if (ogPrice) push('Price', ogCurrency ? `${ogPrice} ${ogCurrency}` : ogPrice);
  push('Summary', meta('meta[property="og:description"]') || meta('meta[name="description"]'));

  // --- 3. The selected variant. This is where the grams live. A checked radio,
  // a selected <option>, or a pressed variant button all mean "this is the size
  // he is looking at" — and its label ("250 g", "1kg") is the weight.
  const variantBits = [];
  for (const sel of document.querySelectorAll('select')) {
    const opt = sel.selectedOptions?.[0];
    if (opt?.textContent) variantBits.push(opt.textContent.trim());
  }
  for (const input of document.querySelectorAll('input[type="radio"]:checked')) {
    const label =
      (input.labels && input.labels[0]?.textContent) ||
      document.querySelector(`label[for="${CSS.escape(input.id || '')}"]`)?.textContent ||
      input.value;
    if (label) variantBits.push(String(label).trim());
  }
  for (const el of document.querySelectorAll(
    '[aria-checked="true"],[aria-selected="true"],.is-selected,.selected,[data-selected="true"]',
  )) {
    const t = el.textContent?.trim();
    // Long matches are almost always a container, not a variant chip.
    if (t && t.length <= 40) variantBits.push(t);
  }
  const variants = [...new Set(variantBits)].filter(Boolean).slice(0, 12);
  if (variants.length) push('Selected', variants.join(' | '));

  // --- 4. Visible text, as the catch-all. Roast date, process and origin are
  // usually written in prose on these pages, and the server's rules voter is
  // built to read exactly that.
  const main =
    document.querySelector('main') ||
    document.querySelector('[role="main"]') ||
    document.querySelector('article') ||
    document.body;
  const text = (main?.innerText ?? '')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .join('\n');
  push(null, text);

  // The history list (#187) mirrors the app's listing row, which leads with a
  // photo, so grab the product image. JSON-LD first (it names the product
  // image specifically), then OpenGraph. Never a page-relative path: the popup
  // renders it from a different origin, so only an absolute URL is usable.
  let imageUrl = null;
  const absolute = (u) => {
    try {
      const abs = new URL(u, location.href).href;
      return abs.startsWith('http') ? abs : null;
    } catch {
      return null;
    }
  };
  for (const line of out) {
    if (!line.startsWith('__IMAGE__:')) continue;
    imageUrl = absolute(line.slice('__IMAGE__:'.length).trim());
    if (imageUrl) break;
  }
  if (!imageUrl) imageUrl = absolute(meta('meta[property="og:image"]') ?? '');

  return {
    url: location.href,
    title: document.title,
    imageUrl,
    // The image marker lines are scaffolding for the block above, not text
    // worth extracting from — strip them before the server sees them.
    text: out.filter((l) => !l.startsWith('__IMAGE__:')).join('\n').slice(0, MAX),
  };
}
