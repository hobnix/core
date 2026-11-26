// The resource tree (left). `storage: true` = needs the encrypted storage, so it dims while that is locked.
// A page that is not built yet shows a placeholder (shell/Placeholder.svelte) with its title from here.
import { P, poolPath, extensionPath } from './paths.js';
import { objectOf, objects } from './objects.js';
// the capability that shows the Developer group
export const DEVELOPER_CAP = 'testlab';
export const tree = [
  {
    label: 'homeserver', icon: 'hard-drives', path: P.summary, node: true,
    children: [
      {
        label: 'Storage', icon: 'database', path: P.storage, storage: true,
        children: [
          // the pools of this server are added under it at render time (nodeItems poolRows). Incident is an action on Pools and on System, not an entry.
          { label: 'Pools', icon: 'cylinder', path: P.pools, storage: true },
          { label: 'Disks', icon: 'hard-drive', path: P.disks, prefix: true, storage: true },
          { label: 'Shares', icon: 'folders', path: P.shares, storage: true },
          { label: 'Files', icon: 'folder-open', path: P.files, storage: true },
          { label: 'Encryption', icon: 'lock-key', path: P.encryption },
          { label: 'Vault', icon: 'vault', path: P.vault },
        ],
      },
      // Apps & VMs is a place itself: the one list of containers, VMs and Docker apps (docs/PLAN-workloads.md 3)
      { label: 'Apps & VMs', icon: 'cube', path: P.appsGroup, storage: true, children: [
        { label: 'App catalog', icon: 'package', path: P.apps, storage: true },
        { label: 'Marketplace', icon: 'storefront', path: P.marketplace, prefix: true },
        { label: 'Docker registries', icon: 'key', path: P.registries, capability: 'docker' },
        { label: 'ISO images', icon: 'disc', path: P.iso, storage: true, capability: 'incus' },
      ] },
      { label: 'Network', icon: 'network', path: P.network, children: [
        { label: 'Services', icon: 'arrows-split', path: P.services, capability: 'reverse-proxy' },
        { label: 'Network map', icon: 'share-network', path: P.networkMap },
      ] },
      // People is no longer hidden by the capability `ad`: local users exist without it (only the directory parts depend on it)
      { label: 'People', icon: 'users-three', path: P.people, storage: true, children: [
        { label: 'Users', icon: 'user', path: P.users, storage: true },
        { label: 'Groups', icon: 'users-four', path: P.groups, storage: true },
      ] },
      { label: 'System', icon: 'heartbeat', path: P.system, children: [
        { label: 'Health', icon: 'heartbeat', path: P.health },
        { label: 'Events', icon: 'list-bullets', path: P.events },
        { label: 'Notifications', icon: 'bell', path: P.notifications, capability: 'notifications' },
        { label: 'Hardware', icon: 'cpu', path: P.hardware },
        { label: 'Updates', icon: 'arrow-circle-up', path: P.updates },
        { label: 'Certificates', icon: 'certificate', path: P.certificates, storage: true },
        { label: 'Diagnostics', icon: 'stethoscope', path: P.diagnostics },
        { label: 'Live state', icon: 'pulse', path: P.liveState, capability: 'live-state' },
        { label: 'Test-lab', icon: 'flask', path: P.testLab, capability: 'testlab' },
      ] },
      { label: 'Backup', icon: 'cloud-arrow-up', path: P.backupGroup, children: [
        { label: 'Backup', icon: 'cloud-arrow-up', path: P.backup },
        { label: 'Expiry dates', icon: 'calendar-x', path: P.expiry },
      ] },
      { label: 'Settings', icon: 'sliders', path: P.settings, children: [
        { label: 'General', icon: 'sliders-horizontal', path: P.settingsGeneral },
        { label: 'Network and DNS', icon: 'network', path: P.settingsNetwork },
        { label: 'Storage', icon: 'database', path: P.settingsStorage, capability: 'storage' },
        { label: 'Backups', icon: 'cloud-arrow-up', path: P.settingsBackups, capability: 'backup' },
        { label: 'Users and access', icon: 'users-three', path: P.settingsAccess },
        // one child per capability that is on and has a settings page of its own is added at render time (nodeItems capItems)
        { label: 'Capabilities', icon: 'puzzle-piece', path: P.capabilities, prefix: true },
        { label: 'Extensions', icon: 'plug', path: P.settingsExtensions },
        { label: 'Advanced', icon: 'wrench', path: P.settingsAdvanced },
      ] },
      // Developer is not a group of the design: it shows at the bottom only while its capability is on (the test-lab capability is the developer one)
      { label: 'Developer', icon: 'wrench', path: P.developer, capability: DEVELOPER_CAP, children: [
        { label: 'Components', icon: 'squares-four', path: P.components },
      ] },
    ],
  },
  {
    label: 'proxyserver', icon: 'globe-hemisphere-west', path: P.summary, node: true, gap: true, capability: 'vps',
    children: [
      { label: 'Mail entry', icon: 'envelope-simple', path: P.mail },
      { label: 'Ports', icon: 'plugs', path: P.ports },
      { label: 'Outside watcher', icon: 'binoculars', path: P.watcher },
      { label: 'Certificate', icon: 'certificate', path: P.certificate },
      { label: 'Tailscale', icon: 'plugs-connected', path: P.tailscale },
      { label: 'Settings', icon: 'sliders', path: P.settings },
    ],
  },
];

