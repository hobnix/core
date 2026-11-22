// A browser keeps at most 6 connections per server (HTTP/1.1). Hover and focus prefetch of plans (prefetchPlan) must never fill them: a slow plan
// (the server under load, `hs sys system plan update` takes a minute) would hold them all, and the Start of the click waits in the browser queue,
// never reaches the server and leaves its toast spinning. This fake browser has 6 slots and a server that never answers a plan.
let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

const SLOTS = 6;
let inflight = 0, peak = 0, startSent = false;
const waiting = [];     // requests the fake browser holds back because all slots are taken
const send = (url, init, resolve, reject) => {
  inflight++; peak = Math.max(peak, inflight);
  const done = () => { inflight--; const w = waiting.shift(); if (w) send(...w); };
  if (url === '/api/start') { startSent = true; done(); return resolve({ ok: true, headers: new Headers(), json: async () => ({ status: 'started', unit: 'job-1' }) }); }
  init.signal?.addEventListener('abort', () => { done(); const e = new Error('aborted'); e.name = 'AbortError'; reject(e); });   // a plan is never answered
};
globalThis.fetch = (url, init) => new Promise((resolve, reject) => { if (inflight >= SLOTS) waiting.push([url, init, resolve, reject]); else send(url, init, resolve, reject); });
let now = 1000;
Date.now = () => now;

const api = await import('../web/src/api.js');
for (let i = 0; i < 10; i++) api.prefetchPlan('backup', ['verify' + i]).catch(() => {});     // the pointer crosses ten buttons
check('hover prefetch keeps most of the connections free', peak <= 2);
now += 40000;     // the old answer is past its 30 s: the next hover would ask again while the first is still running
for (let i = 0; i < 10; i++) api.prefetchPlan('backup', ['verify' + i]).catch(() => {});
check('a prefetch that still runs is not asked a second time', peak <= 2);
const r = await Promise.race([api.start('system', ['update']), new Promise((res) => setTimeout(() => res('queued'), 200))]);
check('the start of the click goes out at once and is answered', startSent && r && r.unit === 'job-1');

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
