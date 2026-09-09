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

const { baseUrl, token, writeToken } = await getSettings();
$('baseUrl').value = baseUrl || DEFAULT_BASE_URL;
$('token').value = token;
$('writeToken').value = writeToken;

$('save').addEventListener('click', async () => {
  await chrome.storage.local.set({
    baseUrl: $('baseUrl').value.trim().replace(/\/+$/, '') || DEFAULT_BASE_URL,
    token: $('token').value.trim(),
    writeToken: $('writeToken').value.trim(),
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

// ---- update status ----
//
// Shown so "is it actually updating?" is answerable without opening the
// service-worker console. `stalled` is the honest case: the extension can see
// a newer version on GitHub but reloading stopped changing anything, which
// means nothing is pulling the files.
function renderUpdate(state) {
  const el = $('update-status');
  const help = $('update-help');
  help.hidden = true;

  if (!state) {
    el.textContent = 'No check has run yet.';
    return;
  }
  if (state.error) {
    el.textContent = `Could not check for updates (${state.error}). Running ${state.current}.`;
    return;
  }
  if (state.upToDate) {
    el.textContent = `Up to date — version ${state.current}.`;
    return;
  }
  if (state.stalled) {
    el.textContent = `Version ${state.latest} is available but reloading is not picking it up — you are still on ${state.current}.`;
    help.hidden = false;
    return;
  }
  el.textContent = `Updating to ${state.latest} (running ${state.current})…`;
  help.hidden = false;
}

const { updateState } = await chrome.storage.local.get('updateState');
renderUpdate(updateState);

$('check-update').addEventListener('click', async () => {
  $('update-status').textContent = 'Checking…';
  // autoReload stays off here: a reload would close this page mid-click.
  const state = await chrome.runtime.sendMessage({ type: 'checkUpdate', autoReload: false });
  renderUpdate(state);
});