// Places that are not rows of the tree but have a title and the flags of a place: Docs and What's new are in the top bar, Setup is a banner on Summary,
// Incident is an action on Pools and System, Nodes is the SERVERS header of the tree. Search lists them, titleOf/itemOf know them.
export const offTree = [
  { label: 'Docs', icon: 'book-open', path: P.docs, prefix: true, capability: 'docs' },
  { label: "What's new", icon: 'sparkle', path: P.whatsNew },
  { label: 'Incident', icon: 'first-aid-kit', path: P.incident, storage: true },
  { label: 'Setup', icon: 'list-checks', path: P.setup },
  { label: 'Servers', icon: 'hard-drives', path: P.nodes },
];

// The tree without the parts of capabilities that are off (docs/PLAN-modular-core.md step 3). `caps` is the list from the session answer
// (ui.features.capabilities); null/undefined = the server did not say (an older one): show everything. An item with a
// `capability` is shown only while that name is in the list; a page the user opens by its address still works.
export function visible(items, caps) {
  if (!Array.isArray(caps)) return items;
  return items.filter((n) => !n.capability || caps.includes(n.capability));
}

// ── nodes as the roots of the tree ─────────────────────────────────────────────────────────────────
// The paths above are INNER paths: the page of a node is /node/<name><path> (route.svelte.js). The main node (this server) gets the long tree. A
// REMOTE node's tree is built from the capabilities its status document reports (`capabilities`, a list of names): Summary and Health always, then
// `storage` -> Storage, `incus` -> Instances (its own address /instances), `backup` -> Backup (all read only, summaries of the document), and for an edge or vps node the
// proxyserver pages (Mail entry, Ports, Outside watcher, Certificate, Tailscale, Settings). `caps` null/undefined = the node did not say: a vps node
// shows all its pages (an old document), any other node only Summary and Health.
export const mainTree = tree[0].children;
// the health page of a remote node is the "System" entry of the new group names (D8 (a)); its address stays /node/<name>/health
const HEALTH = { label: 'System', icon: 'heartbeat', path: P.nodeHealth };
const edgeItems = tree[1].children;
// page -> the edge capability that brings it (a vps node has no list: every page)
const EDGE_NEEDS = { [P.mail]: 'edge-mail', [P.certificate]: 'edge-mail', [P.ports]: 'edge-ports', [P.watcher]: 'edge-watcher' };
const peerItems = [
  { label: 'Storage', icon: 'database', path: P.storage, capability: 'storage' },
  { label: 'Instances', icon: 'cube', path: P.peerInstances, capability: 'incus' },
  { label: 'Backup', icon: 'cloud-arrow-up', path: P.backup, capability: 'backup' },
];
export const remoteTree = [HEALTH];
export const vpsTree = [HEALTH, ...edgeItems];

// kind: 'main' | 'vps' | 'edge' | 'peer' (hs sys node list); caps: the capability names of the node (main: the session answer, remote: its status document)
// capItems: tree items for the capabilities that have a settings page (settings/layout.js capEntries); they go under Settings > Capabilities.
// The tree is copied, never changed. (nav.js stays free of the generated JSON: tests import it in plain node.)
// poolRows: the pool rows of the server (pools.svelte.js, [{name, role, ...}]); they become the children of Storage > Pools.
// Every page is in the tree for every role (a page above the role is greyed by the row, roles.js lockedWhy).
export function nodeItems(kind, caps, exts, capItems = [], poolRows = []) {
  if (kind === 'main') {
    return withExtItems(withPoolItems(withCapItems(visible(mainTree, caps), capItems), poolRows), exts);
  }
  if (kind === 'vps' || kind === 'edge') {
    const have = Array.isArray(caps) ? caps : null;
    return [HEALTH, ...edgeItems.filter((i) => kind === 'vps' && !have ? true : !EDGE_NEEDS[i.path] || (have ?? []).includes(EDGE_NEEDS[i.path]))];
  }
  return [HEALTH, ...(Array.isArray(caps) ? peerItems.filter((i) => caps.includes(i.capability)) : [])];
}

