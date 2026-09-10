// Shared settings accessor.
//
// Deliberately its own module rather than living in background.js: the options
// page needs `getSettings` too, and importing background.js from the options
// page would re-run its top level there — registering a SECOND
// `chrome.runtime.onMessage` listener in the options context, which could then
// answer a popup's `score` message instead of the service worker.
export const DEFAULT_BASE_URL = 'https://mycoffee-production-bd43.up.railway.app';

export async function getSettings() {
  const { baseUrl, token, writeToken } = await chrome.storage.local.get(['baseUrl', 'token', 'writeToken']);
  return {
    baseUrl: (baseUrl || DEFAULT_BASE_URL).replace(/\/+$/, ''),
    token: token || '',
    // Optional and separate on purpose (#161). Scoring is read-only and needs
    // only APP_TOKEN; accepting an enrich suggestion is a WRITE and needs
    // INGEST_TOKEN. Keeping them apart means someone who only wants the score
    // never has to put a write credential in their browser profile.
    writeToken: writeToken || '',
  };
}
