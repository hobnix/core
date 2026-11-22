// The old-address table (web/src/redirects.js, docs/PLAN-navigation.md step 7, D7): every address of the old tree (tests/fixtures/old-tree.json)
// ends on a page that exists now, a query and a node are kept, and a redirect never loops. Runs in plain node (no Svelte).
import { readFileSync } from 'node:fs';
import { redirect, moved, MOVED, MOVED_PREFIX, REMOVE_IN } from '../web/src/redirects.js';
import { P, poolPath, dockerAppPath } from '../web/src/paths.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const here = (f) => new URL(f, import.meta.url);
const old = JSON.parse(readFileSync(here('fixtures/old-tree.json'), 'utf8'));
const routesSrc = readFileSync(here('../web/src/routes.js'), 'utf8');
const keyOf = Object.fromEntries(Object.entries(P).map(([k, v]) => [v, k]));
const L = 'homeserver';

// which inner paths have a page now: the main node by the `routes` table and the prefix families of pageFor, a remote node by its own table
const block = (name) => routesSrc.slice(routesSrc.indexOf(`const ${name} = {`), routesSrc.indexOf('};', routesSrc.indexOf(`const ${name} = {`)));
const keysIn = (src) => new Set([...src.matchAll(/\[P\.(\w+)\]:/g)].map((m) => P[m[1]]));
const live = {
  main: keysIn(block('routes')),
  peer: keysIn(block('peerRoutes')),
  edge: keysIn(block('edgeRoutes')),
};
live.vps = live.edge;
const families = ['/docs/', '/extensions/', '/settings/capabilities/', `${P.docker}/app/`];
const hasPage = (inner, kind) => live[kind].has(inner) || (kind === 'main' && (families.some((f) => inner.startsWith(f)) || /^\/storage\/pools\/[^/]+$/.test(inner)));
const innerOf = (addr) => { const m = addr.split(/[?#]/)[0].match(/^\/node\/[^/]+(\/.*)?$/); return m ? (m[1] || '/') : addr.split(/[?#]/)[0]; };

const probe = (addr) => redirect(addr, L);

// 1. every old address lands on a live page, with and without the node in front, and settles in one step (no loop)
const lands = (list, kind) => {
  const dead = [], loops = [];
  for (const p of list) {
    for (const addr of [p, `/node/${L}${p === '/' ? '' : p}`]) {
      const to = redirect(addr, L) ?? `/node/${L}${addr.startsWith('/node/') ? addr.slice(`/node/${L}`.length) : (p === '/' ? '' : p)}`;
      if (!hasPage(innerOf(to), kind)) dead.push(`${addr} -> ${to}`);
      if (redirect(to, L) !== null) loops.push(`${addr} -> ${to} -> ${redirect(to, L)}`);
    }
  }
  return [dead, loops];
};
for (const [name, list, kind] of [['main', old.main, 'main'], ['prefixed', old.prefixed, 'main'], ['withQuery', old.withQuery.map((a) => a.split('?')[0]), 'main'],
  ['peer', old.remote.peer, 'peer'], ['edge', old.remote.edge, 'edge'], ['vps', old.remote.vps, 'vps']]) {
  const [dead, loops] = lands(list, kind);
  eq(`every old ${name} address lands on a page that exists`, dead, []);
  eq(`no old ${name} address loops`, loops, []);
}

// 2. the table itself: keys exist in paths.js, nothing is listed twice, every place of the old tree has a row
eq('every row names a place of paths.js', Object.entries(MOVED).filter(([, v]) => !(Array.isArray(v) ? v[0] : v) || !P[Array.isArray(v) ? v[0] : v]).map(([k]) => k), []);
eq('every old path of the snapshot has a row', old.main.filter((p) => p !== '/' && !MOVED[p]), []);
eq('no row sends an old path to another old path (a chain)', Object.entries(MOVED).filter(([from, v]) => { const to = P[Array.isArray(v) ? v[0] : v]; return to !== from && MOVED[to] && P[MOVED[to]] !== to; }).map(([k]) => k), []);
eq('every prefix family of the snapshot has a rule', old.prefixed.filter((p) => !MOVED_PREFIX.some(([f]) => p.startsWith(f))), []);

// 3. a node, a query and a hash are kept (the current table moves nothing yet, so the new address is the old one with the node in front)
const full = (from, tail) => `/node/${L}${moved(from)[0] === '/' ? '' : moved(from)[0]}${tail}`;
eq('a query is kept on every old path', Object.keys(MOVED).filter((from) => !Array.isArray(MOVED[from])).filter((from) => (probe(`${from}?sel=a&tab=b`) ?? full(from, '?sel=a&tab=b')) !== full(from, '?sel=a&tab=b')), []);
eq('a query and a hash are kept', Object.keys(MOVED).filter((from) => !Array.isArray(MOVED[from])).filter((from) => (probe(`${from}?sel=a#h`) ?? full(from, '?sel=a#h')) !== full(from, '?sel=a#h')), []);
eq('the node of an address is kept', Object.keys(MOVED).filter((from) => !(probe(`/node/other${from}`) ?? `/node/other${moved(from)[0]}`).startsWith('/node/other')), []);
eq('an encoded node name stays encoded', (probe('/node/my%20box/storage/disks') ?? '/node/my%20box').startsWith('/node/my%20box'), true);

// 4. the moves themselves, through a fake table (the real one moves when paths.js does)
eq('a pool address maps through poolPath', moved('/storage/pools/tank'), [poolPath('tank'), {}]);
eq('a docker app address is not encoded twice', moved('/instances/docker/app/web%201'), [dockerAppPath('web 1'), {}]);
eq('an address that is not old is left alone', moved('/somewhere/else'), ['/somewhere/else', {}]);
eq('a bare prefix is not a family member', moved('/docs/')[0], '/docs/');

// 5. D7: the table has a removal release, and docs/PLAN-navigation.md says so
eq('the removal release is set', /^\d+\.\d+$/.test(REMOVE_IN), true);
eq('the plan names the removal release', readFileSync(here('../docs/PLAN-navigation.md'), 'utf8').includes(`remove in ${REMOVE_IN}`), true);
eq('keyOf covers every row (sanity)', Object.values(MOVED).filter((v) => !keyOf[P[Array.isArray(v) ? v[0] : v]]).length, 0);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
