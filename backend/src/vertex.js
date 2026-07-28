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
  return Boolean(projectId && serviceAccountEmail && privateKey);
}

/**
 * Generate content with a Vertex Gemini model.
 *
 * @param {object} opts
 * @param {string} opts.prompt   - user prompt text
 * @param {string} [opts.system] - optional system instruction
 * @param {number} [opts.maxOutputTokens] - default 8192. Gemini 2.5 is a *thinking*
 *   model; too-low a cap yields empty output, so keep this >= 8192.
 * @param {number} [opts.temperature] - default 0.7
 * @param {boolean} [opts.json] - request application/json responses
 * @returns {Promise<{ text: string, raw: object }>}
 */
export async function generateContent({
  prompt,
  system,
  maxOutputTokens = 8192,
  temperature = 0.7,
  json = false,
} = {}) {
  const { projectId } = loadCredentials();
  const region = config.vertex.region || 'us-central1';
  const model = config.vertex.model || 'gemini-2.5-pro';

  const url =
    `https://${region}-aiplatform.googleapis.com/v1/projects/${projectId}` +
    `/locations/${region}/publishers/google/models/${model}:generateContent`;

  const body = {
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: {
      maxOutputTokens,
      temperature,
      ...(json ? { responseMimeType: 'application/json' } : {}),
    },
  };
  if (system) {
    body.systemInstruction = { parts: [{ text: system }] };
  }

  const client = await getAuthClient();
  const res = await client.request({ url, method: 'POST', data: body });
  const data = res.data;

  const text =
    data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';

  return { text, raw: data };
}
