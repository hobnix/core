// A log view that follows a stream instead of asking again and again (live step 16, decision D15).
//
//   const feed = logfeed({ stream: () => '/api/logs/stream/ct?target=web', read: () => '/api/sys/ct/logs/web?lines=200', follow: () => follow });
//   feed.lines (oldest first), feed.loaded, feed.error, feed.streaming
//
// The stream is server-sent events (GET /api/logs/stream/<kind>, scripts/web-serve.py `_logs_stream`): `data: {"lines": [...]}` batches, the first ones are the
// fill (200 lines), the later ones are what was appended. One EventSource per view; the browser holds only 6 connections per server and the page keeps one
// event stream already, so a view opens its stream only while it is shown (never on hover) and a `follow` switched off closes it.
//   - A tab nobody sees (document.hidden) closes its stream after 15 minutes; it opens again, with a fresh fill, when the tab is shown.
//   - When the stream cannot be had (cap reached, 503, signed out, server restarting, the command ended) the view falls back to the old timed read
//     until the stream is back: the one timed read of every log view is the `poll` below, so the ratchet counts it once.
// A log may hold secrets: nothing here is cached or kept beyond the view.
import { poll } from './data.svelte.js';

export const HIDDEN_PARK_MS = 15 * 60 * 1000;   // D15: a stream with no visible tab closes after 15 minutes
const RETRY_MS = 10000;                          // a dropped stream tries again after this long, the timed read serves meanwhile

const textLines = (d) => (d?.text ?? '').split('\n').filter(Boolean);

export function logfeed({ stream, read, follow = () => true, every = 5000, toLines = textLines, max = 2000 }) {
  const st = $state({ buf: [], opened: false, failed: false, parked: false });

  // the stream: opens while `stream()` has an address and `follow()` is on and the tab was not parked
  $effect(() => {
    const url = stream();
    const want = !!url && follow() && !st.parked;
    if (!want) return;
    if (typeof EventSource === 'undefined') { st.failed = true; return; }
    let es = null;
    let retry = 0;
    let fresh = true;
    let alive = true;
    st.buf = [];
    st.opened = false;
    const drop = () => {
      es?.close();
      es = null;
      if (!alive) return;
      st.failed = true;
      retry = setTimeout(open, RETRY_MS);
    };
    function open() {
      if (!alive) return;
      fresh = true;
      es = new EventSource(url);
      es.onmessage = (e) => {
        let d;
        try { d = JSON.parse(e.data); } catch { return; }
        if (fresh) { st.buf = []; fresh = false; }
        const b = st.buf.concat(d.lines || []);
        st.buf = b.length > max ? b.slice(-max) : b;
        st.opened = true;
        st.failed = false;
      };
      es.onopen = () => { st.opened = true; st.failed = false; };
      es.addEventListener('end', drop);
      es.onerror = drop;
    }
    open();
    return () => { alive = false; clearTimeout(retry); es?.close(); };
  });

  // a hidden tab parks the stream after 15 minutes, showing the tab opens it again
  $effect(() => {
    if (typeof document === 'undefined') return;
    let t = 0;
    const onVis = () => {
      clearTimeout(t);
      if (document.hidden) t = setTimeout(() => { st.parked = true; }, HIDDEN_PARK_MS);
      else if (st.parked) st.parked = false;
    };
    onVis();
    document.addEventListener('visibilitychange', onVis);
    return () => { clearTimeout(t); document.removeEventListener('visibilitychange', onVis); };
  });

  // the fallback: the old timed read, only while the stream is not what serves the view (or follow is off and nothing was read yet)
  const fb = poll(() => (stream() && !st.parked && (st.failed || (!follow() && !st.opened && !fb?.loaded)) ? read() : ''), every);

  const useFb = $derived((!st.opened || st.failed) && !!fb.data);
  const lines = $derived(useFb ? toLines(fb.data) : st.buf);
  return {
    get lines() { return lines; },
    get loaded() { return st.opened || fb.loaded; },
    get error() { return st.failed && fb.error && !fb.data ? fb.error : null; },
    get streaming() { return st.opened && !st.failed; },
  };
}
