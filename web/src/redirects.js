// Address without a node -> address with the local node, and an old inner path -> where that place lives now (pure, no Svelte: tests/web-routes.mjs
// and tests/web-redirects.mjs run it in node). routes.js re-exports it, route.svelte.js applies it with replaceState (Back keeps working).
//
// Every page lives under a node: /node/<name>/<inner path>. An address without a node ("/storage/pools", an entry address, `go('/x')`) gets the
// local node in front. An OLD inner path (the tree of 0.10, snapshot in tests/fixtures/old-tree.json) is mapped to the place's current path
// (docs/PLAN-navigation.md, step 7, D7): the table below says old path -> place KEY of paths.js, so the target is whatever paths.js says now.
// Step 8 moved the pages (the tree of D2 c, paths.js); a row whose key still has the old path does nothing.
// The old groups (Identity, Protection, Operations, Monitoring) end on the group that took most of their places (People, Backup, System).
// A page that merges into another one (Releases into Updates) writes [key, { tab }] instead of the key.
// D7: the table is kept for two releases (0.11 and 0.12) and removed in 0.13: REMOVE_IN is read by the test; delete the table, the
// fixture and the test together then.
// There are TWO tables, each with its own removal release:
//   MOVED, MOVED_PREFIX              the tree of 0.10 (above, REMOVE_IN)
//   MOVED_APPS, MOVED_APPS_PREFIX    the pages Instances and Docker, which became the one list Apps & VMs in 0.13 (docs/PLAN-workloads.md 3). These
//                                    addresses were current up to 0.12: kept for 0.13 and 0.14, removed in 0.15 (APPS_REMOVE_IN). They stay when
//                                    the first table goes.
// An older address of the first table ends on the new places too. A remote node is not touched at /instances: a peer's own read-only page is there.
import { P, poolPath, dockerAppPagePath, capabilityPath, extensionPath } from './paths.js';

export const REMOVE_IN = '0.13';          // MOVED and MOVED_PREFIX
export const APPS_REMOVE_IN = '0.15';     // MOVED_APPS and MOVED_APPS_PREFIX

// the node the VPS pages belong to (kind vps)
export const VPS_NODE = 'proxyserver';

const dec = (s) => { try { return decodeURIComponent(s); } catch { return s; } };
const composeTab = (rest) => dockerAppPagePath(dec(rest.split('/')[0]), 'compose');   // the old compose editor is the Compose tab of the app

// 0.13: the addresses of Instances and Docker (kept until APPS_REMOVE_IN)
export const MOVED_APPS = Object.freeze({
  '/instances':                   'appsGroup',
  '/instances/iso':               'iso',
  '/apps/docker':                 ['appsGroup', { provider: 'docker' }],
});
export const MOVED_APPS_PREFIX = Object.freeze([
  ['/apps/docker/app/', composeTab],
  ['/instances/ct/', (rest) => `${P.appsGroup}/instance/${rest}`],                      // name and tab stay as written
]);

// old inner path -> place key of paths.js (or [key, query])
export const MOVED = Object.freeze({
  '/storage':                     'storage',
  '/identity':                    'people',
  '/protection':                  'backupGroup',
  '/operations':                  'system',
  '/monitoring':                  'system',
  '/developer':                   'developer',
  '/settings':                    'settings',
  '/storage/pools':               'pools',
  '/storage/incident':            'incident',
  '/storage/disks':               'disks',
  '/storage/shares':              'shares',
  '/storage/files':               'files',
  '/storage/encryption':          'encryption',
  '/storage/vault':               'vault',
  '/instances/apps':              'apps',
  '/instances/services':          'services',
  '/instances/docker':            ['appsGroup', { provider: 'docker' }],
  '/instances/docker/registries': 'registries',
  '/instances/docker/new':        'dockerNew',
  '/instances/docker/wizard':     'dockerWizard',
  '/marketplace':                 'marketplace',
  '/marketplace/builder':         'builder',
  '/network':                     'network',
  '/identity/groups':             'groups',
  '/identity/users':              'users',
  '/identity/certificates':       'certificates',
  '/monitoring/hardware':         'hardware',
  '/monitoring/network-map':      'networkMap',
  '/monitoring/diagnostics':      'diagnostics',
  '/monitoring/live-state':       'liveState',
  '/monitoring/test-lab':         'testLab',
  '/protection/backup':           'backup',
  '/protection/expiry':           'expiry',
  '/operations/health':           'health',
  '/operations/notifications':    'notifications',
  '/operations/events':           'events',
  '/operations/whats-new':        'whatsNew',
  '/developer/components':        'components',
  '/docs':                        'docs',
  '/setup':                       'setup',
  '/setup/first-run':             'firstRun',
  '/nodes':                       'nodes',
  '/settings/general':            'settingsGeneral',
  '/settings/network':            'settingsNetwork',
  '/settings/storage':            'settingsStorage',
  '/settings/backups':            'settingsBackups',
  '/settings/access':             'settingsAccess',
  '/settings/updates':            'updates',
  '/settings/releases':           ['updates', { tab: 'releases' }],
  '/settings/capabilities':       'capabilities',
  '/settings/advanced':           'settingsAdvanced',
  '/health':                      'nodeHealth',
  '/mail':                        'mail',
  '/ports':                       'ports',
  '/watcher':                     'watcher',
  '/certificate':                 'certificate',
  '/tailscale':                   'tailscale',
});

