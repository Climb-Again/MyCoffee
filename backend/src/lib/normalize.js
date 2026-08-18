// Pure normalisers — no DB, no network. The highest-value test surface in the
// project (PLAN.md §2): every function here takes raw caption/label text and
// returns a typed, confidence-scored value, or null when it can't tell.
//
// Number parsing is resolved by SHAPE (which separator, how many trailing
// digits) and, only where genuinely ambiguous, by FIELD. There is deliberately
// no single shared number parser — `1.6` means 1600 for an altitude and 1.6
// for a rating, and conflating those two would silently corrupt one of them.

export function normalizeVocabString(s) {
  if (s == null) return '';
  return String(s).trim().replace(/\s+/g, ' ').toLowerCase();
}

export function foldDiacritics(s) {
  if (s == null) return '';
  return String(s).normalize('NFKD').replace(/[\u0300-\u036f]/g, '');
}

function includesTerm(normalizedText, term) {
  if (term.length <= 3) {
    return new RegExp(`\\b${term}\\b`).test(normalizedText);
  }
  return normalizedText.includes(term);
}

// ---- Core number parsing: shape-driven, field-aware only where ambiguous ----

export function parseNumber(raw, { field } = {}) {
  if (raw == null) return null;
  let s = String(raw).trim();
  if (!s) return null;
  const negative = s.startsWith('-');
  s = s.replace(/^[-+]/, '').replace(/\s/g, '');
  if (!s || !/^[0-9.,]+$/.test(s)) return null;

  const hasDot = s.includes('.');
  const hasComma = s.includes(',');
  let value;

  if (hasDot && hasComma) {
    const lastDot = s.lastIndexOf('.');
    const lastComma = s.lastIndexOf(',');
    value = lastDot < lastComma
      ? parseFloat(s.replace(/\./g, '').replace(',', '.')) // '.' groups, ',' decimal: 1.600,50
      : parseFloat(s.replace(/,/g, ''));                    // ',' groups, '.' decimal: 1,600.50
  } else if (hasComma) {
    value = /^\d{1,3}(,\d{3})+$/.test(s)
      ? parseFloat(s.replace(/,/g, ''))  // '1,600' — thousands group
      : parseFloat(s.replace(',', '.')); // '4,1'   — decimal comma
  } else if (hasDot) {
    if (/^\d{1,3}(\.\d{3})+$/.test(s)) {
      value = parseFloat(s.replace(/\./g, ''));       // '1.600' — thousands group
    } else if (field === 'altitude' && /^\d{1,3}\.\d{1,2}$/.test(s)) {
      value = parseFloat(s) * 1000;                    // '1.6' altitude shorthand -> 1600
    } else {
      value = parseFloat(s);                            // '4.1' plain decimal
    }
  } else {
    value = parseFloat(s);
  }

  if (!Number.isFinite(value)) return null;
  return negative ? -value : value;
}

// ---- Altitude ----

// Altitude unit tokens. Longest/most-specific first so "meter" isn't matched as
// a bare "m" (the alternation is ordered): "2000 meter" / "2000 metres" /
// "2000 metros" and the Spanish "m.s.n.m."/"msnm" now parse, not just "m"/
// "masl". Root cause of a review accept 422'ing on a candidate like
// "2000 meter" (the extractor kept the bag's own wording).
const ALTITUDE_UNIT = String.raw`m\.?a\.?s\.?l\.?|masl|m\.?s\.?n\.?m?\.?|met(?:er|re)s?|metros?|mts?|m`;
const ALTITUDE_RANGE_RE = new RegExp(String.raw`(\d[\d.,]*)\s*(?:-|–|to|ro)\s*(\d[\d.,]*)\s*(?:${ALTITUDE_UNIT})?\b`, 'i');
const ALTITUDE_SINGLE_RE = new RegExp(String.raw`(\d[\d.,]*)\s*(?:${ALTITUDE_UNIT})\b`, 'i');

