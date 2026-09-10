// Popup UI (#162).
//
// Wording is fixed by #106 and must stay identical to the iOS screen (#125):
// this is FIT WITH WHAT YOU BUY, never a predicted rating. The endpoint's own
// validation is r≈0.39 against real ratings, so calling it a prediction would
// be a claim the data does not support. Components carry equal visual weight
// with the headline, and a `low` confidence result shows no headline number at
// all — the server already returns `score: null` in that case, and this file
// never invents one.

import { getSettings } from './settings.js';
import { loadHistory, rank, RETENTION_DAYS, TOP_N, roastColor, roastLabel, relativeTime } from './history.js';

const $ = (id) => document.getElementById(id);

const show = (which) => {
  for (const id of ['loading', 'error', 'result']) $(id).classList.toggle('hidden', id !== which);
};

const ERRORS = {
  no_token: {
    title: 'Add your API token',
    body: 'The extension needs your MyCoffee read token before it can score anything. It is stored only in this browser.',
    settings: true,
  },
  bad_token: {
    title: 'Token rejected',
    body: 'The backend refused that token. Check it in settings — the read token (APP_TOKEN) is the one you want.',
    settings: true,
  },
  unsupported_page: {
    title: 'Not a web page',
    body: 'Open a coffee shop product page and try again.',
  },
  cannot_read_page: {
    title: "Chrome won't let the extension read this page",
    body: 'Browser-internal pages, the Web Store and PDFs are off limits. Try a normal shop page.',
  },
  not_enough_text: {
    title: 'Not enough on this page',
    body: 'This looks like a listing or a nav shell rather than a product page. Open the individual coffee.',
  },
  no_tab: { title: 'No active tab', body: 'Nothing to read here.' },
  network: {
    title: "Couldn't reach the backend",
    body: 'Check your connection and the backend URL in settings.',
    settings: true,
  },
  server: { title: 'The backend returned an error', body: '' },
  unexpected: { title: 'Something went wrong', body: '' },
};

function renderError(res) {
  const spec = ERRORS[res.error] ?? ERRORS.unexpected;
  $('err-title').textContent = spec.title;
  $('err-body').textContent = [spec.body, res.detail].filter(Boolean).join(' ');
  $('err-settings').hidden = !spec.settings;
  show('error');
}

function bar(name, value, note) {
  const row = document.createElement('div');
  row.className = 'bar-row';

  const label = document.createElement('span');
  label.className = 'bar-name';
  label.textContent = name;

  const track = document.createElement('div');
  track.className = 'bar-track';
  const fill = document.createElement('div');
  fill.className = 'bar-fill';
  fill.style.width = `${Math.max(0, Math.min(100, value ?? 0))}%`;
  track.appendChild(fill);

  const val = document.createElement('span');
  val.className = value == null ? 'bar-val none' : 'bar-val';
  val.textContent = value == null ? (note ?? '—') : String(value);

  row.append(label, track, val);
  return row;
}

function chip(text, isNew = false) {
  const el = document.createElement('span');
  el.className = isNew ? 'chip new' : 'chip';
  el.textContent = text;
  return el;
}

