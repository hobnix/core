// The early reads after unlock and the one running request per address (web/src/api.js get, web/src/shell/Shell.svelte).
import { readFileSync } from 'node:fs';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

// a fake server: every request waits until the test answers it
const sent = [];
globalThis.fetch = (url) => new Promise((resolve, reject) => {
  sent.push({
    url,
    answer: (body, status = 200, headers = {}) => resolve({ ok: status < 300, status, headers: new Headers(headers), json: async () => body }),
    abort: () => { const e = new Error('aborted'); e.name = 'AbortError'; reject(e); },
  });
});
let now = 1000;
Date.now = () => now;
const api = await import('../web/src/api.js');
const P = '/api/sys/ct/list';
const settle = (p) => p.then((value) => ({ value }), (error) => ({ error }));

{
  const a = api.get(P), b = api.get(P);
  check('a second read of a running address joins it', sent.length === 1);
  const other = api.get('/api/sys/shares/overview');
  check('another address is its own request', sent.length === 2);
  sent[0].answer({ n: 1 }, 200, { 'X-HS-Age': '7', 'X-HS-Status': 'stale' });
  sent[1].answer({ n: 0 });
  const [x, y] = await Promise.all([a, b, other]);
  check('both callers get the answer', x.n === 1 && y.n === 1);
  check('age and state of the joined read are kept', api.ageOf(P) === 7 && api.stateOf(P)?.status === 'stale');
  const c = api.get(P);
  check('a finished request is not kept', sent.length === 3);
  sent[2].answer({ n: 2 });
  await c;
}
sent.length = 0;
{
  const old = api.get(P);
  const fresh = api.get(P, true);
  check('a forced refresh never joins an older request', sent.length === 2 && sent[1].url === `${P}?fresh=1`);
  const after = api.get(P);
  check('nobody joins the older request after a forced refresh', sent.length === 3);
  const again = api.get(P, true);
  check('a second forced refresh is its own request too', sent.length === 4);
  const joined = api.get(P);
  check('a forced refresh also ends the sharing of the read before it', sent.length === 5);
  sent[0].answer({ n: 'old' });
  await old;
  const late = api.get(P);
  check('the end of an older request leaves the newer one shared', sent.length === 5);
  sent.slice(1).forEach((r) => r.answer({ n: 'new' }));
  await Promise.all([fresh, after, again, joined, late]);
}
for (const [name, fail] of [['failed', (r) => r.answer({ error: 'boom' }, 500)], ['aborted', (r) => r.abort()]]) {
  sent.length = 0;
  const a = settle(api.get(P)), b = settle(api.get(P));
  fail(sent[0]);
  const [x, y] = await Promise.all([a, b]);
  check(`a ${name} request fails for those who waited`, !!x.error && !!y.error);
  const c = api.get(P);
  check(`a ${name} request does not poison the next caller`, sent.length === 2);
  sent[1].answer({ n: 3 });
  check(`the read after a ${name} one succeeds`, (await c).n === 3);
}
sent.length = 0;
{
  const a = api.get(P);
  now += api.JOIN_MS;
  const b = api.get(P);
  check('a request that is too old is not joined', sent.length === 2);
  api.forgetReads();
  const c = api.get(P);
  check('after forgetReads a running request is not joined', sent.length === 3);
  const s = api.start('system', ['update']);
  const d = api.get(P);
  check('a start of a change ends the sharing of what runs', sent.length === 5);
  sent[3].answer({ status: 'started' });
  await s;
  const e = api.get(P);
  check('so does the answer of the start', sent.length === 6);
  sent.forEach((r, i) => { if (i !== 3) r.answer({}); });
  await Promise.all([a, b, c, d, e]);
}

const src = (f) => readFileSync(new URL(`../web/src/${f}`, import.meta.url), 'utf8');
const shell = src('shell/Shell.svelte');
const at = shell.indexOf('touch(fieldReads(ui.role, ui.features.capabilities))');
check('the shell asks the picker reads right after unlock, before the idle prefetch', at > 0 && at < shell.indexOf('prefetch([...new Set('));
check('not while locked, and not before the lock state is known', /lockGate\(clearPollCache, \(\) => \{/.test(shell.slice(0, at)) && /gate\(!!deck\.data, locked\)/.test(shell));
const livejs = src('live.svelte.js');
check('events of the live stream end the sharing', /resyncAll\(\) \{ forgetReads\(\);/.test(livejs) && /forgetReads\(\); live\.gen\[m\.topic\]/.test(livejs) && /live\.lastId = m\.id;\s+forgetReads\(\);/.test(livejs));
check('a job that ended and a refresh end the sharing', /endToast\(t\) \{\s+forgetReads\(\);/.test(src('ui.svelte.js')) && /forgetReads\(\);[^\n]*\n\s+sync\.n\+\+/.test(src('data.svelte.js')));

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