export function parseAltitude(text) {
  if (!text) return null;
  const s = String(text);
  let min, max;

  const rangeMatch = s.match(ALTITUDE_RANGE_RE);
  if (rangeMatch) {
    min = parseNumber(rangeMatch[1], { field: 'altitude' });
    max = parseNumber(rangeMatch[2], { field: 'altitude' });
  } else {
    const singleMatch = s.match(ALTITUDE_SINGLE_RE);
    if (!singleMatch) return null;
    min = max = parseNumber(singleMatch[1], { field: 'altitude' });
  }
  if (min == null || max == null) return null;
  if (min > max) [min, max] = [max, min];

  // Hard plausibility envelope: coffee grows ~200-4000m. Below/above that the
  // extractor almost certainly grabbed something else (a roast-level scale, a
  // count) rather than a real elevation — absent is safer than a bogus value,
  // and accept-by-default no longer has a confidence gate to catch it (#39).
  if (max < 200 || min > 4000) return null;

  const plausible = min >= 900 && max <= 2200;
  const wideSpan = max - min > 800;
  return {
    // altitude_min_m / altitude_max_m are INTEGER columns — round so a decimal
    // elevation can't abort the coffee insert (same class as weight above).
    min: Math.round(min),
    max: Math.round(max),
    unit: 'm',
    confidence: plausible ? 1.0 : 0.5,
    needsReview: wideSpan || !plausible,
  };
}

// ---- Price ----

const CURRENCY_PATTERNS = [
  [/(\d[\d.,]*)\s*(?:€|eur\b)/i, 'EUR'],
  [/€\s*(\d[\d.,]*)/i, 'EUR'],
  [/(\d[\d.,]*)\s*lei\b/i, 'RON'],
  [/(\d[\d.,]*)\s*(?:kč|kc\b)/i, 'CZK'],
  [/(\d[\d.,]*)\s*(?:zł|zl\b)/i, 'PLN'],
  [/(\d[\d.,]*)\s*(?:ft|huf)\b/i, 'HUF'],
  [/\$\s*(\d[\d.,]*)/i, 'USD'],
  [/(\d[\d.,]*)\s*usd\b/i, 'USD'],
  [/£\s*(\d[\d.,]*)/i, 'GBP'],
  [/(\d[\d.,]*)\s*gbp\b/i, 'GBP'],
  [/(\d[\d.,]*)\s*chf\b/i, 'CHF'],
];

export function parsePrice(text) {
  if (!text) return null;
  const s = String(text);
  for (const [re, currency] of CURRENCY_PATTERNS) {
    const m = s.match(re);
    if (m) {
      const amount = parseNumber(m[1], { field: 'price' });
      if (amount == null) continue;
      return { amount, currency, confidence: 1.0 };
    }
  }
  // Bare number, no currency marker — low confidence, never silent.
  const bare = s.match(/(\d[\d.,]*)/);
  if (!bare) return null;
  const amount = parseNumber(bare[1], { field: 'price' });
  if (amount == null) return null;
  return { amount, currency: null, confidence: 0.5 };
}

// ---- Weight ----

const WEIGHT_RE = /(\d[\d.,]*)\s*(g|gr|grams?)\b/i;
const WEIGHT_STANDARD_G = [100, 200, 250];

export function parseWeight(text) {
  if (!text) return null;
  const s = String(text);
  const match = s.match(WEIGHT_RE);
  if (!match) return null;

  // A number immediately glued to a bare 'm' right before this match (e.g. an
  // OCR-mangled "1600m250g") is more likely an altitude bleeding into the
  // weight parse than a real weight — refuse to guess rather than misparse.
  const before = s.slice(Math.max(0, match.index - 4), match.index);
  if (/\dm$/i.test(before)) return null;

  const grams = parseNumber(match[1], { field: 'weight' });
  if (grams == null) return null;
  // Hard plausibility envelope: a coffee bag is never sub-gram or over 5kg (#39).
  if (grams < 1 || grams > 5000) return null;
  const snapped = WEIGHT_STANDARD_G.find((v) => Math.abs(v - grams) <= 3);
  return {
    // `weight_g` is an INTEGER column, so a decimal ("18.5 g") must be rounded
    // or the coffee insert throws `invalid input syntax for type integer` and
    // aborts the whole extraction of that photo.
    grams: snapped ?? Math.round(grams),
    confidence: snapped ? 1.0 : 0.6,
  };
}

