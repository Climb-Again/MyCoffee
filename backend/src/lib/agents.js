// The 4 LLM voters (PLAN.md §2: P1 extract-A, P2 extract-B, P4 critic,
// P5 reconciler) built on top of `../vertex.js`. P3 (rules) is deterministic,
// no-network, and owned by the data lane's `deterministic.js` (#25) -- see
// `loadRulesVoter()` below for how the worker picks it up once it exists.
//
// Prompt building and response parsing are pure (no network), same split as
// `vertex.js`'s `buildRequestBody`/`parseResponse`, so prompt shaping and
// output parsing are unit-testable without a live Vertex call. Only
// `runExtractA`/`runExtractB`/`runCritic`/`runReconciler` touch the network.
import { generateContent } from '../vertex.js';

export const PROMPT_VERSION = 'v1';

// camelCase (wire/schema) <-> snake_case (adjudicate.js field key).
export const FIELD_KEY_MAP = {
  roaster: 'roaster_id',
  originCountries: 'origin_country_ids',
  originFarm: 'origin_farm_id',
  altitude: 'altitude',
  price: 'price',
  weightG: 'weight_g',
  rating: 'rating',
  roastedOn: 'roasted_on',
  profile: 'profile',
  descFarmLot: 'desc_farm_lot',
  descBrewGuide: 'desc_brew_guide',
  descRoasterCopy: 'desc_roaster_copy',
};

const PROSE_KEYS = ['descFarmLot', 'descBrewGuide', 'descRoasterCopy'];

const TEXT_FIELD_SCHEMA = {
  type: 'object',
  properties: {
    value: { type: 'string' },
    confidence: { type: 'number' },
    evidence: { type: 'string' },
  },
};

// Character offsets into the raw text, not rewritten prose (PLAN.md §2 point
// 6: "prose is selected, not voted") -- Vertex rejects `minimum`/`maximum` on
// generated/response schemas, so bounds-checking the offsets happens in
// `adjudicate.js`'s canonicalize(), not here.
const PROSE_FIELD_SCHEMA = {
  type: 'object',
  properties: {
    start: { type: 'integer' },
    end: { type: 'integer' },
    confidence: { type: 'number' },
    evidence: { type: 'string' },
  },
};

export const EXTRACT_RESPONSE_SCHEMA = {
  type: 'object',
  properties: Object.fromEntries(
    Object.keys(FIELD_KEY_MAP).map((key) => [key, PROSE_KEYS.includes(key) ? PROSE_FIELD_SCHEMA : TEXT_FIELD_SCHEMA]),
  ),
};

export const CRITIC_RESPONSE_SCHEMA = {
  type: 'object',
  properties: Object.fromEntries(
    Object.keys(FIELD_KEY_MAP).map((key) => [
      key,
      {
        type: 'object',
        properties: {
          refuted: { type: 'boolean' },
          reason: { type: 'string' },
          evidenceSpan: { type: 'string' },
        },
      },
    ]),
  ),
};

// ---- Vocabulary shortlist rendering ----
//
// "The vocabulary block is rendered in a different order per agent so
// ordering bias doesn't correlate" (PLAN.md §2). Deterministic, not random --
// a worker re-run must build the identical prompt for an identical
// input_sha (PLAN.md §2's idempotency lookup depends on that).
function renderVocabBlock(vocabShortlist, agent) {
  const names = (vocabShortlist ?? []).map((v) => (typeof v === 'string' ? v : v.name));
  if (names.length === 0) return '(no vocabulary shortlist provided)';
  const ordered = agent === 'extract_b' || agent === 'reconciler' ? [...names].reverse() : names;
  return ordered.join(', ');
}

function fieldChecklist() {
  return Object.keys(FIELD_KEY_MAP)
    .map((key) =>
      PROSE_KEYS.includes(key)
        ? `- ${key}: character offsets {start, end} into RAW_TEXT for the span covering this, or omit if absent`
        : `- ${key}: the value as written, verbatim where possible, or omit if absent`,
    )
    .join('\n');
}

