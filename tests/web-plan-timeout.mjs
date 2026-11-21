// A plan or start the server never answers ends with a message instead of waiting for ever (web/src/api.js CHANGE_WAIT_MS), and a task whose job
// record cannot be read ends with a toast (web/src/ui.svelte.js POLL_MAX_ERRORS).
let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
  const s = init.signal;
  if (url === '/api/session') return resolve({ ok: true, headers: new Headers(), json: async () => ({ csrf: 'x' }) });
  s?.addEventListener('abort', () => { const e = new Error('aborted'); e.name = 'AbortError'; reject(e); });   // never answers by itself
});
const api = await import('../web/src/api.js');
check('the wait is a little more than the 60 s the server gives a script', api.CHANGE_WAIT_MS > 60000 && api.CHANGE_WAIT_MS <= 120000);

// shrink the wait through a fake timer: setTimeout fires at once for the long waits
const realSet = globalThis.setTimeout;
globalThis.setTimeout = (f, ms, ...a) => realSet(f, ms >= api.CHANGE_WAIT_MS ? 5 : ms, ...a);
for (const [name, run] of [['start', () => api.start('apps', ['x'])], ['plan', () => api.plan('apps', ['x'], 'secret')]]) {
  let err = null;
  try { await run(); } catch (e) { err = e; }
  check(`${name} that is never answered rejects with a reason`, err && err.timeout === true && /did not answer/.test(err.message) && /Jobs/.test(err.message));
}
// a caller that aborts keeps its AbortError (the create dialog's older question)
const ctl = new AbortController();
const pr = api.plan('apps', ['y'], 'secret', undefined, ctl.signal);
ctl.abort();
let e2 = null; try { await pr; } catch (e) { e2 = e; }
check('an abort by the caller is still an AbortError, not a timeout', e2 && e2.name === 'AbortError' && !e2.timeout);
globalThis.setTimeout = realSet;

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
