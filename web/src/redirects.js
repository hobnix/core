// Address without a node -> address with the local node, and an old inner path -> where that place lives now (pure, no Svelte: tests/web-routes.mjs
// and tests/web-redirects.mjs run it in node). routes.js re-exports it, route.svelte.js applies it with replaceState (Back keeps working).
//
// Every page lives under a node: /node/<name>/<inner path>. An address without a node ("/storage/pools", an entry address, `go('/x')`) gets the
// local node in front. An OLD inner path (the tree of 0.10, snapshot in tests/fixtures/old-tree.json) is mapped to the place's current path
// (docs/PLAN-navigation.md, step 7, D7): the table below says old path -> place KEY of paths.js, so the target is whatever paths.js says now.
// While the tree has not moved a key's path is the old path itself and the row does nothing; the step that moves a page changes paths.js only.
// A page that merges into another one (Releases into Updates) writes [key, { tab }] instead of the key.
// D7: the table is kept for two releases (0.11 and 0.12) and removed in 0.13: REMOVE_IN is read by the test; delete the table, the
// fixture and the test together then.
import { P, poolPath, dockerAppPath, capabilityPath, extensionPath } from './paths.js';

export const REMOVE_IN = '0.13';

// the node the VPS pages belong to (kind vps)
export const VPS_NODE = 'proxyserver';

// old inner path -> place key of paths.js (or [key, query])
export const MOVED = Object.freeze({
  '/storage':                     'storage',
  '/instances':                   'instances',
  '/identity':                    'identity',
  '/protection':                  'protection',
  '/operations':                  'operations',
  '/monitoring':                  'monitoring',
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
  '/instances/iso':               'iso',
  '/instances/services':          'services',
  '/instances/docker':            'docker',
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
  '/settings/updates':            'settingsUpdates',
  '/settings/releases':           'releases',
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
const dec = (s) => { try { return decodeURIComponent(s); } catch { return s; } };
export const MOVED_PREFIX = Object.freeze([
  ['/storage/pools/', (rest) => poolPath(rest)],
  ['/instances/docker/app/', (rest) => dockerAppPath(dec(rest))],
  ['/settings/capabilities/', (rest) => capabilityPath(rest)],
  ['/extensions/', (rest) => extensionPath(rest)],
  ['/docs/', (rest) => `${P.docs}/${rest}`],
]);

// Split "/path?query#hash" into [path, rest]
const cut = (a) => { const i = a.search(/[?#]/); return i < 0 ? [a, ''] : [a.slice(0, i), a.slice(i)]; };

// An old inner path -> [its current inner path, query to add] (the same path and {} when it is not old or did not move)
export function moved(inner) {
  const row = MOVED[inner];
  if (row) { const [key, query] = Array.isArray(row) ? row : [row, {}]; return [P[key], query]; }
  for (const [from, to] of MOVED_PREFIX) if (inner.startsWith(from) && inner.length > from.length) return [to(inner.slice(from.length)), {}];
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
  const [to, add] = moved(inner);
  let rest = rest0;
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
