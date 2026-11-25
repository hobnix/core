// Polled reads. `poll('/api/sys/ct/list', 5000)` gives a reactive { data, error, loaded }. The path may be a function (or return
// '' to pause, e.g. while a panel is collapsed). A failed read keeps the last data, so a page never flashes empty on one bad answer.
import { get, forgetReads } from './api.js';
import { live, STREAM_TOPICS, wantTopic } from './live.svelte.js';
import { nextDelay } from './polldelay.js';
export { ageOf, stateOf } from './api.js';

// The last answer per path, for the whole session: a page revisited (or the tree's counts) shows it at once and then reads again.
const cache = new Map();
// clearPollCache (sign-out, lock) ends the cache's session: an answer asked before it never enters the cache, so the next user (or the pickers after
// the next unlock) cannot be shown it. forgetReads: nobody joins a read that began before.
let session = 0;
export const cacheSession = () => session;
export const clearPollCache = () => { session++; cache.clear(); forgetReads(); };
// call it when the read is asked: what it returns keeps the answer only while that session lasts
const keeper = (p) => { const asked = session; return (d) => { if (asked === session) cache.set(p, d); }; };

// Read these paths once, one after the other, when the browser is idle (after sign-in), so the first click on a page finds its data.
export function prefetch(paths) {
  const idle = window.requestIdleCallback || ((f) => setTimeout(f, 300));
  const born = session;
  let i = 0;
  const next = () => {
    if (i >= paths.length || born !== session) return;
    const p = paths[i++];
    (cache.has(p) ? Promise.resolve() : get(p).then(keeper(p)).catch(() => {})).finally(() => idle(next));
  };
  idle(next);
}

// Fetch these paths now (all at once) and keep the answers in the cache; for the moment before a page opens (the pointer is on its tree entry).
// An error leaves the old answer where it is.
export function touch(paths) {
  for (const p of paths) get(p).then(keeper(p)).catch(() => {});
}

// The refresh button of a page: read these paths now (the server runs the scripts, whatever it holds), keep the answers, and let every poll show them.
export const sync = $state({ n: 0, busy: false });
export async function refresh(paths) {
  sync.busy = true;
  try {
    await Promise.all(paths.map((p) => get(p, true).then(keeper(p)).catch(() => {})));
  } finally {
    sync.busy = false;
    forgetReads();   // the polls that run again now must not join a read that began before this one was done
    sync.n++;
  }
}

// topic: the name of the server's live state for this read (Summary: 'status'); it may be a function resolved like path. While the live
// stream is open the read follows it instead of a timer.
export function poll(path, ms, topic) {
  const st = $state({ data: null, error: null, loaded: false });
  $effect(() => {
    sync.n;   // a refresh re-runs this effect: the new answer is in the cache
    const p = typeof path === 'function' ? path() : path;
    if (!p) return;
    const t = (typeof topic === 'function' ? topic() : topic) ?? live.topics[p];
    const liveOpen = !!t && live.open && (live.follow || STREAM_TOPICS.has(t));
    if (t) { live.gen[t]; live.resyncs; }   // a change of the topic (or a resync) re-runs this effect, which reads again
    const release = wantTopic(t);           // D13: the stream carries this topic while the read is on a page
    if (cache.has(p)) { st.data = cache.get(p); st.error = null; st.loaded = true; }
    let alive = true;
    let timer;
    const run = async () => {
      let err = null;
      const keep = keeper(p);
      try {
        const d = await get(p);
        keep(d);
        if (alive) { st.data = d; st.error = null; }
      } catch (e) {
        err = e;
        if (alive) st.error = e;
      }
      if (alive) {
        st.loaded = true;
        const wait = nextDelay(t, liveOpen, ms, err);
        if (wait !== null) timer = setTimeout(run, wait);
      }
    };
    run();
    return () => { alive = false; clearTimeout(timer); release(); };
  });
  return st;
}

// the rows of a tsv answer, [] before the first answer
export const rows = (st) => st.data?.rows ?? [];
