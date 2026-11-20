// Browser notifications (#888, D7 of docs/PLAN-live-interface.md), as plain functions (tests/web-notify.mjs runs them with node).
// Opt-in per browser, off by default. Only the Notification API of the page: no service worker, no push service, nothing leaves the server.
// The Watcher decides what is raised: a new unacknowledged problem, or a new warn/error event, that this page has not shown before; never while the
// page has the focus, never what was already there when the page opened or the switch went on.

const REASONS = {
  none: 'This browser has no notification support.',
  insecure: 'This browser only allows notifications on a secure page (HTTPS, or localhost). This page is plain HTTP.',
  denied: 'Notifications are blocked for this site in the browser. Allow them in the site settings of the browser, then turn this on again.',
};

// {ok, reason}: can this page raise notifications at all (before the user is asked)? `g` is the window (a fake one in the tests).
export function notifySupport(g = globalThis) {
  if (g.isSecureContext === false) return { ok: false, reason: REASONS.insecure };
  if (typeof g.Notification !== 'function') return { ok: false, reason: REASONS.none };
  if (g.Notification.permission === 'denied') return { ok: false, reason: REASONS.denied };
  return { ok: true, reason: '' };
}

// The text goes onto the desktop: no serial numbers or other identifiers. The part after "Details" is dropped, a word of 8 or more characters
// that has a digit in it (serials, ids, keys) becomes "...", and the text is cut at 100 characters.
export function safeText(text) {
  const t = String(text ?? '').split(/\s*Details\b/i)[0]
    .replace(/\S*\d\S*/g, (w) => (w.replace(/[^A-Za-z0-9]/g, '').length >= 8 ? '...' : w))
    .replace(/\s+/g, ' ').trim();
  return t.length > 100 ? `${t.slice(0, 99)}…` : t;
}

export class Watcher {
  // raise(item) shows one notification; focused() says the person is looking at this page right now
  constructor({ raise, focused }) { this.raise = raise; this.focused = focused; this.problems = null; this.lastNote = 0; }
  // problems/notes are the items of shell/inbox.js; ready = the first read of the problem list has arrived. Returns the items raised.
  update(problems, notes, ready = true) {
    if (!ready) return [];
    const ids = new Set(problems.map((p) => p.id));
    const out = [];
    if (this.problems === null) {
      this.problems = ids;                                     // the baseline: what is open now is not news
      this.lastNote = notes.reduce((m, n) => Math.max(m, n.id), 0);
      return out;
    }
    for (const p of problems) if (!p.acked && !this.problems.has(p.id)) out.push({ ...p, tag: `p:${p.id}` });
    for (const n of notes) if (n.id > this.lastNote) out.push({ ...n, tag: `n:${n.id}` });
    this.problems = ids;                                       // a problem that went away and comes back is news again
    this.lastNote = Math.max(this.lastNote, ...notes.map((n) => n.id));
    if (this.focused()) return [];
    out.forEach((i) => this.raise(i));
    return out;
  }
}

// the notification of one item: [title, options]. The tag makes a second one of the same item replace the first.
export function notificationFor(item) {
  const title = item.kind === 'problem' ? 'Hobnix: problem' : item.level === 'error' ? 'Hobnix: error' : 'Hobnix: warning';
  return [title, { body: safeText(item.text), tag: item.tag }];
}