// #161 -- the "you already own this one" card and its enrich diff.
//
// Two rules, both from Radu's brief:
//   * If he owns it, that leads. A fit score for a bag already in the library
//     answers the wrong question, so the card sits above the headline.
//   * If the page adds nothing, say nothing. An enrich panel that is always
//     present but always empty is worse than no panel, so the whole block
//     stays hidden unless there is something real to offer.
function renderOwned(match, enrich, hasWriteToken) {
  const card = $('owned');
  if (!match) {
    card.classList.add('hidden');
    return;
  }

  const possible = match.confidence === 'possible';
  $('owned-tag').textContent = possible ? 'Possibly one of yours' : 'You have this one';
  $('owned-tag').classList.toggle('maybe', possible);

  const meta = [];
  if (match.purchasedOn) {
    const d = new Date(`${match.purchasedOn}T00:00:00Z`);
    meta.push(
      Number.isNaN(d.getTime())
        ? match.purchasedOn
        : d.toLocaleDateString(undefined, { month: 'short', year: 'numeric', timeZone: 'UTC' }),
    );
  }
  if (match.rating != null) meta.push(`${match.rating.toFixed(1)}★`);
  if (match.isFavorite) meta.push('favourite');
  $('owned-meta').textContent = meta.join(' · ');

  $('owned-title').textContent = match.rawTitle || '(untitled)';

  // Always say WHY it matched. A match the user can't sanity-check is a match
  // they can't correct, and this one can be wrong.
  const why = [];
  if (match.matchedOn?.length) why.push(`matched on ${match.matchedOn.join(', ')}`);
  if (match.originAgrees === false) why.push('but the page lists a different origin');
  if (match.alternatives?.length) why.push(`${match.alternatives.length} other close match(es)`);
  $('owned-why').textContent = why.join(' — ');

  const box = $('enrich');
  const rows = $('enrich-rows');
  rows.replaceChildren();

  if (!enrich?.length) {
    box.classList.add('hidden');
    return;
  }

  $('enrich-head').textContent = `This page adds ${enrich.length} thing${enrich.length === 1 ? '' : 's'}`;

  for (const item of enrich) {
    const row = document.createElement('div');
    row.className = 'enrich-row';

    const label = document.createElement('span');
    label.className = 'enrich-label';
    label.textContent = item.label;

    const value = document.createElement('span');
    value.className = 'enrich-value';
    value.textContent = item.display;
    value.title = item.display;

    const btn = document.createElement('button');
    btn.className = 'enrich-btn';
    btn.textContent = 'Add';
    btn.disabled = !hasWriteToken;
    btn.title = hasWriteToken ? `Add ${item.label} to this coffee` : 'Add a write token in settings first';

    btn.addEventListener('click', async () => {
      btn.disabled = true;
      btn.textContent = '…';
      const res = await chrome.runtime.sendMessage({
        type: 'enrich',
        coffeeId: match.id,
        field: item.field,
        value: item.value,
      });
      if (res?.ok) {
        btn.textContent = 'Added';
        btn.classList.add('done');
      } else {
        btn.textContent = 'Failed';
        btn.classList.add('failed');
        btn.disabled = false;
        btn.title = res?.detail || res?.error || 'unknown error';
      }
    });

    row.append(label, value, btn);
    rows.appendChild(row);
  }

  if (!hasWriteToken) {
    const note = document.createElement('div');
    note.className = 'enrich-note';
    note.textContent = 'Add your write token in settings to save these.';
    rows.appendChild(note);
  }

  box.classList.remove('hidden');
}

function render(data, hasWriteToken) {
  const { score, confidence, components, fields, missing, explanation, cached, match, enrich } = data;

  renderOwned(match, enrich, hasWriteToken);

  // A suppressed headline is a deliberate outcome, not a failure: #106 says
  // show the components and say why, rather than invent a number.
  const scoreEl = $('score');
  scoreEl.textContent = score == null ? '—' : String(score);
  scoreEl.classList.toggle('suppressed', score == null);
  $('score-label').textContent = score == null ? 'no headline number' : 'fit with what you buy';
  $('confidence').classList.toggle('hidden', confidence !== 'low');
  $('explanation').textContent = explanation ?? '';

  // Ordered by weight (#189: affinity 50 · roast 20 · value 15 · novelty 10),
  // so the bars read in the same order the blend actually weighs them.
  //
  // NOTE: this block read `components.roastRecency` until 2026-09-10. #188
  // renamed that field to `components.roast` on the server and this was not
  // updated, so the Freshness bar silently vanished — the id cross-check I ran
  // only verified DOM ids, not response paths. Caught while adding Novelty.
  const bars = $('bars');
  bars.replaceChildren();
  bars.appendChild(bar('Affinity', components?.affinity?.score ?? null));
  bars.appendChild(
    components?.roast == null ? bar('Freshness', null, 'no date') : bar('Freshness', components.roast.score),
  );
  bars.appendChild(
    components?.value == null ? bar('Value', null, 'n/a') : bar('Value', components.value.score, null),
  );
  bars.appendChild(bar('Novelty', components?.novelty?.score ?? null));

  const chips = $('fields');
  chips.replaceChildren();
  if (fields?.roasterName) chips.appendChild(chip(fields.roasterName, components?.novelty?.isNewRoaster));
  if (fields?.originName) chips.appendChild(chip(fields.originName, components?.novelty?.isNewOrigin));
  if (fields?.profileId) chips.appendChild(chip(String(fields.profileId).replace(/_/g, ' ')));
  if (fields?.pricePer100gEur != null) chips.appendChild(chip(`€${fields.pricePer100gEur.toFixed(2)}/100g`));
  else if (fields?.priceAmount != null) {
    chips.appendChild(chip(`${fields.priceAmount}${fields.priceCurrency ? ` ${fields.priceCurrency}` : ''}`));
  }
  if (fields?.weightG) chips.appendChild(chip(`${fields.weightG} g`));
  // #188: the roast chip is colour-coded — green under two weeks, ramping to
  // red — and says outright when it cost points, since a -10 that is not
  // explained just looks like a wrong number.
  if (components?.roast) {
    const { daysSinceRoast: d, stale, penalty } = components.roast;
    const c = chip(roastLabel(d) ?? fields.roastedOn);
    const colour = roastColor(d);
    if (colour) {
      c.style.borderColor = colour;
      c.style.color = colour;
      c.style.fontWeight = '600';
    }
    if (stale) c.title = `Over ${d} days old — ${penalty} points off the score`;
    chips.appendChild(c);
  } else if (fields?.roastedOn) {
    chips.appendChild(chip(fields.roastedOn));
  }
  if (!chips.children.length) chips.appendChild(chip('nothing recognised on this page'));

  // Say what the page failed to provide rather than quietly scoring on less.
  // Value is 0.50 of the headline, so a missing price is worth naming.
  const gaps = [];
  if (missing?.price) gaps.push('no price');
  else if (missing?.currency) gaps.push('a price with no currency');
  if (missing?.weight) gaps.push('no weight');
  const missingEl = $('missing');
  if (gaps.length && components?.value == null) {
    missingEl.textContent = `This page had ${gaps.join(' and ')}, so the value half of the score is missing — and value carries the most weight of the three.`;
    missingEl.classList.remove('hidden');
  } else {
    missingEl.classList.add('hidden');
  }

  $('cached-note').textContent = cached ? 'cached result' : '';
  show('result');
}


