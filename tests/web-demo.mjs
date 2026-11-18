// Demo mode (web/demo/): every read of the READS allowlist in scripts/web-serve.py has a fixture, every fixture only names known reads,
// a plan opens, a start is refused, the five fixtures differ the way they promise.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { INDEX, page, search } from '../web/demo/docs.js';
import { baseReads, fixture, fixtureNames, read, answer, DEMO_NOTE } from '../web/demo/engine.js';

let bad = 0;
const check = (name, cond, extra = '') => { if (cond) console.log(`  ok    ${name}`); else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = readFileSync(join(root, 'scripts/web-serve.py'), 'utf8');
const block = src.slice(src.indexOf('\nREADS = {'), src.indexOf('\n}\n', src.indexOf('\nREADS = {')));
const reads = [...block.matchAll(/^    \(((?:"[^"]+",?\s*)+)\):\s*\{/gm)].map((m) => [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]));
check('found the READS allowlist', reads.length > 100, `(${reads.length})`);

const base = baseReads();
const missing = reads.filter((w) => !(w.join('/') in base)).map((w) => w.join(' '));
check('every allowlisted read has a fixture', missing.length === 0, missing.join(', '));
const known = new Set(reads.map((w) => w.join('/')));
// a key is a read, a read plus argument words ("ct/bindings/nextcloud") or a read plus a query ("pool/info?pool=bulk")
const isKnown = (k) => { const w = k.split('?')[0].split('/'); for (let n = w.length; n >= 1; n--) if (known.has(w.slice(0, n).join('/'))) return true; return false; };
const stray = Object.keys(base).filter((k) => !isKnown(k));
check('base.json names only allowlisted reads', stray.length === 0, stray.join(', '));

const names = fixtureNames();
check('the five fixtures exist', ['degraded', 'healthy', 'locked', 'one-pool', 'three-pools'].every((n) => names.includes(n)), names.join(','));
for (const n of names) {
  const f = fixture(n);
  const bads = Object.keys(JSON.parse(readFileSync(join(root, 'web/demo/fixtures', n + '.json'), 'utf8')).reads).filter((k) => !isKnown(k));
  check(`${n}: names only allowlisted reads`, bads.length === 0, bads.join(', '));
  const r = read(f, '/api/sys/pool/list');
  check(`${n}: pool list answers rows`, r.status === 200 && Array.isArray(r.body.rows));
}
for (const w of reads) {
  const r = answer('GET', '/api/sys/' + w.join('/'), {}, undefined, fixture('healthy'));
  if (r.status !== 200) check(`read ${w.join(' ')} answers`, false, String(r.status));
}
check('all reads answer 200', reads.every((w) => answer('GET', '/api/sys/' + w.join('/'), {}, undefined, fixture('healthy')).status === 200));

// Data, not just an answer: a read with an empty fixture is only allowed when it is listed in tests/web-demo-empty.txt (it prints nothing
// on a healthy server, or it needs an argument and has per-name keys); the number of non-empty reads per fixture may only go up (tests/web-demo-min.tsv).
const nonEmpty = (v) => (Array.isArray(v) ? v.length > 0 : typeof v === 'string' ? v.length > 0 : !!v && Object.keys(v).length > 0);
const noData = (r, k) => !nonEmpty(r[k]) && !Object.keys(r).some((o) => o !== k && (o.startsWith(k + '/') || o.startsWith(k + '?')) && nonEmpty(r[o]));
const lines = (f) => readFileSync(join(root, f), 'utf8').split(String.fromCharCode(10)).filter((l) => l && !l.startsWith('#'));
const mayBeEmpty = new Set(lines('tests/web-demo-empty.txt'));
const emptyNow = reads.map((w) => w.join('/')).filter((k) => noData(fixture('healthy').reads, k) && !mayBeEmpty.has(k));
check('healthy: no read is empty unless listed in tests/web-demo-empty.txt', emptyNow.length === 0, emptyNow.join(', '));
const staleEmpty = [...mayBeEmpty].filter((k) => !noData(fixture('healthy').reads, k));
check('tests/web-demo-empty.txt lists only reads that are empty', staleEmpty.length === 0, staleEmpty.join(', '));
const mins = Object.fromEntries(lines('tests/web-demo-min.tsv').map((l) => l.split(String.fromCharCode(9))));
for (const n of names) {
  const r = fixture(n).reads;
  const count = reads.map((w) => w.join('/')).filter((k) => !noData(r, k)).length;
  check(`${n}: ${count} reads with data (at least ${mins[n]})`, count >= Number(mins[n] ?? 1e9), 'add the fixture to tests/web-demo-min.tsv or fill the reads');
}

const pools = (n) => read(fixture(n), '/api/sys/pool/list').body.rows;
check('one-pool: one pool', pools('one-pool').length === 1);
check('three-pools: three pools, each with members', pools('three-pools').length === 3 && read(fixture('three-pools'), '/api/sys/pool/members', { pool: 'media' }).body.rows.length > 0);
check('degraded: a pool is degraded', pools('degraded').some((r) => r[3] === 'degraded'));
check('locked: hello says locked, pools locked', answer('GET', '/api/hello', {}, undefined, fixture('locked')).body.locked === true && pools('locked').every((r) => r[3] === 'locked'));
check('healthy: no pool is degraded', pools('healthy').every((r) => r[3] === 'online'));
check('unknown read: 404', read(fixture('healthy'), '/api/sys/nope/nothing').status === 404);

const fx = fixture('healthy');
const p = answer('POST', '/api/plan', {}, { area: 'pool', args: ['bulk', 'add'] }, fx);
check('a plan opens (status ok, with the demo note)', p.status === 200 && p.body.status === 'ok' && JSON.stringify(p.body.steps).includes(DEMO_NOTE));
const s = answer('POST', '/api/start', {}, { area: 'pool', args: ['bulk', 'add'], confirm: 'bulk' }, fx);
check('a start is refused with a note', s.body.status === 'refused' && s.body.reason === DEMO_NOTE);
check('any other change is refused', answer('POST', '/api/terminal', {}, { target: 'host' }, fx).status === 403);

const slugs = INDEX.langs.en.groups.flatMap((g) => g.pages.map((p) => p.slug));
check('every demo guide of the index has a page', slugs.length > 3 && slugs.every((x) => page(x)), slugs.join(','));
check('the demo guide search finds a guide', search('share').hits.length > 0);

process.exit(bad ? 1 : 0);
