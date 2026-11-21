// The browser half of the delay measure (#486, D8): how long after a `changed` event of the stream the Live state page showed the new data.
// Pure JavaScript: the page feeds it the events and the rows it shows; `send(topic, ms)` posts a number to the server (only a topic name and
// milliseconds, nothing about the viewer). A topic is sampled at most once per `gap` ms and a pending change that is never shown is dropped
// after `expire` ms, so a page that is slow to load or in a background tab sends nothing wrong.
/**
 * @param {(topic: string, ms: number) => void} send
 * @param {{ now?: () => number, gap?: number, expire?: number }} [opt]
 */
export function createSampler(send, opt = {}) {
  const now = opt.now ?? (() => performance.now());
  const gap = opt.gap ?? 2000;
  const expire = opt.expire ?? 60000;
  /** @type {Map<string, {gen: number, t: number}>} */
  const pending = new Map();
  /** @type {Map<string, number>} */
  const sent = new Map();
  /** @type {Map<string, number>} */
  const known = new Map();
  return {
    /** the stream says `topic` is now at `gen`; the first sight of a topic is no change */
    changed(topic, gen) {
      const g = Number(gen);
      if (!Number.isFinite(g)) return;
      const had = known.get(topic);
      known.set(topic, g);
      if (had === undefined || g <= had || pending.has(topic)) return;   // an older change keeps its start time
      pending.set(topic, { gen: g, t: now() });
    },
    /** the page shows these rows ({topic, gen}) now: every pending topic whose row reached its gen gives one sample */
    shown(rows) {
      const t1 = now();
      for (const r of rows || []) {
        const p = pending.get(r.topic);
        if (!p) continue;
        if (t1 - p.t > expire) { pending.delete(r.topic); continue; }
        if (Number(r.gen) < p.gen) continue;
        pending.delete(r.topic);
        const last = sent.get(r.topic);
        if (last !== undefined && t1 - last < gap) continue;
        sent.set(r.topic, t1);
        send(r.topic, Math.max(0, Math.round(t1 - p.t)));
      }
    },
  };
}