// ---- #187: the top-10 list ----
//
// Radu: "always show last top 10 coffees ranked on score for 10 days ...
// Include a short summary using the coffee listing layout from the app but
// including of course the evaluator notes."
//
// The row deliberately mirrors `CoffeeRowView` from the app (the 2a redesign):
// image · UPPERCASE ROASTER / heavy one-line title / origin line · a
// right-aligned column of numbers. The FIT SCORE takes the rating's slot,
// because that is the number this surface knows — the app shows what he rated
// it, the extension shows how well it fits.
//
// Collapsed by default and per-row notes collapsed too: ten rows plus the
// current page's result does not fit a popup, which is the "if it's too many
// data expand / collapse" half of the ask.

const HISTORY_OPEN_KEY = 'historyOpen';

function historyRow(entry) {
  const row = document.createElement('div');
  row.className = 'hrow';

  // --- photo
  if (entry.imageUrl) {
    const img = document.createElement('img');
    img.className = 'hthumb';
    img.src = entry.imageUrl;
    img.alt = '';
    img.loading = 'lazy';
    // A shop CDN that 404s or blocks hotlinking must not leave a broken icon.
    img.addEventListener('error', () => {
      const ph = document.createElement('div');
      ph.className = 'hthumb-empty';
      img.replaceWith(ph);
    });
    row.appendChild(img);
  } else {
    const ph = document.createElement('div');
    ph.className = 'hthumb-empty';
    row.appendChild(ph);
  }

  // --- middle column
  const mid = document.createElement('div');
  mid.className = 'hmid';

  if (entry.roasterName) {
    const r = document.createElement('div');
    r.className = 'hroaster';
    r.textContent = entry.roasterName;
    mid.appendChild(r);
  }

  // The title IS the link — "save url so if i click any of these coffees i go
  // to that page".
  const link = document.createElement('a');
  link.className = 'htitle';
  link.href = entry.url;
  link.target = '_blank';
  link.rel = 'noreferrer noopener';
  link.textContent = entry.title || entry.url;
  link.title = entry.url;
  mid.appendChild(link);

  const bits = [entry.originName, entry.profileId ? String(entry.profileId).replace(/_/g, ' ') : null]
    .filter(Boolean)
    .join(' · ');
  if (bits) {
    const o = document.createElement('div');
    o.className = 'horigin';
    o.textContent = bits;
    mid.appendChild(o);
  }

  // Roast age (colour-coded) and when I looked at it, on one line.
  const meta = document.createElement('div');
  meta.className = 'hmeta';
  if (entry.roastDays != null) {
    const roast = document.createElement('span');
    roast.className = 'hroast';
    roast.textContent = roastLabel(entry.roastDays);
    roast.style.color = roastColor(entry.roastDays);
    if (entry.roastStale) roast.title = 'Over 40 days at the time — the score was penalised';
    meta.appendChild(roast);
  }
  const seen = document.createElement('span');
  seen.className = 'hseen';
  // The age shown is the age AT THE VISIT, so the visit time is what makes it
  // readable — "roasted 30d ago, seen 5d ago" is a different bag today.
  seen.textContent = `seen ${relativeTime(entry.savedAt)}`;
  seen.title = new Date(entry.savedAt).toLocaleString();
  meta.appendChild(seen);
  mid.appendChild(meta);

  if (entry.ownedTitle) {
    const owned = document.createElement('div');
    owned.className = 'howned';
    owned.textContent = 'IN YOUR LIBRARY';
    mid.appendChild(owned);
  }

  row.appendChild(mid);

  // --- right column: score in the rating's slot, then price, then the pills
  const right = document.createElement('div');
  right.className = 'hright';

  const score = document.createElement('div');
  score.className = entry.score >= 60 ? 'hscore high' : 'hscore';
  score.textContent = entry.score == null ? '—' : String(entry.score);
  right.appendChild(score);

  if (entry.pricePer100gEur != null) {
    const p = document.createElement('div');
    p.className = 'hprice';
    p.textContent = `€${entry.pricePer100gEur.toFixed(2)}/100g`;
    right.appendChild(p);
  } else if (entry.priceAmount != null && entry.priceCurrency) {
    const p = document.createElement('div');
    p.className = 'hprice';
    p.textContent = `${entry.priceAmount} ${entry.priceCurrency}`;
    right.appendChild(p);
  }

  if (entry.valuePills != null) {
    const pills = document.createElement('div');
    pills.className = 'hpills';
    for (let i = 0; i < 5; i++) {
      const pill = document.createElement('span');
      pill.className = i < entry.valuePills ? 'hpill on' : 'hpill';
      pills.appendChild(pill);
    }
    right.appendChild(pills);
  }

  row.appendChild(right);

  // --- evaluator note, collapsed
  if (entry.explanation) {
    const toggle = document.createElement('button');
    toggle.className = 'hnote-toggle';
    toggle.textContent = 'Why?';
    const note = document.createElement('div');
    note.className = 'hnote';
    note.textContent = entry.explanation;
    note.hidden = true;
    toggle.addEventListener('click', () => {
      note.hidden = !note.hidden;
      toggle.textContent = note.hidden ? 'Why?' : 'Hide';
    });
    row.append(toggle, note);
  }

  return row;
}

