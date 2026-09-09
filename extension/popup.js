// Popup UI (#162).
//
// Wording is fixed by #106 and must stay identical to the iOS screen (#125):
// this is FIT WITH WHAT YOU BUY, never a predicted rating. The endpoint's own
// validation is r≈0.39 against real ratings, so calling it a prediction would
// be a claim the data does not support. Components carry equal visual weight
// with the headline, and a `low` confidence result shows no headline number at
// all — the server already returns `score: null` in that case, and this file
// never invents one.

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

function render(data) {
  const { score, confidence, components, fields, missing, explanation, cached } = data;

  // A suppressed headline is a deliberate outcome, not a failure: #106 says
  // show the components and say why, rather than invent a number.
  const scoreEl = $('score');
  scoreEl.textContent = score == null ? '—' : String(score);
  scoreEl.classList.toggle('suppressed', score == null);
  $('score-label').textContent = score == null ? 'no headline number' : 'fit with what you buy';
  $('confidence').classList.toggle('hidden', confidence !== 'low');
  $('explanation').textContent = explanation ?? '';

  const bars = $('bars');
  bars.replaceChildren();
  bars.appendChild(bar('Affinity', components?.affinity?.score ?? null));
  bars.appendChild(
    components?.value == null
      ? bar('Value', null, 'n/a')
      : bar('Value', components.value.score, null),
  );
  if (components?.roastRecency != null) {
    bars.appendChild(bar('Freshness', components.roastRecency.score));
  }

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
  if (fields?.roastedOn) {
    const d = components?.roastRecency?.daysSinceRoast;
    chips.appendChild(chip(d == null ? fields.roastedOn : `roasted ${d}d ago`));
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

async function run() {
  show('loading');
  const res = await chrome.runtime.sendMessage({ type: 'score' });
  if (!res || res.error) return renderError(res ?? { error: 'unexpected' });
  render(res.data);
}

$('settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('err-settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('err-retry').addEventListener('click', run);

run();