function basePromptBody({ rawText, vocabShortlist, agent }) {
  return [
    `RAW_TEXT (0-indexed characters, use exact offsets for any span field):`,
    JSON.stringify(rawText ?? ''),
    ``,
    `Known vocabulary (roasters, origin countries, farms) -- prefer these exact names when the bag/caption matches one:`,
    renderVocabBlock(vocabShortlist, agent),
    ``,
    `Extract one candidate per field below. Respond only with the JSON object described by the schema.`,
    fieldChecklist(),
  ].join('\n');
}

// ---- Prompt builders (pure) ----

export function buildExtractPrompt(agent, ctx) {
  const body = basePromptBody({ ...ctx, agent });
  if (agent === 'extract_a') {
    return {
      system:
        'You are a careful data-entry assistant. The caption/description text is authoritative; use the bag image only to fill gaps the text leaves open. Never invent a value not supported by the text or image.',
      prompt: body,
    };
  }
  if (agent === 'extract_b') {
    return {
      system:
        'You are auditing a coffee-bag photo field by field, as an independent checklist pass -- do not assume any field depends on another. For each field, look for its own direct evidence before deciding it is absent.',
      prompt: body,
    };
  }
  throw new Error(`buildExtractPrompt: unknown agent "${agent}"`);
}

export function buildCriticPrompt({ rawText, vocabShortlist, candidatesByField }) {
  const summary = Object.entries(candidatesByField ?? {})
    .map(([field, candidates]) => `- ${field}: ${candidates.map((c) => `${c.agent}="${c.value}"`).join(' | ')}`)
    .join('\n');
  return {
    system:
      'You are a skeptical reviewer. You will be shown candidate values other extractors proposed for a coffee-bag photo. For each field, try to REFUTE it: does the raw text or image actually contradict it? Cite the exact contradicting span. Never propose a replacement value -- only verdicts.',
    prompt: [basePromptBody({ rawText, vocabShortlist, agent: 'critic' }), ``, `Candidates to review:`, summary].join(
      '\n',
    ),
  };
}

export function buildReconcilerPrompt({ rawText, vocabShortlist, candidatesByField }) {
  const summary = Object.entries(candidatesByField ?? {})
    .map(([field, candidates]) => `- ${field}: ${candidates.map((c) => `${c.agent}="${c.value}" (conf ${c.confidence})`).join(' | ')}`)
    .join('\n');
  return {
    system:
      'Read the bag label first, then reconcile against the caption. Where voters disagree, report the disagreement honestly via a lower confidence rather than picking arbitrarily.',
    prompt: [
      basePromptBody({ rawText, vocabShortlist, agent: 'reconciler' }),
      ``,
      `Every other voter's candidates, for reconciliation:`,
      summary,
    ].join('\n'),
  };
}

// ---- Response parsing (pure) ----

export function parseExtractResponse(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return {};
  }
  const fields = {};
  for (const [wireKey, field] of Object.entries(FIELD_KEY_MAP)) {
    const entry = data?.[wireKey];
    if (entry == null) continue;
    if (PROSE_KEYS.includes(wireKey)) {
      if (typeof entry.start !== 'number' || typeof entry.end !== 'number') continue;
      fields[field] = { value: { start: entry.start, end: entry.end }, confidence: entry.confidence ?? 0.8, evidence: entry.evidence };
    } else {
      if (entry.value == null || entry.value === '') continue;
      fields[field] = { value: entry.value, confidence: entry.confidence ?? 0.8, evidence: entry.evidence };
    }
  }
  return fields;
}

export function parseCriticResponse(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return {};
  }
  const verdicts = {};
  for (const [wireKey, field] of Object.entries(FIELD_KEY_MAP)) {
    const entry = data?.[wireKey];
    if (entry == null) continue;
    verdicts[field] = { refuted: Boolean(entry.refuted), reason: entry.reason, evidenceSpan: entry.evidenceSpan };
  }
  return verdicts;
}

// ---- Cost estimation ----
//
// PLAN.md §2's cost table, "my recollection -- confirm against the Vertex
// price sheet before the run." Output tokens include thinking tokens, which
// dominate cost on the pro model.
const MODEL_RATES = {
  'gemini-2.5-pro': { inputPerMTok: 1.25, outputPerMTok: 10 },
  'gemini-2.5-flash': { inputPerMTok: 0.3, outputPerMTok: 2.5 },
};

