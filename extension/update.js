// Auto-update for an unpacked extension (Radu, 2026-09-09: "make it auto
// updateable, too much manual work").
//
// An unpacked extension gets none of the Web Store's update machinery, and it
// cannot rewrite its own files — `chrome.runtime.reload()` is the one lever it
// has, and for an unpacked extension that lever re-reads everything from disk.
// So auto-update is two halves that have to meet:
//
//   1. Something keeps the files on disk current. That is `git pull`, run by a
//      launchd agent — `install-autoupdate.sh` sets it up once.
//   2. Something notices and reloads. That is this file.
//
// The version check reads the manifest straight from GitHub rather than from
// our own backend, deliberately: the repo is public so it needs no token, and
// it stays truthful even if the backend is down or was never reachable. It is
// a plain version-string read — no code is fetched or executed. MV3 forbids
// remote code and this respects that: the only thing that ever changes the
// extension's behaviour is a file `git pull` put on disk.
const MANIFEST_URL = 'https://raw.githubusercontent.com/Climb-Again/MyCoffee/main/extension/manifest.json';

export const UPDATE_ALARM = 'mycoffee-update-check';
const CHECK_PERIOD_MINUTES = 180;

// A reload only helps once `git pull` has actually landed the new files. If it
// hasn't, we would reload into the same version and try again forever, so each
// target version gets a small, finite number of attempts.
const MAX_RELOAD_ATTEMPTS = 3;

// "1.2.10" > "1.2.9" — string compare gets this wrong, so compare numerically.
export function isNewer(candidate, current) {
  const parse = (v) => String(v ?? '').split('.').map((n) => parseInt(n, 10) || 0);
  const a = parse(candidate);
  const b = parse(current);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0;
    const y = b[i] ?? 0;
    if (x !== y) return x > y;
  }
  return false;
}

async function fetchLatestVersion() {
  // no-store plus a cache-buster: raw.githubusercontent sits behind a CDN with
  // its own few-minute cache, and a stale read here just delays an update.
  const res = await fetch(`${MANIFEST_URL}?t=${Date.now()}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const manifest = await res.json();
  const version = manifest?.version;
  if (typeof version !== 'string') throw new Error('no version in remote manifest');
  return version;
}

async function setBadge(updateAvailable) {
  try {
    await chrome.action.setBadgeText({ text: updateAvailable ? '↑' : '' });
    if (updateAvailable) {
      await chrome.action.setBadgeBackgroundColor({ color: '#0078ff' });
      await chrome.action.setTitle({ title: 'Evaluate this coffee — an update is ready' });
    } else {
      await chrome.action.setTitle({ title: 'Evaluate this coffee' });
    }
  } catch {
    // Badge is a nicety; never let it break the check.
  }
}

/**
 * One update check. Returns a small record of what happened, which the options
 * page renders so "is it updating?" is answerable without reading logs.
 */
export async function checkForUpdate({ autoReload = true } = {}) {
  const current = chrome.runtime.getManifest().version;
  const stamp = new Date().toISOString();

  let latest;
  try {
    latest = await fetchLatestVersion();
  } catch (e) {
    const state = { checkedAt: stamp, current, error: String(e?.message ?? e) };
    await chrome.storage.local.set({ updateState: state });
    return state;
  }

  if (!isNewer(latest, current)) {
    await setBadge(false);
    const state = { checkedAt: stamp, current, latest, upToDate: true };
    await chrome.storage.local.set({ updateState: state, reloadAttempts: null });
    return state;
  }

  await setBadge(true);

  // Count attempts per target version so a missing `git pull` cannot put us in
  // a reload loop.
  const { reloadAttempts } = await chrome.storage.local.get('reloadAttempts');
  const attempts = reloadAttempts?.version === latest ? reloadAttempts.count : 0;
  const exhausted = attempts >= MAX_RELOAD_ATTEMPTS;

  const state = {
    checkedAt: stamp,
    current,
    latest,
    upToDate: false,
    attempts,
    // The honest diagnosis when reloading stopped helping: the files on disk
    // are still the old ones, so nothing is pulling them.
    stalled: exhausted,
  };
  await chrome.storage.local.set({ updateState: state });

  if (autoReload && !exhausted) {
    await chrome.storage.local.set({ reloadAttempts: { version: latest, count: attempts + 1 } });
    // For an UNPACKED extension this re-reads the manifest and every file from
    // disk — which is the whole mechanism. If git pull has landed, we come back
    // as `latest`; if not, we come back unchanged and burn one attempt.
    chrome.runtime.reload();
  }

  return state;
}

export async function scheduleUpdateChecks() {
  await chrome.alarms.create(UPDATE_ALARM, {
    delayInMinutes: 1,
    periodInMinutes: CHECK_PERIOD_MINUTES,
  });
}
