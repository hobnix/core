// Demo mode (web/demo/): every read of the READS allowlist in scripts/web-serve.py has a fixture, every fixture only names known reads,
// a plan opens, a start is refused, the five fixtures differ the way they promise.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
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
const stray = Object.keys(base).filter((k) => !known.has(k.split('?')[0]));
check('base.json names only allowlisted reads', stray.length === 0, stray.join(', '));

const names = fixtureNames();
check('the five fixtures exist', ['degraded', 'healthy', 'locked', 'one-pool', 'three-pools'].every((n) => names.includes(n)), names.join(','));
for (const n of names) {
  const f = fixture(n);
  const bads = Object.keys(JSON.parse(readFileSync(join(root, 'web/demo/fixtures', n + '.json'), 'utf8')).reads).filter((k) => !known.has(k.split('?')[0]));
  check(`${n}: names only allowlisted reads`, bads.length === 0, bads.join(', '));
  const r = read(f, '/api/sys/pool/list');
  check(`${n}: pool list answers rows`, r.status === 200 && Array.isArray(r.body.rows));
}
for (const w of reads) {
  const r = answer('GET', '/api/sys/' + w.join('/'), {}, undefined, fixture('healthy'));
  if (r.status !== 200) check(`read ${w.join(' ')} answers`, false, String(r.status));
}
check('all reads answer 200', reads.every((w) => answer('GET', '/api/sys/' + w.join('/'), {}, undefined, fixture('healthy')).status === 200));

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

process.exit(bad ? 1 : 0);
