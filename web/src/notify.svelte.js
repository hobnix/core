// Browser notifications, the switch (#888). Kept in this browser only (localStorage, wrapped in try/catch); off by default.
// The permission prompt is asked only from enableNotify(), which the click on the switch calls: never on load. Logic: shell/notify.js.
import { notifySupport, notificationFor } from './shell/notify.js';
import { go } from './route.svelte.js';

const KEY = 'hs.notify';
let stored = false;
try { stored = localStorage.getItem(KEY) === '1'; } catch { /* no memory */ }

export const nf = $state({ on: false, reason: '' });

function remember(v) { try { if (v) localStorage.setItem(KEY, '1'); else localStorage.removeItem(KEY); } catch { /* no memory */ } }

// the state on load: on only if it was turned on here, and the browser still allows it. No prompt.
export function initNotify(g = globalThis) {
  const s = notifySupport(g);
  nf.reason = s.reason;
  nf.on = stored && s.ok && g.Notification.permission === 'granted';
}

export async function enableNotify(g = globalThis) {
  const s = notifySupport(g);
  nf.reason = s.reason;
  if (!s.ok) { nf.on = false; return false; }
  let perm = g.Notification.permission;
  if (perm !== 'granted') {
    try { perm = await g.Notification.requestPermission(); } catch { perm = 'default'; }
  }
  nf.on = perm === 'granted';
  if (perm === 'denied') nf.reason = notifySupport(g).reason || 'Notifications are blocked for this site in the browser.';
  else if (perm !== 'granted') nf.reason = 'The browser did not give permission. Turn this on again to be asked once more.';
  else nf.reason = '';
  remember(nf.on);
  return nf.on;
}

export function disableNotify() { nf.on = false; nf.reason = ''; remember(false); }

// Shows one item; a click brings this tab to the front and opens the page of the object.
export function raiseNotification(item, g = globalThis) {
  try {
    const [title, opts] = notificationFor(item);
    const n = new g.Notification(title, opts);
    n.onclick = () => { try { g.focus?.(); } catch { /* ignored */ } go(item.href); n.close?.(); };
  } catch { /* a browser that refuses (some mobile ones) must not break the page */ }
}

export const pageFocused = (d = globalThis.document) => !!d && !d.hidden && (typeof d.hasFocus !== 'function' || d.hasFocus());

if (typeof window !== 'undefined') initNotify();
