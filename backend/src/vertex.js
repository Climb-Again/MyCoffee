// Gemini Developer API client (Google AI Studio, `generativelanguage.googleapis.com`).
//
// History: this module used to target **Vertex AI** and authenticated with a
// service account (GOOGLE_* env vars → minted OAuth token via
// google-auth-library). On 2026-08-16 it was migrated to the **Gemini Developer
// API** — a single `GEMINI_API_KEY`, no project/region/SA — to escape the GCP
// project spend cap that had started refusing every Vertex call ("Spend cap
// breached for project …"). The free tier has no GCP billing at all. The file
// keeps its `vertex.js` name and the `config.vertex.*` shape so nothing else in
// the app has to change. The request/response JSON is the same generateContent
// schema Vertex used, so `buildRequestBody`/`parseResponse` are unchanged.
import { config } from './config.js';

export function isConfigured() {
  return Boolean(config.vertex.apiKey);
}

/**
 * Build the Gemini `generateContent` request body. Pure — no network, no auth —
 * so request shaping is unit-testable on its own.
 *
 * @param {object} opts
 * @param {string} opts.prompt   - user prompt text
 * @param {string} [opts.system] - optional system instruction
 * @param {Array<{mimeType: string, dataBase64: string}>} [opts.images] - inline images,
 *   appended as `inlineData` parts after the text part
 * @param {number} [opts.maxOutputTokens] - default 8192. Gemini 2.5+ is a *thinking*
 *   model; too-low a cap yields empty output, so keep this >= 8192.
 * @param {number} [opts.temperature] - default 0.7
 * @param {boolean} [opts.json] - request application/json responses
 * @param {object} [opts.responseSchema] - JSON Schema for schema-constrained output.
 *   Implies `responseMimeType: 'application/json'`. Rejects `minimum`/`maximum`/
 *   `minLength`/recursive schemas — range validation stays in
 *   `src/lib/normalize.js`; enums are enforceable and should be used.
 * @param {number} [opts.thinkingBudget] - 0 disables thinking (the cost/reliability
 *   lever for structured JSON extraction on flash); omit to use the model default.
 * @returns {object}
 */
export function buildRequestBody({
  prompt,
  system,
  images = [],
  maxOutputTokens = 8192,
  temperature = 0.7,
  json = false,
  responseSchema,
  thinkingBudget,
} = {}) {
  const parts = [
    { text: prompt },
    ...images.map(({ mimeType, dataBase64 }) => ({
      inlineData: { mimeType, data: dataBase64 },
    })),
  ];

  const body = {
    contents: [{ role: 'user', parts }],
    generationConfig: {
      maxOutputTokens,
      temperature,
      ...(json || responseSchema ? { responseMimeType: 'application/json' } : {}),
      ...(responseSchema ? { responseSchema } : {}),
      ...(thinkingBudget !== undefined ? { thinkingConfig: { thinkingBudget } } : {}),
    },
  };
  if (system) {
    body.systemInstruction = { parts: [{ text: system }] };
  }
  return body;
}

/**
 * Parse a `generateContent` response into the shape callers need.
 * Pure — no network — so response parsing is unit-testable on its own.
 *
 * @param {object} data - the raw response body
 * @returns {{ text: string, usage: object, finishReason: string|undefined, raw: object }}
 */
export function parseResponse(data) {
  const text =
    data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
  const finishReason = data?.candidates?.[0]?.finishReason;
  const { promptTokenCount, candidatesTokenCount, thoughtsTokenCount } =
    data?.usageMetadata || {};

  return {
    text,
    usage: { promptTokenCount, candidatesTokenCount, thoughtsTokenCount },
    finishReason,
    raw: data,
  };
}

const RETRYABLE_STATUS = new Set([429, 500, 503]);
const MAX_ATTEMPTS = 5;

function backoffMs(attempt, retryAfterHeader) {
  // Honour a server-sent Retry-After (seconds) when present, else exponential.
  const retryAfter = Number.parseInt(retryAfterHeader ?? '', 10);
  if (Number.isFinite(retryAfter) && retryAfter > 0) return Math.min(retryAfter * 1000, 32_000);
  return Math.min(1500 * 2 ** attempt, 32_000);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Generate content with a Gemini model via the Developer API. See
 * `buildRequestBody` for the request options this accepts.
 *
 * Free-tier reality (AI Studio): flash allows ~10 RPM, and the extraction worker
 * fires several voter calls per photo, so bursts trip `429 RESOURCE_EXHAUSTED`.
 * We retry 429/500/503 with exponential backoff (honouring Retry-After) so a
 * rate-limit degrades into a short wait rather than a failed photo.
 *
 * @returns {Promise<{ text: string, usage: object, finishReason: string|undefined, raw: object }>}
 */
export async function generateContent(opts = {}) {
  const apiKey = config.vertex.apiKey;
  if (!apiKey) throw new Error('GEMINI_API_KEY not set — Gemini Developer API is unconfigured');

  const model = opts.model || config.vertex.model || 'gemini-flash-latest';
  const body = buildRequestBody(opts);
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const timeoutMs = opts.timeoutMs ?? config.vertex.timeoutMs;

  let lastErr;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          // Header form (not `?key=`) so the key never lands in a logged URL.
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (res.ok) {
        return parseResponse(await res.json());
      }

      const errText = await res.text().catch(() => '');
      if (RETRYABLE_STATUS.has(res.status) && attempt < MAX_ATTEMPTS - 1) {
        lastErr = new Error(`Gemini ${res.status}: ${errText.slice(0, 300)}`);
        await sleep(backoffMs(attempt, res.headers.get('retry-after')));
        continue;
      }
      throw new Error(`Gemini ${res.status}: ${errText.slice(0, 500)}`);
    } catch (err) {
      // Network/abort errors are retryable too; a rethrown HTTP error above is
      // not (it already exhausted retries or was non-retryable) — surface it.
      if (err?.message?.startsWith('Gemini ') || attempt === MAX_ATTEMPTS - 1) throw err;
      lastErr = err;
      await sleep(backoffMs(attempt));
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastErr ?? new Error('Gemini request failed');
}