async function renderHistory() {
  const section = $('history');
  const list = $('history-list');
  const entries = await loadHistory();
  const { top, unscoredCount, total } = rank(entries);

  section.classList.remove('hidden');
  $('history-meta').textContent = total === 0 ? 'nothing yet' : `${top.length} of ${total} · ${RETENTION_DAYS}d`;

  list.replaceChildren();
  if (top.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent =
      total === 0
        ? `Coffees you evaluate are saved here for ${RETENTION_DAYS} days, ranked by score.`
        : `${total} saved, but none has a headline score yet — a page needs a price for that.`;
    list.appendChild(empty);
  } else {
    for (const entry of top) list.appendChild(historyRow(entry));
  }

  const foot = document.createElement('div');
  foot.className = 'history-foot';
  const note = document.createElement('span');
  note.textContent = unscoredCount > 0 ? `${unscoredCount} more without a score` : '';
  const clear = document.createElement('button');
  clear.className = 'btn ghost small';
  clear.textContent = 'Clear';
  clear.addEventListener('click', async () => {
    const { clearHistory } = await import('./history.js');
    await clearHistory();
    renderHistory();
  });
  foot.append(note, clear);
  list.appendChild(foot);
}

async function initHistory() {
  const stored = await chrome.storage.local.get(HISTORY_OPEN_KEY);
  let open = Boolean(stored?.[HISTORY_OPEN_KEY]);

  const apply = () => {
    $('history-list').classList.toggle('hidden', !open);
    $('history-caret').textContent = open ? '▾' : '▸';
    $('history-toggle').setAttribute('aria-expanded', String(open));
  };

  $('history-toggle').addEventListener('click', async () => {
    open = !open;
    apply();
    await chrome.storage.local.set({ [HISTORY_OPEN_KEY]: open });
  });

  apply();
  await renderHistory();
}

async function run() {
  show('loading');
  const res = await chrome.runtime.sendMessage({ type: 'score' });
  if (!res || res.error) {
    renderError(res ?? { error: 'unexpected' });
  } else {
    const { writeToken } = await getSettings();
    render(res.data, Boolean(writeToken));
  }
  // Deliberately after BOTH branches: opening the popup on a non-coffee tab
  // should still show the top 10. "Always show" means always.
  await renderHistory();
}

$('settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('err-settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('err-retry').addEventListener('click', run);

initHistory();
run();