// ---- Rating ----

// A rating is always out of 5 — anything outside that scale is a different
// quantity (an altitude, a count) misfiring this parser, not a real rating.
function inRatingScale(value) {
  return value != null && value >= 0 && value <= 5;
}

export function parseRating(text) {
  if (!text) return null;
  const s = String(text);

  let m = s.match(/(\d[.,]?\d?)\s*\/\s*5\b/);
  if (m) {
    const value = parseNumber(m[1], { field: 'rating' });
    return inRatingScale(value) ? { value, confidence: 1.0 } : null;
  }

  m = s.match(/⭐️?\s*(\d[.,]?\d?)/u);
  if (m) {
    const value = parseNumber(m[1], { field: 'rating' });
    return inRatingScale(value) ? { value, confidence: 0.9 } : null;
  }

  m = s.match(/(\d[.,]?\d?)/);
  if (m) {
    const value = parseNumber(m[1], { field: 'rating' });
    return inRatingScale(value) ? { value, confidence: 0.6 } : null;
  }

  return null;
}

// ---- Dates ----

export function parseDate(text, { photoDate } = {}) {
  if (!text) return null;
  const s = String(text).trim();
  let day, month, year;

  let m = s.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$/);
  if (m) {
    // Day-first when ambiguous.
    day = parseInt(m[1], 10);
    month = parseInt(m[2], 10);
    year = parseInt(m[3], 10);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    if (month > 12 && day <= 12) [day, month] = [month, day];
  } else {
    m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/); // ISO
    if (m) {
      year = +m[1];
      month = +m[2];
      day = +m[3];
    }
  }
  if (year == null || month < 1 || month > 12 || day < 1 || day > 31) return null;

  const date = new Date(Date.UTC(year, month - 1, day));
  if (Number.isNaN(date.getTime())) return null;

  if (photoDate) {
    const photo = photoDate instanceof Date ? photoDate : new Date(photoDate);
    if (date.getTime() > photo.getTime()) {
      return { date, rejected: true, reason: 'roast date after photo date' };
    }
  }
  return { date, rejected: false };
}

// ---- Roast profile + decaf (orthogonal) ----

// Order matters: a caption often names two processes at once ("Co-Fermentata cu
// fructe, Washed", "Experimental Washed"), and the first match wins. The
// distinguishing process is checked before the generic one, so a co-fermented
// washed coffee reads as co-fermented rather than plain washed. `experimental`
// stays last so it acts as the catch-all rather than swallowing "Experimental
// Washed", which is a real washed process.
// Romanian forms are first-class here: the corpus is a Romanian shop's copy
// ("Procesare: Anaerob", "Co-Fermentata cu fructe"), and 'anaerobic' does not
// substring-match 'anaerob'.
const PROFILE_ALIASES = [
  ['co_fermented', ['co-fermented', 'co-ferment', 'cofermented', 'co-fermentata', 'cofermentata', 'infused']],
  ['anaerobic', ['anaerobic', 'anaerob', 'carbonic maceration', 'cm']],
  ['natural', ['natural', 'dry process', 'uscat']],
  ['washed', ['lavado', 'spalat', 'spalata', 'fully washed', 'washed']],
  ['experimental', ['experimental', 'thermal shock', 'double fermentation', 'yeast', 'lactic']],
];

// Process is clearly being described, but by a name we don't model. Radu's
// rule: structure it if at least one known profile matches, otherwise file it
// under Experimental — but only when the text actually talks about processing,
// so a caption that never mentions it stays NULL instead of being mislabelled.
// Deliberately a *labelled* pattern ("Procesare: …", "Process: …") or an
// explicit fermentation word, not the bare noun: prose like "a bag with no
// process mentioned" must not label the coffee Experimental.
const PROCESS_LABEL_RE = /\b(procesare|processing|process|proces)\s*[:=]/i;
const FERMENT_RE = /\bfermenta/i;

