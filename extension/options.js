import { DEFAULT_BASE_URL, getSettings } from './settings.js';
import {
  entryKey,
  fetchFeed,
  liveEntries,
  loadSeen,
  markAllSeen,
  planByLane,
  saveSeen,
  unseenLiveCount,
} from './whatsnew.js';

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

// ---- What's New (#200) ----
//
// Fetch once on load (fetchFeed's own 10-minute cache means reopening the page
// costs no network); render two tabs; check-toggling writes seen state
// immediately so the badge painter (which listens on storage.onChanged) can
// clear the count without any message plumbing.

let whatsnewState = { feed: { live: [], plan: { byLane: {} } }, seen: new Set(), tab: 'live' };

function escape(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function renderWhatsNewCount() {
  const el = $('whatsnew-count');
  const n = unseenLiveCount(whatsnewState.feed, whatsnewState.seen);
  if (n > 0) {
    el.textContent = `· ${n} new`;
    el.hidden = false;
  } else {
    el.hidden = true;
  }
}

function renderWhatsNewBody() {
  const body = $('whatsnew-body');
  const { feed, seen, tab } = whatsnewState;
  body.innerHTML = '';

  if (tab === 'live') {
    const entries = liveEntries(feed);
    if (!entries.length) {
      body.innerHTML = '<p class="whatsnew-empty">Nothing shipped yet.</p>';
      return;
    }
    for (const entry of entries) {
      const key = entryKey(entry);
      const row = document.createElement('label');
      row.className = 'whatsnew-row';
      row.innerHTML = `
        <input type="checkbox" class="whatsnew-check" data-key="${escape(key)}" ${seen.has(key) ? 'checked' : ''} />
        <div class="whatsnew-body">
          <div class="whatsnew-title">${escape(entry.title)}</div>
          ${entry.detail ? `<p class="whatsnew-detail">${escape(entry.detail)}</p>` : ''}
          ${entry.area ? `<span class="whatsnew-area">${escape(entry.area)}</span>` : ''}
        </div>`;
      body.appendChild(row);
    }
    return;
  }

  const lanes = planByLane(feed);
  if (!lanes.length) {
    body.innerHTML = '<p class="whatsnew-empty">Nothing queued.</p>';
    return;
  }
  for (const { lane, entries } of lanes) {
    const header = document.createElement('div');
    header.className = 'whatsnew-lane-header';
    header.textContent = `${lane} · ${entries.length}`;
    body.appendChild(header);
    for (const entry of entries) {
      const key = entryKey(entry);
      const row = document.createElement('label');
      row.className = 'whatsnew-row';
      row.innerHTML = `
        <input type="checkbox" class="whatsnew-check" data-key="${escape(key)}" ${seen.has(key) ? 'checked' : ''} />
        <div class="whatsnew-body">
          <div class="whatsnew-title">${escape(entry.title)}</div>
          ${entry.detail ? `<p class="whatsnew-detail">${escape(entry.detail)}</p>` : ''}
        </div>`;
      body.appendChild(row);
    }
  }
}

document.querySelectorAll('.whatsnew-tab').forEach((btn) => {
  btn.addEventListener('click', () => {
    whatsnewState.tab = btn.dataset.tab;
    for (const tab of document.querySelectorAll('.whatsnew-tab')) {
      tab.setAttribute('aria-selected', tab === btn ? 'true' : 'false');
    }
    renderWhatsNewBody();
  });
});

$('whatsnew-body').addEventListener('change', async (e) => {
  const cb = e.target;
  if (!cb.matches('.whatsnew-check')) return;
  const key = cb.dataset.key;
  if (cb.checked) whatsnewState.seen.add(key);
  else whatsnewState.seen.delete(key);
  await saveSeen(whatsnewState.seen);
  renderWhatsNewCount();
});

$('whatsnew-mark').addEventListener('click', async () => {
  whatsnewState.seen = new Set(markAllSeen(whatsnewState.feed, [...whatsnewState.seen]));
  await saveSeen(whatsnewState.seen);
  renderWhatsNewCount();
  renderWhatsNewBody();
});

(async () => {
  try {
    const [feed, seen] = await Promise.all([
      fetchFeed(($('baseUrl').value || DEFAULT_BASE_URL).replace(/\/+$/, ''), $('token').value),
      loadSeen(),
    ]);
    whatsnewState = { feed, seen, tab: whatsnewState.tab };
    renderWhatsNewCount();
    renderWhatsNewBody();
  } catch (e) {
    $('whatsnew-body').innerHTML = `<p class="whatsnew-empty">Could not load What's New (${escape(e?.message || e)}).</p>`;
  }
})();