// old address families with a name in them: old prefix -> the new path of the same object (`rest` = what follows the prefix, still encoded)
export const MOVED_PREFIX = Object.freeze([
  ['/storage/pools/', (rest) => poolPath(rest)],
  ['/instances/docker/app/', composeTab],
  ['/settings/capabilities/', (rest) => capabilityPath(rest)],
  ['/extensions/', (rest) => extensionPath(rest)],
  ['/docs/', (rest) => `${P.docs}/${rest}`],
]);

// Split "/path?query#hash" into [path, rest]
const cut = (a) => { const i = a.search(/[?#]/); return i < 0 ? [a, ''] : [a.slice(0, i), a.slice(i)]; };

// the two object families without a name show nothing (and would pass for the page of an extension or recipe): the list
const NAMELESS = /^\/apps\/(instance|docker-app)\/?$/;

// An old inner path -> [its current inner path, query to add] (the same path and {} when it is not old or did not move)
export function moved(inner) {
  if (NAMELESS.test(inner)) return [P.appsGroup, {}];
  const row = MOVED_APPS[inner] ?? MOVED[inner];
  if (row) { const [key, query] = Array.isArray(row) ? row : [row, {}]; return [P[key], query]; }
  for (const [from, to] of [...MOVED_APPS_PREFIX, ...MOVED_PREFIX]) if (inner.startsWith(from) && inner.length > from.length) return [to(inner.slice(from.length)), {}];
  return [inner, {}];
}

// The new address for `addr` (path + search), or null when it is fine as it is. `local` = the local node's name.
export function redirect(addr, local) {
  if (!local) return null;
  const [path, rest0] = cut(addr);
  let node, inner;
  const m = path.match(/^\/node\/([^/]+)(\/.*)?$/);
  if (m) { node = decodeURIComponent(m[1]); inner = m[2] || '/'; }
  else { inner = path || '/'; node = local; }
  // /instances of ANOTHER node is that peer's read-only page, which did not move
  const [to, add] = node !== local && inner === P.peerInstances ? [inner, {}] : moved(inner);
  let rest = rest0;
  // a quick look of the old Docker list (`?sel=<app>[&tab=compose|logs]`) is the page of that app
  if (add.provider === 'docker' && /^\?(.*&)?sel=[^&#]/.test(rest)) {
    const hash = rest.indexOf('#');
    const q = new URLSearchParams(hash < 0 ? rest.slice(1) : rest.slice(1, hash));
    const app = dockerAppPagePath(q.get('sel'), ['compose', 'logs'].includes(q.get('tab')) ? q.get('tab') : '');
    q.delete('sel'); q.delete('tab');
    return `/node/${encodeURIComponent(node)}${app}${q.toString() ? `?${q}` : ''}${hash < 0 ? '' : rest.slice(hash)}`;
  }
  // the Network tab Remote shares moved to the Shares page, view Remote (docs/PLAN-remote-shares.md D1)
  if (to === P.network && /^\?(.*&)?tab=remote(&|#|$)/.test(rest)) {
    const hash = rest.indexOf('#');
    const q = new URLSearchParams(hash < 0 ? rest.slice(1) : rest.slice(1, hash));
    q.delete('tab'); q.set('view', 'remote');
    return `/node/${encodeURIComponent(node)}${P.shares}?${q}${hash < 0 ? '' : rest.slice(hash)}`;
  }
  const extra = Object.keys(add);
  if (extra.length) {
    const hash = rest.indexOf('#');
    const q = new URLSearchParams(rest[0] === '?' ? (hash < 0 ? rest.slice(1) : rest.slice(1, hash)) : '');
    for (const k of extra) if (!q.has(k)) q.set(k, add[k]);
    rest = (q.toString() ? `?${q}` : '') + (hash < 0 ? '' : rest.slice(hash));
  }
  const out = `/node/${encodeURIComponent(node)}${to === '/' ? '' : to}${rest}`;
  return out === addr ? null : out;
}
