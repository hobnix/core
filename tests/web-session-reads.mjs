// The read cache across a sign-out and a lock (web/src/data.svelte.js clearPollCache, web/src/lockgate.js). The real data.svelte.js runs in node: the two
// runes it uses are stand-ins here (a state is the plain object, an effect runs once).
let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

const cleanups = [];
globalThis.$state = (v) => v;
globalThis.$effect = (f) => { cleanups.push(f()); };
const idle = [];
globalThis.window = { requestIdleCallback: (f) => idle.push(f) };
const sent = [];
globalThis.fetch = (url) => new Promise((resolve) => {
  const reply = (status, body) => resolve({ ok: status < 300, status, headers: new Headers(), json: async () => body });
  sent.push({ url, answer: (body) => reply(200, body), fail: () => reply(500, {}) });
});
const tick = () => new Promise((r) => setTimeout(r, 0));
const runIdle = async () => { while (idle.length) { idle.shift()(); await tick(); } };

const data = await import('../web/src/data.svelte.js');
const P = '/api/sys/users/list';
// what the cache holds for P: a poll shows a cached answer at once, before its own read is answered (which then fails, so the probe keeps nothing)
const cached = async () => {
  const n = sent.length;
  const st = data.poll(P, 60000);
  const seen = st.data;
  cleanups.pop()?.();
  for (const r of sent.slice(n)) r.fail();
  await tick();
  return seen;
};
const empty = async () => { await tick(); data.clearPollCache(); sent.length = 0; idle.length = 0; };

const ways = {
  touch: () => { data.touch([P]); },
  prefetch: () => { data.prefetch([P]); idle.shift()(); },
  refresh: () => { data.refresh([P]); },
  poll: () => { data.poll(P, 60000); },
};
for (const [name, ask] of Object.entries(ways)) {
  await empty();
  ask();
  sent[0].answer({ who: 'same' });
  await tick();
  cleanups.splice(0).forEach((c) => c?.());
  check(`${name}: an answer of this session is kept`, (await cached())?.who === 'same');

  await empty();
  ask();
  const old = sent[0];
  data.clearPollCache();       // sign-out
  cleanups.splice(0).forEach((c) => c?.());
  old.answer({ who: 'previous' });
  await tick();
  const got = await cached();
  check(`${name}: an answer that arrives after sign-out is not kept`, got == null, JSON.stringify(got));
}

await empty();
data.prefetch(['/api/sys/a', '/api/sys/b']);
idle.shift()();
data.clearPollCache();
sent[0].answer({});
await tick();
await runIdle();
check('an idle prefetch stops when its session is over', sent.length === 1, String(sent.length));

await empty();
data.touch([P]);
data.clearPollCache();
data.touch([P]);
check('after clearPollCache a read that still runs is not joined', sent.length === 2, String(sent.length));
sent.forEach((r) => r.answer({}));

// lock, then unlock: the early reads run again and nothing from before the lock is left
const { lockGate } = await import('../web/src/lockgate.js');
await empty();
let unlocks = 0, locks = 0;
const gate = lockGate(() => { locks++; data.clearPollCache(); }, () => { unlocks++; data.prefetch([P]); });
gate(false, false);
check('nothing happens before the lock state is known', unlocks === 0 && locks === 0);
gate(true, false);
gate(true, false);
check('the first open answer starts the reads once', unlocks === 1);
await runIdle();
sent[0].answer({ who: 'before the lock' });
await tick();
await runIdle();
check('the first unlock keeps its answer', (await cached())?.who === 'before the lock');
sent.length = 0;
gate(true, true);
gate(true, true);
check('a lock drops the cache once', locks === 1 && (await cached()) == null);
sent.length = 0;
gate(true, false);
check('the second unlock starts the reads again', unlocks === 2);
await runIdle();
check('and asks the server anew', sent.some((r) => r.url === P), JSON.stringify(sent.map((r) => r.url)));
sent.forEach((r) => r.answer({}));

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