// Checked in order, most specific phrase first, so the literal preserved in
// profile_detail is the fullest term actually present ("Yellow Honey", not
// just "Honey").
const HONEY_TERMS = ['yellow honey', 'black honey', 'pulped natural', 'honey'];

// 'decaf' substring-matches 'decaffeinated'/'decafeinizata' too, which is how
// the corpus usually spells it. NOT a bare 'ea': the captions are Romanian,
// where "ea" is an ordinary word ("she"), so the ethyl-acetate process has to
// be named explicitly or every other record would come out decaf.
const DECAF_TERMS = [
  'decaf',
  'decofeinizat',
  'swiss water',
  'co2 process',
  'fara cofeina',
  'ethyl acetate',
  'ea process',
  'ea decaf',
  'sugarcane ea',
];

function findLiteral(text, term) {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = String(text).match(new RegExp(escaped, 'i'));
  return m ? m[0] : term;
}

export function parseProfile(text) {
  if (!text) return { profileId: null, isDecaf: false, detail: null };
  const norm = foldDiacritics(String(text)).toLowerCase();

  let isDecaf = false;
  for (const term of DECAF_TERMS) {
    if (includesTerm(norm, term)) {
      isDecaf = true;
      break;
    }
  }

  const honeyTerm = HONEY_TERMS.find((h) => includesTerm(norm, h));
  let structured = null;
  for (const [profileId, terms] of PROFILE_ALIASES) {
    const hit = terms.find((t) => includesTerm(norm, t));
    if (hit) {
      structured = { profileId, term: hit };
      break;
    }
  }

  // A structured profile wins over Honey ("Co-Fermentata cu fructe, Honey" is
  // co-fermented, with Honey kept in `detail`) — *unless* the structured term is
  // merely a fragment of the honey phrase itself. "Pulped natural" is a honey
  // process, not a natural one, and the word "natural" inside it must not
  // hijack the classification.
  if (structured && !(honeyTerm && honeyTerm.includes(structured.term))) {
    return { profileId: structured.profileId, isDecaf, detail: honeyTerm ? findLiteral(text, honeyTerm) : null };
  }

  // Honey has no class of its own, so it files under Experimental, keeping the
  // fullest literal ("Yellow Honey", not just "Honey") in profile_detail.
  if (honeyTerm) {
    return { profileId: 'experimental', isDecaf, detail: findLiteral(text, honeyTerm) };
  }

  // Processing is described but under a name we don't model -> Experimental,
  // per Radu's rule. Requires a process *label* or an explicit fermentation
  // word, so ordinary prose can't trigger it.
  if (PROCESS_LABEL_RE.test(text) || FERMENT_RE.test(norm)) {
    return { profileId: 'experimental', isDecaf, detail: null };
  }

  // Nothing about process at all — never default to Washed, even though it's
  // the modal class.
  return { profileId: null, isDecaf, detail: null };
}

// ---- Farm / producer ----

const FARM_PREFIXES = [
  ['finca', /^finca\s+/i],
  ['fazenda', /^fazenda\s+/i],
  ['producer', /^producer:?\s+/i],
  ['washing_station', /^washing station:?\s+/i],
];

export function parseFarm(text) {
  if (!text) return null;
  let s = String(text).trim();
  let kind = null;

  for (const [k, re] of FARM_PREFIXES) {
    if (re.test(s)) {
      s = s.replace(re, '').trim();
      kind = k;
      break;
    }
  }

  // "Finca El Paraiso — Diego Bermudez" and "Producer: Diego Bermudez" must
  // resolve to the same row: take the part after a dash as the residual name.
  const parts = s.split(/\s*[—–-]\s*/);
  const residual = parts.length > 1 ? parts[parts.length - 1] : s;
  return { name: residual.trim(), kind };
}

// ---- City -> country (ambiguous cities never auto-accept) ----

export function resolveCityCountry(cityName, cityMap) {
  if (!cityName || !cityMap) return null;
  const key = normalizeVocabString(cityName);
  const entry = cityMap.get ? cityMap.get(key) : cityMap[key];
  if (!entry || entry.ambiguous) return null;
  return entry.countryName ?? entry.country ?? null;
}
