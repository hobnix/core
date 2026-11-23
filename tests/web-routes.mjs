// The node addresses and the node-less fallback (web/src/redirects.js, pure) and the inner-path handling of readsFor, run with node.
import { redirect } from '../web/src/redirects.js';
import { readsFor, innerPath } from '../web/src/readsfor.js';
import { readFileSync } from 'node:fs';
import { P } from '../web/src/paths.js';
import { tree } from '../web/src/nav.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const L = 'homeserver';
eq('/ goes to the local node', redirect('/', L), '/node/homeserver');
eq('a node-less inner path gets the node', redirect('/instances', L), '/node/homeserver/instances');
eq('the query is kept', redirect('/instances?x=1', L), '/node/homeserver/instances?x=1');
eq('a query on a new address is kept as it is', redirect('/storage/disks?pool=bulk', L), '/node/homeserver/storage/disks?pool=bulk');
eq('the settings subpages of this server only get the node', [redirect('/settings', L), redirect('/settings/general', L)], ['/node/homeserver/settings', '/node/homeserver/settings/general']);
eq('a guide address', redirect('/docs/en/setup', L), '/node/homeserver/docs/en/setup');
eq('a node address is left alone', redirect('/node/homeserver/instances', L), null);
eq('the node root is left alone', redirect('/node/other', L), null);
eq('the pages of another node are left alone', [redirect('/node/edge1/settings', L), redirect('/node/proxyserver/mail', L)], [null, null]);
eq('without a local name nothing happens', redirect('/storage', ''), null);
// old inner paths are no longer special: they only get the node in front
eq('an old storage path only gets the node', redirect('/storage/bulk/disks', L), '/node/homeserver/storage/bulk/disks');
eq('an old path with the node in front is left alone', redirect('/node/homeserver/storage/unassigned', L), null);
eq('/proxy is no longer mapped to the proxyserver', [redirect('/proxy', L), redirect('/proxy/ports', L)], ['/node/homeserver/proxy', '/node/homeserver/proxy/ports']);
eq('the new Apps page prefetches the recipes', readsFor('/node/homeserver/apps/installed').includes('/api/sys/recipes/list'), true);
eq('the Apps page prefetches the versions', readsFor('/node/homeserver/apps/installed').includes('/api/sys/recipes/versions'), true);
eq('the old Apps address prefetches nothing', readsFor('/instances/apps'), []);


eq('inner path strips node and query', innerPath('/node/homeserver/storage/bulk/disks?pool=bulk'), '/storage/bulk/disks');
eq('inner path of a node root', innerPath('/node/homeserver'), '/');
eq('inner path of a plain path', innerPath('/instances'), '/instances');
eq('readsFor takes a node address', readsFor('/node/homeserver/instances'), readsFor('/instances'));
eq('readsFor takes a pool address', readsFor('/node/hs/storage/pools/fast').some((p) => p.endsWith('pool=fast')), true);

// every tree path has a route (the routes table is keyed by inner path), and the nav lines the shell relies on are there
const routes = readFileSync(new URL('../web/src/routes.js', import.meta.url), 'utf8');
const keyOf = Object.fromEntries(Object.entries(P).map(([k, v]) => [v, k]));
const treePaths = [];
(function walk(items) { for (const it of items) { if (it.path) treePaths.push(it.path); if (it.children) walk(it.children); } })(tree);
const missing = treePaths.filter((p) => p !== '/' && !routes.includes(`[P.${keyOf[p]}]:`));
eq('every tree path has a route', missing, []);

// the Live state page: a route, a nav entry behind the capability, and its one read only with live state on
eq('live-state has a route', routes.includes('[P.liveState]: LiveState'), true);
eq('the Live state nav entry carries the capability', tree[0].children.find((x) => x.path === P.system).children.find((x) => x.path === P.liveState).capability, 'live-state');
eq('the Live state read, live on', readsFor(P.liveState, [], true), ['/api/sys/live/inspect']);
eq('the Live state page reads nothing, live off', readsFor(P.liveState, [], false), []);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
