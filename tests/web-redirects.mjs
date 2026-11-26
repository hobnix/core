// The old-address table (web/src/redirects.js, docs/PLAN-navigation.md step 7, D7): every address of the old tree (tests/fixtures/old-tree.json)
// ends on a page that exists now, a query and a node are kept, and a redirect never loops. Runs in plain node (no Svelte).
import { readFileSync } from 'node:fs';
import { redirect, moved, MOVED, MOVED_PREFIX, REMOVE_IN, MOVED_APPS, MOVED_APPS_PREFIX, APPS_REMOVE_IN } from '../web/src/redirects.js';
import { P, poolPath, dockerAppPagePath } from '../web/src/paths.js';

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
const families = ['/docs/', '/extensions/', '/settings/capabilities/'];
const hasPage = (inner, kind) => live[kind].has(inner) || (kind === 'main' && (families.some((f) => inner.startsWith(f)) || /^\/storage\/pools\/[^/]+$/.test(inner) || /^\/apps\/(instance|docker-app)\/[^/]+(\/[a-z]+)?$/.test(inner)));
const innerOf = (addr) => { const m = addr.split(/[?#]/)[0].match(/^\/node\/[^/]+(\/.*)?$/); return m ? (m[1] || '/') : addr.split(/[?#]/)[0]; };

const probe = (addr) => redirect(addr, L);

// 1. every old address lands on a live page, with and without the node in front, and settles in one step (no loop)
// a remote node's addresses carry its name (`other`), this server's have its own or none
const lands = (list, kind) => {
  const dead = [], loops = [];
  const node = kind === 'main' ? L : 'other';
  for (const p of list) {
    for (const addr of [...(kind === 'main' ? [p] : []), `/node/${node}${p === '/' ? '' : p}`]) {
      const to = redirect(addr, L) ?? `/node/${node}${addr.startsWith('/node/') ? addr.slice(`/node/${node}`.length) : (p === '/' ? '' : p)}`;
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

// both tables together: what redirect() follows
const ALL = { ...MOVED, ...MOVED_APPS };
const ALL_PREFIX = [...MOVED_APPS_PREFIX, ...MOVED_PREFIX];

// 2. the table itself: keys exist in paths.js, nothing is listed twice, every place of the old tree has a row
eq('every row names a place of paths.js', Object.entries(ALL).filter(([, v]) => !(Array.isArray(v) ? v[0] : v) || !P[Array.isArray(v) ? v[0] : v]).map(([k]) => k), []);
eq('every old path of the snapshot has a row', old.main.filter((p) => p !== '/' && !ALL[p]), []);
eq('no row sends an old path to another old path (a chain)', Object.entries(ALL).filter(([from, v]) => { const to = P[Array.isArray(v) ? v[0] : v]; return to !== from && ALL[to] && P[ALL[to]] !== to; }).map(([k]) => k), []);
eq('every prefix family of the snapshot has a rule', old.prefixed.filter((p) => !ALL_PREFIX.some(([f]) => p.startsWith(f))), []);

// 3. a node, a query and a hash are kept (the current table moves nothing yet, so the new address is the old one with the node in front)
const full = (from, tail) => `/node/${L}${moved(from)[0] === '/' ? '' : moved(from)[0]}${tail}`;
eq('a query is kept on every old path', Object.keys(ALL).filter((from) => !Array.isArray(ALL[from])).filter((from) => (probe(`${from}?sel=a&tab=b`) ?? full(from, '?sel=a&tab=b')) !== full(from, '?sel=a&tab=b')), []);
eq('a query and a hash are kept', Object.keys(ALL).filter((from) => !Array.isArray(ALL[from])).filter((from) => (probe(`${from}?sel=a#h`) ?? full(from, '?sel=a#h')) !== full(from, '?sel=a#h')), []);
eq('the node of an address is kept', Object.keys(ALL).filter((from) => !(probe(`/node/other${from}`) ?? `/node/other${moved(from)[0]}`).startsWith('/node/other')), []);
eq('an encoded node name stays encoded', (probe('/node/my%20box/storage/disks') ?? '/node/my%20box').startsWith('/node/my%20box'), true);

// 4. the moves themselves, through a fake table (the real one moves when paths.js does)
eq('a pool address maps through poolPath', moved('/storage/pools/tank'), [poolPath('tank'), {}]);
eq('a docker app address is not encoded twice', moved('/instances/docker/app/web%201'), [dockerAppPagePath('web 1', 'compose'), {}]);
eq('an address that is not old is left alone', moved('/somewhere/else'), ['/somewhere/else', {}]);
eq('a bare prefix is not a family member', moved('/docs/')[0], '/docs/');

// 4b. the Network tab Remote shares moved to Shares, view Remote (docs/PLAN-remote-shares.md D1; issue #1151)
eq('the old Remote tab address opens the Remote view', probe('/network?tab=remote'), `/node/${L}${P.shares}?view=remote`);
eq('the Remote tab redirect keeps a node and other query', probe(`/node/${L}/network?tab=remote&x=1`), `/node/${L}${P.shares}?x=1&view=remote`);
eq('another Network tab is not redirected to Shares', probe(`/node/${L}/network?tab=dns`), null);
eq('the Network overview is not redirected', probe(`/node/${L}/network`), null);

// 4c. 0.13: Instances and Docker became the one list Apps & VMs (docs/PLAN-workloads.md 3), the table of its old addresses
const at = (inner) => `/node/${L}${inner}`;
for (const [from, to] of [
  ['/instances', '/apps'],
  ['/instances?view=snapshots', '/apps?view=snapshots'],
  ['/instances/ct/jellyfin', '/apps/instance/jellyfin'],
  ['/instances/ct/jellyfin/config', '/apps/instance/jellyfin/config'],
  ['/instances/ct/a%20b/console?x=1#h', '/apps/instance/a%20b/console?x=1#h'],
  ['/instances/ct/docker', '/apps/instance/docker'],
  ['/instances/iso', '/apps/iso'],
  ['/instances/apps', '/apps/installed'],
  ['/apps/docker', '/apps?provider=docker'],
  ['/apps/docker?type=vm&q=x', '/apps?type=vm&q=x&provider=docker'],
  ['/instances/docker', '/apps?provider=docker'],
  ['/apps/docker/app/web%201', '/apps/docker-app/web%201/compose'],
  ['/apps/docker/app/arr?x=1', '/apps/docker-app/arr/compose?x=1'],
  ['/instances/docker/app/arr', '/apps/docker-app/arr/compose'],
  ['/apps/docker?sel=arr', '/apps/docker-app/arr'],
  ['/apps/docker?sel=arr&tab=logs', '/apps/docker-app/arr/logs'],
  ['/instances/docker?sel=a%20b&tab=compose&x=1', '/apps/docker-app/a%20b/compose?x=1'],
]) eq(`${from} -> ${to}`, [probe(from), probe(at(from)), probe(at(to))], [at(to), at(to), null]);
eq('the new addresses and the kept Docker ones stay', ['/apps', '/apps?provider=docker&type=vm&q=photo', '/apps/installed', '/apps/iso', '/apps/instance/docker', '/apps/docker-app/docker', '/apps/docker/new', '/apps/docker/wizard', '/apps/docker/registries'].map((a) => probe(at(a))), Array(9).fill(null));
eq("another node keeps its own /instances page", [probe('/node/other/instances'), probe('/node/other/instances?x=1')], [null, null]);

for (const p of ['/apps/instance', '/apps/instance/', '/apps/docker-app', '/apps/docker-app/']) eq(`${p} without a name -> the list`, redirect(`/node/${L}${p}`, L), `/node/${L}/apps`);
eq('a named object and an extension page stay', [redirect(`/node/${L}/apps/instance/a`, L), redirect(`/node/${L}/apps/jellyfin`, L)], [null, null]);

// 4d. the rows of 0.13 are a table of their own: they stay for 0.13 and 0.14 and do not go with the old table (REMOVE_IN)
const minor = (v) => Number(v.split('.')[1]);
eq('the 0.13 rows are removed in 0.15, two releases after they came', [APPS_REMOVE_IN, minor(APPS_REMOVE_IN) - 13], ['0.15', 2]);
eq('they outlive the old table', minor(APPS_REMOVE_IN) > minor(REMOVE_IN), true);
eq('the addresses that were current up to 0.12 are in the 0.13 table', [Object.keys(MOVED_APPS), MOVED_APPS_PREFIX.map(([f]) => f)], [['/instances', '/instances/iso', '/apps/docker'], ['/apps/docker/app/', '/instances/ct/']]);
eq('none of them is in the old table, so removing it takes none of them away', [...Object.keys(MOVED_APPS).filter((k) => k in MOVED), ...MOVED_APPS_PREFIX.filter(([f]) => MOVED_PREFIX.some(([o]) => o === f))], []);
eq('the code says both removal releases', ["REMOVE_IN = '0.13'", "APPS_REMOVE_IN = '0.15'", 'kept for 0.13 and 0.14'].filter((t) => !readFileSync(here('../web/src/redirects.js'), 'utf8').includes(t)), []);

// 5. D7: the table has a removal release, and docs/PLAN-navigation.md says so
eq('the removal release is set', /^\d+\.\d+$/.test(REMOVE_IN), true);
eq('the plan names the removal release', readFileSync(here('../docs/PLAN-navigation.md'), 'utf8').includes(`remove in ${REMOVE_IN}`), true);
eq('keyOf covers every row (sanity)', Object.values(ALL).filter((v) => !keyOf[P[Array.isArray(v) ? v[0] : v]]).length, 0);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
