// Vertex AI (Gemini) client. App-agnostic — copied faithfully from the MyHealthOS
// pattern. Builds credentials in code from the GOOGLE_* env vars; it does NOT rely
// on GOOGLE_APPLICATION_CREDENTIALS.
import { GoogleAuth } from 'google-auth-library';
import { config } from './config.js';

// GOOGLE_PRIVATE_KEY is tolerant of several shapes:
//   1. Full service-account JSON pasted in (detected by a leading "{").
//   2. Raw PEM ("-----BEGIN PRIVATE KEY----- ...").
//   3. base64-encoded PEM.
//   4. Escaped-newline form ("\\n" instead of real newlines).
function normalizePrivateKey(raw) {
  if (!raw) return '';
  let key = raw.trim();

  // Escaped newlines -> real newlines.
  if (key.includes('\\n')) key = key.replace(/\\n/g, '\n');

  // base64 (no PEM header, no braces) -> decode.
  if (!key.includes('BEGIN') && !key.startsWith('{')) {
    try {
      const decoded = Buffer.from(key, 'base64').toString('utf8');
      if (decoded.includes('BEGIN')) key = decoded;
    } catch {
      // leave as-is
    }
  }
  return key;
}

// Returns { credentials, projectId } suitable for GoogleAuth.
export function loadCredentials() {
  const { projectId, serviceAccountEmail, privateKey, privateKeyId, clientId } =
    config.vertex;

  const rawKey = (privateKey || '').trim();

  // Case 1: the whole service-account JSON was pasted into GOOGLE_PRIVATE_KEY.
  if (rawKey.startsWith('{')) {
    let parsed;
    try {
      parsed = JSON.parse(rawKey);
    } catch (err) {
      throw new Error(`GOOGLE_PRIVATE_KEY looks like JSON but failed to parse: ${err.message}`);
    }
    return {
      projectId: parsed.project_id || projectId,
      credentials: {
        client_email: parsed.client_email || serviceAccountEmail,
        private_key: normalizePrivateKey(parsed.private_key),
        private_key_id: parsed.private_key_id || privateKeyId,
        client_id: parsed.client_id || clientId,
      },
    };
  }

  // Case 2: individual GOOGLE_* fields.
  return {
    projectId,
    credentials: {
      client_email: serviceAccountEmail,
      private_key: normalizePrivateKey(rawKey),
      private_key_id: privateKeyId,
      client_id: clientId,
    },
  };
}

let _authClient = null;
async function getAuthClient() {
  if (_authClient) return _authClient;
  const { credentials } = loadCredentials();
  const auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  _authClient = await auth.getClient();
  return _authClient;
}

export function isConfigured() {
  const { projectId, serviceAccountEmail, privateKey } = config.vertex;
  if (!privateKey) return false;
  // Full SA JSON carries its own project_id/client_email, so the individual
  // vars aren't required in that shape (see loadCredentials() case 1).
  if (privateKey.trim().startsWith('{')) {
    try {
      const parsed = JSON.parse(privateKey.trim());
      return Boolean(
        (parsed.project_id || projectId) &&
          (parsed.client_email || serviceAccountEmail) &&
          parsed.private_key,
      );
    } catch {
      return false;
    }
  }
  return Boolean(projectId && serviceAccountEmail && privateKey);
}

/**
 * Build the Vertex `generateContent` request body. Pure — no network, no auth —
 * so request shaping is unit-testable on its own.
 *
 * @param {object} opts
 * @param {string} opts.prompt   - user prompt text
 * @param {string} [opts.system] - optional system instruction
 * @param {Array<{mimeType: string, dataBase64: string}>} [opts.images] - inline images,
 *   appended as `inlineData` parts after the text part
 * @param {number} [opts.maxOutputTokens] - default 8192. Gemini 2.5 is a *thinking*
 *   model; too-low a cap yields empty output, so keep this >= 8192.
 * @param {number} [opts.temperature] - default 0.7
 * @param {boolean} [opts.json] - request application/json responses
 * @param {object} [opts.responseSchema] - JSON Schema for schema-constrained output.
 *   Implies `responseMimeType: 'application/json'`. Vertex rejects `minimum`/
 *   `maximum`/`minLength`/recursive schemas — range validation stays in
 *   `src/lib/normalize.js`; enums are enforceable and should be used.
 * @param {number} [opts.thinkingBudget] - 0 disables thinking (a cost lever for
 *   the flash extractor); omit to use the model default.
 * @param {Object<string,string>} [opts.labels] - billing labels propagated to
 *   the Vertex billing export (e.g. `{ app: 'mycoffee', agent: 'extract_a' }`).
 *   Omitted from the body when empty. Keys/values must be lowercase
 *   letters/digits/`-`/`_`.
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
  labels,
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
    ...(labels && Object.keys(labels).length ? { labels } : {}),
  };
  if (system) {
    body.systemInstruction = { parts: [{ text: system }] };
  }
  return body;
}

/**
 * Parse a Vertex `generateContent` response into the shape callers need.
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

/**
 * Generate content with a Vertex Gemini model. See `buildRequestBody` for the
 * request options this accepts.
 *
 * @returns {Promise<{ text: string, usage: object, finishReason: string|undefined, raw: object }>}
 */
export async function generateContent(opts = {}) {
  const { projectId } = loadCredentials();
  const region = config.vertex.region || 'us-central1';
  // Honour the caller's model. This used to always use config.vertex.model, so
  // every extraction voter ran on 2.5-pro even though agents.js labels
  // extract_b/critic as 2.5-flash — and because only *flash* can disable
  // thinking, their `thinkingBudget: 0` made Vertex reject the request with
  // "The model does not support setting thinking_budget to 0", failing every
  // photo. The per-voter model was being recorded for bookkeeping but never
  // actually requested.
  const model = opts.model || config.vertex.model || 'gemini-2.5-flash';

  // Billing labels: always stamp `app` (from config) so every call is
  // attributable in the Vertex billing export, and merge any per-voter labels
  // the caller passed (e.g. `agent: 'extract_a'`) so cost can be broken down by
  // voter too. Caller-supplied keys win on collision.
  const labels = { app: config.vertex.labelApp, ...(opts.labels || {}) };

  // Belt and braces: a 2.5-pro model cannot disable thinking at all, so a
  // budget of 0 is a hard 400 rather than a hint. Drop it instead of failing,
  // so a VERTEX_MODEL override can't resurrect that exact outage.
  const base = { ...opts, labels };
  const effectiveOpts =
    base.thinkingBudget === 0 && /pro/i.test(model) ? { ...base, thinkingBudget: undefined } : base;

  const url =
    `https://${region}-aiplatform.googleapis.com/v1/projects/${projectId}` +
    `/locations/${region}/publishers/google/models/${model}:generateContent`;

  const body = buildRequestBody(effectiveOpts);

  const client = await getAuthClient();
  // `timeout` is mandatory here, not defensive: gaxios' default is 0 (wait
  // forever). Without it a stalled Vertex call hangs the extraction worker
  // indefinitely while it holds the advisory lock — every later job then gets
  // refused the lock and sits at status='running' with no error to look at.
  const res = await client.request({
    url,
    method: 'POST',
    data: body,
    timeout: opts.timeoutMs ?? config.vertex.timeoutMs,
  });

  return parseResponse(res.data);
}
