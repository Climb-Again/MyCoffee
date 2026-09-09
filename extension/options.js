import { DEFAULT_BASE_URL, getSettings } from './settings.js';

const $ = (id) => document.getElementById(id);
const flash = (msg, ok = true) => {
  const el = $('saved');
  el.textContent = msg;
  el.style.color = ok ? 'var(--good)' : 'var(--warn)';
  setTimeout(() => {
    if (el.textContent === msg) el.textContent = '';
  }, 4000);
};

const { baseUrl, token } = await getSettings();
$('baseUrl').value = baseUrl || DEFAULT_BASE_URL;
$('token').value = token;

$('save').addEventListener('click', async () => {
  await chrome.storage.local.set({
    baseUrl: $('baseUrl').value.trim().replace(/\/+$/, '') || DEFAULT_BASE_URL,
    token: $('token').value.trim(),
  });
  flash('Saved');
});

// Hits /health rather than /api/score: it needs no token and no page text, so
// a green here isolates "can I reach the backend" from "is my token right".
$('test').addEventListener('click', async () => {
  const url = ($('baseUrl').value.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
  const tok = $('token').value.trim();
  try {
    const health = await fetch(`${url}/health`);
    if (!health.ok) return flash(`Backend unreachable (HTTP ${health.status})`, false);

    if (!tok) return flash('Backend reachable — now add a token', false);
    // /api/status accepts either token, so it verifies the credential without
    // needing a product page to score.
    const status = await fetch(`${url}/api/status`, { headers: { authorization: `Bearer ${tok}` } });
    if (status.status === 401) return flash('Backend reachable, token rejected', false);
    if (!status.ok) return flash(`Token check failed (HTTP ${status.status})`, false);
    flash('Backend and token both good');
  } catch (e) {
    flash(`Could not reach ${url}`, false);
  }
});