export function estimateCostUsd(model, usage) {
  const rates = MODEL_RATES[model];
  if (!rates || !usage) return 0;
  const inputTok = usage.promptTokenCount ?? 0;
  const outputTok = (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0);
  const cost = (inputTok / 1_000_000) * rates.inputPerMTok + (outputTok / 1_000_000) * rates.outputPerMTok;
  return Math.round(cost * 10_000) / 10_000;
}

// ---- Network-touching voters ----

export async function runExtractA({ rawText, images, vocabShortlist } = {}) {
  const model = 'gemini-2.5-pro';
  const { system, prompt } = buildExtractPrompt('extract_a', { rawText, vocabShortlist });
  const { text, usage } = await generateContent({
    model,
    system,
    prompt,
    images,
    temperature: 0,
    responseSchema: EXTRACT_RESPONSE_SCHEMA,
  });
  return {
    agent: 'extract_a',
    provider: 'vertex',
    model,
    promptVersion: PROMPT_VERSION,
    fields: parseExtractResponse(text),
    usage,
    costUsd: estimateCostUsd(model, usage),
  };
}

export async function runExtractB({ rawText, images, vocabShortlist } = {}) {
  const model = 'gemini-2.5-flash';
  const { system, prompt } = buildExtractPrompt('extract_b', { rawText, vocabShortlist });
  const { text, usage } = await generateContent({
    model,
    system,
    prompt,
    images,
    temperature: 0.4,
    thinkingBudget: 0,
    responseSchema: EXTRACT_RESPONSE_SCHEMA,
  });
  return {
    agent: 'extract_b',
    provider: 'vertex',
    model,
    promptVersion: PROMPT_VERSION,
    fields: parseExtractResponse(text),
    usage,
    costUsd: estimateCostUsd(model, usage),
  };
}

// Critic never emits values -- callers use `verdicts` to discount other
// voters' confidence for a field (see `adjudicate.js`'s `criticVerdicts` ctx),
// not as a `field_candidates` row of its own.
export async function runCritic({ rawText, images, vocabShortlist, candidatesByField } = {}) {
  const model = 'gemini-2.5-flash';
  const { system, prompt } = buildCriticPrompt({ rawText, vocabShortlist, candidatesByField });
  const { text, usage } = await generateContent({
    model,
    system,
    prompt,
    images,
    temperature: 0,
    thinkingBudget: 0,
    responseSchema: CRITIC_RESPONSE_SCHEMA,
  });
  return {
    agent: 'critic',
    provider: 'vertex',
    model,
    promptVersion: PROMPT_VERSION,
    verdicts: parseCriticResponse(text),
    usage,
    costUsd: estimateCostUsd(model, usage),
  };
}

export async function runReconciler({ rawText, images, vocabShortlist, candidatesByField } = {}) {
  const model = 'gemini-2.5-pro';
  const { system, prompt } = buildReconcilerPrompt({ rawText, vocabShortlist, candidatesByField });
  const { text, usage } = await generateContent({
    model,
    system,
    prompt,
    images,
    temperature: 0,
    responseSchema: EXTRACT_RESPONSE_SCHEMA,
  });
  return {
    agent: 'reconciler',
    provider: 'vertex',
    model,
    promptVersion: PROMPT_VERSION,
    fields: parseExtractResponse(text),
    usage,
    costUsd: estimateCostUsd(model, usage),
  };
}

// P3 (rules) is the data lane's `src/lib/deterministic.js` (#25) -- pure JS,
// no network, and per PLAN.md §2 "better than any LLM" on numbers/units/
// vocab. It doesn't exist yet, so this resolves to `null` and the worker
// simply runs without it until the data lane adds it; no coordination is
// needed in either direction when that file lands.
let _rulesVoterPromise;
export async function loadRulesVoter() {
  if (_rulesVoterPromise) return _rulesVoterPromise;
  _rulesVoterPromise = import('./deterministic.js')
    .then((mod) => mod.rulesVoter ?? null)
    .catch(() => null);
  return _rulesVoterPromise;
}