// the icon of a pool by role: the apps pool is the fast one
export const poolIcon = (role) => (role === 'apps' ? 'lightning' : 'cylinder');

export function poolItems(poolRows) {
  return (poolRows ?? []).map((r) => ({ label: r.name, icon: poolIcon(r.role), path: poolPath(r.name), storage: true }));
}

function withPoolItems(items, poolRows) {
  if (!poolRows?.length) return items;
  const kids = poolItems(poolRows);
  return items.map((it) => it.path === P.storage && it.children
    ? { ...it, children: it.children.map((c) => (c.path === P.pools ? { ...c, children: kids } : c)) }
    : it);
}

function withCapItems(items, capItems) {
  if (!capItems.length) return items;
  return items.map((it) => it.path === P.settings && it.children
    ? { ...it, children: it.children.map((c) => (c.path === P.capabilities ? { ...c, children: capItems } : c)) }
    : it);
}

// Extension pages: one page per extension package that is on AND declares a web page (ui.features.extensions, the manifests' [web.page]). A page
// goes into the group its `group` key names (storage, instances, apps, network, people, system, backup, settings; default apps, an unknown name
// too; `instances` and `apps` are both Apps & VMs), after the places of the core. Nothing is added while there is no such package. The pages are /extensions/<name> (pages/Extension.svelte).
export const EXT_GROUPS = Object.freeze({ storage: P.storage, instances: P.appsGroup, apps: P.appsGroup, network: P.network, people: P.people, system: P.system, backup: P.backupGroup, settings: P.settings });
export const extGroup = (e) => EXT_GROUPS[e?.group] ?? P.appsGroup;
// Order inside a group: the places of the core keep their order; package places follow, alphabetically by title. A package that says `after`
// (the last word of a place's path, its label in lower case, or another package's name) sits right behind that place instead; an `after` that
// matches nothing is ignored. Never a third level: a package with several views is one place with tabs.
const placeKey = (c) => String(c.path ?? '').split('/').pop();
export function placeExt(children, exts) {
  const byTitle = [...exts].sort((a, b) => String(a.title).localeCompare(String(b.title)) || String(a.name).localeCompare(String(b.name)));
  const item = (e) => ({ label: e.title, icon: e.icon || 'puzzle-piece', path: extensionPath(e.name), ...(e.state ? { state: true } : {}) });
  const anchors = (c, e) => c.path === extensionPath(e.name) ? [] : [placeKey(c), String(c.label).toLowerCase()];
  const names = new Set(byTitle.map((e) => e.name));
  const behind = (key) => byTitle.filter((e) => e.after === key && e.after !== e.name);
  const out = [];
  const put = (e, seen) => { if (seen.has(e.name)) return; seen.add(e.name); out.push(item(e)); behind(e.name).forEach((x) => put(x, seen)); };
  const seen = new Set();
  for (const c of children) {
    out.push(c);
    for (const e of byTitle) if (!seen.has(e.name) && e.after && !names.has(e.after) && anchors(c, e).includes(e.after)) put(e, seen);
  }
  // the rest: no `after`, or one that matches no place; those that hang behind another package follow it
  for (const e of byTitle) if (!seen.has(e.name) && !(e.after && names.has(e.after) && e.after !== e.name)) put(e, seen);
  for (const e of byTitle) put(e, seen);
  return out;
}
export function withExtItems(items, exts) {
  if (!Array.isArray(exts) || !exts.length) return items;
  return items.map((it) => {
    const mine = exts.filter((e) => e.kind !== 'recipe' && extGroup(e) === it.path);      // a recipe's page is opened from its row, it has no place in the tree
    return mine.length ? { ...it, children: placeExt(it.children ?? [], mine) } : it;
  });
}

// the icon of a node root by kind
export const nodeIcon = { main: 'hard-drives', vps: 'globe-hemisphere-west', edge: 'globe-hemisphere-west', peer: 'house-line' };

