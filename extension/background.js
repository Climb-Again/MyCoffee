// MV3 service worker (#162).
//
// The API call happens HERE, not in the injected scraper or the popup, and
// that is load-bearing: a service-worker fetch covered by `host_permissions`
// is exempt from CORS, so the backend needs no @fastify/cors and no
// `Access-Control-Allow-Origin` for a shop's origin. (Checked before writing
// this: `server.js` registers helmet, rate-limit, multipart, compress and etag
// — no cors plugin, and none is needed as long as the fetch stays here.)
import { scrapePage } from './scrape.js';
import { getSettings } from './settings.js';
import { checkForUpdate, scheduleUpdateChecks, UPDATE_ALARM } from './update.js';
import { recordVisit } from './history.js';

async function scoreActiveTab() {
  const { baseUrl, token } = await getSettings();
  if (!token) return { error: 'no_token' };

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return { error: 'no_tab' };
  // `tab.url` is only readable once `activeTab` is granted for this tab. Reject
  // only a URL we can see AND know is unsupported -- an absent url means "not
  // visible yet", not "not a web page", and letting executeScript fail below
  // gives a truthful error instead of a wrong one.
  if (tab.url && !/^https?:/i.test(tab.url)) return { error: 'unsupported_page' };

  let scraped;
  try {
    // `activeTab` grants this only because the user clicked the toolbar button.
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: scrapePage,
    });
    scraped = result;
  } catch (e) {
    // Chrome refuses injection on its own pages, the Web Store, and PDFs.
    return { error: 'cannot_read_page', detail: String(e?.message ?? e) };
  }

  if (!scraped?.text || scraped.text.trim().length < 40) return { error: 'not_enough_text' };

  let res;
  try {
    res = await fetch(`${baseUrl}/api/score`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ url: scraped.url, title: scraped.title, text: scraped.text }),
    });
  } catch (e) {
    return { error: 'network', detail: String(e?.message ?? e) };
  }

  if (res.status === 401) return { error: 'bad_token' };
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const body = await res.json();
      if (body?.error) detail = body.error;
    } catch {
      // Non-JSON error body; the status code is enough.
    }
    return { error: 'server', detail };
  }

  const data = await res.json();
  // The page's own image never reaches the server -- scoring has no use for
  // it -- so attach it here for the history list.
  data.imageUrl = scraped.imageUrl ?? null;

  // #187. Failing to save must never fail the score the user asked for.
  try {
    await recordVisit(data, { url: scraped.url, title: scraped.title });
  } catch (e) {
    console.warn('[mycoffee] could not save to history', e);
  }

  return { ok: true, data, pageTitle: scraped.title };
}

// #161: accept one enrich suggestion -- write a single field onto a coffee he
// already owns. Deliberately routed through #40's edit endpoint rather than any
// new write path: that endpoint re-parses the value with the same parser the
// in-app edit sheet uses, refuses to touch a human-locked field, and records
// the result as `decided_by='human'` -- correct, since Radu tapped it.
async function acceptEnrich({ coffeeId, field, value }) {
  const { baseUrl, writeToken } = await getSettings();
  if (!writeToken) return { error: 'no_write_token' };
  if (!coffeeId || !field) return { error: 'bad_request' };

  let res;
  try {
    res = await fetch(`${baseUrl}/api/coffees/${encodeURIComponent(coffeeId)}/edit`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${writeToken}` },
      body: JSON.stringify({ field, value }),
    });
  } catch (e) {
    return { error: 'network', detail: String(e?.message ?? e) };
  }

  if (res.status === 401) return { error: 'bad_write_token' };
  if (res.status === 422) return { error: 'unresolvable', detail: `the backend could not parse "${value}"` };
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const body = await res.json();
      if (body?.error) detail = body.error;
    } catch {
      // Non-JSON body; the status is enough.
    }
    return { error: 'server', detail };
  }
  return { ok: true };
}

// Auto-update (see update.js). The alarm survives the service worker being
// torn down, which a setInterval would not -- an MV3 worker is evicted after
// ~30s idle, so a timer-based check would simply never fire.
chrome.runtime.onInstalled.addListener(() => {
  scheduleUpdateChecks();
  checkForUpdate();
});
chrome.runtime.onStartup.addListener(() => {
  scheduleUpdateChecks();
  checkForUpdate();
});
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === UPDATE_ALARM) checkForUpdate();
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  // Manual "check now" from the options page. autoReload:false so a human
  // pressing the button gets an answer rather than the page vanishing under
  // them mid-reload.
  if (msg?.type === 'checkUpdate') {
    checkForUpdate({ autoReload: Boolean(msg.autoReload) })
      .then(sendResponse)
      .catch((e) => sendResponse({ error: String(e?.message ?? e) }));
    return true;
  }
  if (msg?.type === 'enrich') {
    acceptEnrich(msg)
      .then(sendResponse)
      .catch((e) => sendResponse({ error: 'unexpected', detail: String(e?.message ?? e) }));
    return true;
  }
  if (msg?.type !== 'score') return false;
  // Returning true keeps the message channel open for the async reply; a
  // rejected promise must still produce a response or the popup hangs.
  scoreActiveTab()
    .then(sendResponse)
    .catch((e) => sendResponse({ error: 'unexpected', detail: String(e?.message ?? e) }));
  return true;
});
