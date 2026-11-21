// The topics an open page reads (D13): a reference count per topic, so two reads of one topic and a read that re-runs (release, then want again)
// leave the set as it was. Plain JS so tests/web-live.mjs can load it in node. `*` = every topic (the Live state page measures all of them).
export const ALWAYS = ['reads:jobs-records'];   // the job strip, row state and job dialogs of the shell follow this one on every page

export class TopicSet {
  constructor(always = ALWAYS) { this.always = always; this.n = new Map(); }
  // -> a function that gives the topic back (call it once)
  want(topic) {
    if (!topic) return () => {};
    this.n.set(topic, (this.n.get(topic) ?? 0) + 1);
    let done = false;
    return () => {
      if (done) return;
      done = true;
      const c = (this.n.get(topic) ?? 1) - 1;
      if (c <= 0) this.n.delete(topic); else this.n.set(topic, c);
    };
  }
  // the sorted set to send; `*` swallows the rest
  list() {
    const all = new Set([...this.always, ...this.n.keys()]);
    return all.has('*') ? ['*'] : [...all].sort();
  }
  key() { return this.list().join(','); }
}

// the query of /api/events: `topics=a,b&sid=<id>`; a topic name never needs escaping, but encode anyway
export const streamQuery = (list, sid) => `topics=${list.map(encodeURIComponent).join(',')}&sid=${encodeURIComponent(sid)}`;

// one id per stream, chosen by the page (the server finds the stream by it for the subscribe call)
export function newSid(rand = Math.random) {
  let s = '';
  for (let i = 0; i < 16; i++) s += 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(rand() * 36)];
  return s;
}

// Debounced sender of the set: want() calls come in bursts (a route change releases and registers every read of two pages), one POST follows.
// send(list) -> Promise<{gens}|undefined>; it is only called when the set differs from what the server has.
export function createSubscriber({ set, send, delay = 100, setTimer = setTimeout, clearTimer = clearTimeout, onGens = () => {} }) {
  let sentKey = null, timer = null, inflight = false, again = false, ready = false;
  const run = async () => {
    timer = null;
    if (!ready) return;
    if (inflight) { again = true; return; }
    const key = set.key();
    if (key === sentKey) return;
    inflight = true;
    try {
      const r = await send(set.list());
      sentKey = key;
      if (r && r.gens) onGens(r.gens);
    } catch { /* the next change or the next open sends it again */ }
    inflight = false;
    if (again || set.key() !== sentKey) { again = false; schedule(); }
  };
  const schedule = () => { if (timer === null) timer = setTimer(run, delay); };
  return {
    schedule,
    // the stream opened (or reopened) with `key` in its URL: that is what the server has
    opened(key, fresh = true) { sentKey = fresh ? key : null; ready = true; schedule(); },
    closed() { ready = false; if (timer !== null) { clearTimer(timer); timer = null; } },
    get sentKey() { return sentKey; },
  };
}