// the tree item for an inner path (null if none); the shell reads its `storage` and `capability` flags for the page states
export function itemOf(path) {
  const walk = (items) => {
    for (const it of items) {
      if (it.path === path || (it.prefix && path.startsWith(it.path + '/'))) return it;
      if (it.children) { const r = walk(it.children); if (r) return r; }
    }
    return null;
  };
  // an object page (a pool: /storage/pools/<name>) is a page of the item of its list
  const obj = objectOf(path);
  return walk(tree) ?? walk(offTree) ?? (obj ? itemOf(objects[obj.kind].list) : null);
}

export function titleOf(path) {
  const walk = (items, trail) => {
    for (const it of items) {
      const t = [...trail, it.label];
      if (it.path === path) return t;
      if (it.children) { const r = walk(it.children, t); if (r) return r; }
    }
    return null;
  };
  const obj = objectOf(path);
  return walk(tree, []) ?? walk(offTree, []) ?? (obj ? [...(titleOf(objects[obj.kind].list) ?? []), obj.id] : null);
}

// ── the trail and the marks of the tree (docs/PLAN-workloads.md 1 and 2: #1292, #1293) ─────────────
// the items from the top of `items` down to the one `match` accepts, or null
function chainTo(items, match) {
  for (const it of items) {
    if (match(it)) return [it];
    const r = it.children && chainTo(it.children, match);
    if (r) return [it, ...r];
  }
  return null;
}
const under = (path, base) => path.startsWith(base + '/');

// The breadcrumb of an INNER path: [{ label, path }], the PARENTS of the page only: the server, the groups, the lists and, on an object page,
// everything above the object. `server` is the node's name, `items` its tree (nodeItems; default: the static tree of this server). Summary has no
// parent ([]); a place of `offTree` has the server and nothing more; a page that is no row hangs under the deepest row its address starts with.
export function trailOf(path, { server = tree[0].label, items = mainTree } = {}) {
  if (path === P.summary) return [];
  const top = [{ label: server, path: P.summary }];
  const trailTo = (chain) => [...top, ...(chain ?? []).map((it) => ({ label: it.label, path: it.path }))];
  const obj = objectOf(path);
  const list = obj && chainTo(items, (it) => it.path === objects[obj.kind].list);
  if (list) return trailTo(list);
  const exact = chainTo(items, (it) => it.path === path);
  if (exact) return trailTo(exact.slice(0, -1));
  if (offTree.some((it) => it.path === path || (it.prefix && under(path, it.path)))) return top;
  let best = null;
  const walk = (rows, chain) => {
    for (const it of rows) {
      const next = [...chain, it];
      if (it.path && under(path, it.path) && it.path.length > (best?.at(-1).path.length ?? 0)) best = next;
      if (it.children) walk(it.children, next);
    }
  };
  walk(items, []);
  return trailTo(best);
}

// The trail as the shell shows it. `node` is the node on screen ({ name, kind, caps, local }): a remote one has its own name and tree. This server
// (also without a node) is named `local` and its tree has the package pages `exts`.
export function nodeTrail(path, node, local, exts) {
  if (node && !node.local) return trailOf(path, { server: node.name, items: nodeItems(node.kind, node.caps) });
  return trailOf(path, { server: local, items: withExtItems(mainTree, exts) });
}

// is `rowPath` the row of the page `path`? The same address, or the same object (a tab of it has no row of its own)
export function isRowOf(rowPath, path) {
  if (!rowPath) return false;
  if (rowPath === path) return true;
  const a = objectOf(rowPath), b = objectOf(path);
  return !!a && !!b && a.kind === b.kind && a.id === b.id;
}

// how a row shows where you are: 'current' (the open page), 'parent' (the last of the trail), 'above' (every row over that), '' (not on the way)
export function rowMark(rowPath, path, trail) {
  if (isRowOf(rowPath, path)) return 'current';
  const i = trail.findIndex((c) => c.path === rowPath);
  return i < 0 ? '' : i === trail.length - 1 ? 'parent' : 'above';
}

// An object page whose object has no row of its own gets a temporary one under the row of its list (`temp: true`, gone when the page is left).
// An object with a permanent row (a pool) gets none. The tree is copied, never changed.
export function withObjectRow(items, path) {
  const obj = objectOf(path);
  if (!obj || chainTo(items, (it) => isRowOf(it.path, path))) return items;
  const def = objects[obj.kind];
  const row = { label: obj.id, path: def.base + path.slice(def.base.length).split('/')[0], temp: true };
  const walk = (rows) => rows.map((it) => {
    if (it.path === def.list) return { ...it, children: [...(it.children ?? []), { ...row, icon: it.icon, ...(it.storage ? { storage: true } : {}) }] };
    return it.children ? { ...it, children: walk(it.children) } : it;
  });
  return walk(items);
}
