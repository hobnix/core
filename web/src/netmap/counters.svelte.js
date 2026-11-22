// The counters of the network map, as rates (#877, docs/PLAN-network-map.md part 2).
//
//   const c = netmapCounters();   // call during component setup
//   c.rates   { [nodeId]: { rx, tx } } bytes per second, {} until two readings are in
//   c.mode    'connecting' | 'stream' | 'poll' (the stream is down, the timed read serves) | 'off' (neither answers)
//
// The server sends totals about every 2 s on GET /api/netmap/stream (server-sent events, one shared sampler, only while a page listens); this divides
// two readings by their times. The page keeps ONE stream open and only while it is shown. When the stream cannot be had (503 at the cap, signed out,
// a restart) the page reads `sys netmap counters` every 5 s until the stream is back: polling is the fallback, never the plan. A tab nobody sees
// (document.hidden) closes the stream and reopens it when the tab is shown, so a hidden tab costs the server nothing. No old value is kept: after a
// gap the first new reading gives no rates, the second does.
import { get } from './../api.js';
import { ratesFrom } from './rates.js';

export const STREAM_URL = '/api/netmap/stream';
const RETRY_MS = 10000;       // a dropped stream tries again after this long
const POLL_MS = 5000;         // the fallback read

export function netmapCounters() {
  const st = $state({ rates: {}, mode: 'connecting' });
  let prev = null;
  const feed = (frame) => { st.rates = ratesFrom(prev, frame); prev = frame; };
  const gap = () => { prev = null; st.rates = {}; };

  $effect(() => {
    if (typeof EventSource === 'undefined') { st.mode = 'poll'; return; }
    let es = null, retry = 0, alive = true, hidden = typeof document !== 'undefined' && document.hidden;
    const close = () => { es?.close(); es = null; };
    const fail = () => {
      close();
      if (!alive) return;
      gap();
      st.mode = 'poll';
      clearTimeout(retry);
      retry = setTimeout(open, RETRY_MS);
    };
    function open() {
      if (!alive || es || hidden) return;
      es = new EventSource(STREAM_URL);
      es.onmessage = (e) => {
        let d;
        try { d = JSON.parse(e.data); } catch { return; }
        if (!d || !Array.isArray(d.rows) || !(d.t > 0)) return;
        st.mode = 'stream';
        feed(d);
      };
      es.addEventListener('end', fail);
      es.onerror = fail;
    }
    const onVis = () => {
      hidden = document.hidden;
      if (hidden) { close(); clearTimeout(retry); gap(); } else open();
    };
    document.addEventListener('visibilitychange', onVis);
    open();
    return () => { alive = false; clearTimeout(retry); close(); document.removeEventListener('visibilitychange', onVis); };
  });

  // the fallback: the timed read, only while the stream is not what serves the page (reason in scripts/lib/read-reasons.tsv)
  $effect(() => {
    if (st.mode !== 'poll') return;
    let alive = true, timer = 0;
    const run = async () => {
      try {
        const d = await get('/api/sys/netmap/counters');
        if (alive && st.mode === 'poll') feed({ t: Date.now(), rows: d?.rows ?? [] });
      } catch {
        if (alive) gap();
      }
      if (alive) timer = setTimeout(run, POLL_MS);
    };
    run();
    return () => { alive = false; clearTimeout(timer); };
  });

  return st;
}
