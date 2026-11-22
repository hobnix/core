// What a page reads first, by address (pure: tests/web-prefetch.mjs checks every path against the READS allowlist of scripts/web-serve.py).
import { LEGACY_POOLS } from './pages/storage/pool.js';
import { P } from './paths.js';

const A = '/api/sys/';
const DISKS = [`${A}monitor/disks`, `${A}disk-health/list`, `${A}state/disks`, `${A}disk/marks`];
const SHARES = [`${A}shares/overview`, `${A}shares/deleted`, `${A}ct/list`];
const pool = (p) => [`${A}pool/info?pool=${p}`, `${A}pool/members?pool=${p}`, `${A}monitor/disks`, `${A}disk/marks`];

// The address may carry its node and a query (/node/homeserver/storage/disks?x=1); the table below is keyed by the INNER path.
export const innerPath = (p) => (p || '').replace(/^\/node\/[^/]+(?=\/|$)/, '').replace(/[?#].*$/, '') || '/';

// The first reads of an extension's page: every `read` its declaration names ([web.page] blocks of its manifest, features.extensions), as the
// paths of the generic read API. Nothing about a particular extension is known here.
const wordsPath = (name, words) => `${A}ext/${name}/${String(words).split(' ').map(encodeURIComponent).join('/')}`;
function extReads(name, pages) {
  const page = (pages || []).find((p) => p.name === name);
  const out = new Set();
  const walk = (n) => {
    if (Array.isArray(n)) n.forEach(walk);
    else if (n && typeof n === 'object') for (const [k, v] of Object.entries(n)) (k === 'read' && typeof v === 'string') ? out.add(wordsPath(name, v)) : walk(v);
  };
  if (page) walk(page);
  return [...out];
}

// `extPages` = ui.features.extensions (the pages of the extension packages that are on); without it an extension page reads nothing first.
// `poolList` = the pool rows (pools.rows once loaded). `liveOn` = ui.features.live. Diagnostics switches its read in live mode so the prefetch/refresh button matches the visible table.
export function readsFor(path, extPages = [], liveOn = false, poolList = LEGACY_POOLS) {
  path = innerPath(path);
  let m;
  if ((m = path.match(/^\/extensions\/([a-z][a-z0-9-]*)$/))) return extReads(m[1], extPages);
  if ((m = path.match(/^\/storage\/pools\/([a-z0-9-]+)$/))) return pool(m[1]);
  if (/^\/storage\/disks\/[^/]+/.test(path)) return DISKS;   // the page of one disk reads what the list reads (its SMART history and tests are read by the page itself)
  if (path.startsWith('/settings/capabilities')) return [`${A}config/list`, `${A}parts/list`, `${A}parts/pending`];
  if (path === P.settingsUpdates) return [`${A}config/list`, `${A}system/updates`];
  if (path.startsWith('/settings/')) return [`${A}config/list`];
  switch (path) {
    case P.summary: return [`${A}status`, `${A}monitor/disks`, `${A}setup/list`, `${A}ups/status`];
    case P.instances: return [`${A}ct/list`, `${A}backup/overview`, `${A}services/list`, `${A}recipes/list`, `${A}docker/list`];
    case P.docker: return [`${A}docker/apps`, `${A}docker/status`];
    case P.registries: return [`${A}docker/registries`];
    case P.network: return [`${A}ct/list`, `${A}dns/list`, `${A}ports/list`, `${A}remote/list`, `${A}unifi/clients`, `${A}unifi/networks`];
    case P.users: case P.groups: return [`${A}users/list`, `${A}users/groups`];
    case P.certificates: return [`${A}dc/state`];
    case P.networkMap: return [`${A}netmap/topology`];
    case P.hardware: return [`${A}hardware`, `${A}monitor/disks`, `${A}ups/status`];
    case P.backup: return [`${A}backup/state`, `${A}backup/overview`, `${A}backup/snapshots?tag=shares`, `${A}backup/snapshots?tag=host`];
    case P.expiry: return [`${A}expiry/list`];
    case P.health: return [`${A}health/next`, `${A}health/list`, `${A}jobs/list`, `${A}status`];
    case P.apps: return [`${A}recipes/list`, `${A}recipes/versions`, `${A}apps/versions`, `${A}ct/list`];
    case P.marketplace: return [`${A}pkg/market`, `${A}pkg/repos`];
    case P.services: return [`${A}services/list`, `${A}services/routes`, `${A}ct/list`];
    case P.events: return [`${A}event/list?n=100`];
    case P.notifications: return [`${A}notify/channels`, `${A}notify/providers`];
    case P.liveState: return liveOn ? [`${A}live/inspect`] : [];
    case P.testLab: return [`${A}testlab/results`];
    case P.diagnostics: return [`${A}live/status`];
    case P.encryption: return [`${A}encryption/list`, `${A}status`];
    case P.vault: return [`${A}status`, `${A}vault/list`, `${A}vault/usage`, `${A}vault/uses`];
    case P.pools: return [`${A}pool/list`, `${A}monitor/disks`, ...poolList.filter((p) => p.kind !== 'zfs').map((p) => `${A}pool/info?pool=${p.name}`)];
    case P.incident: return [`${A}incident/state`, `${A}pool/disks`];
    case P.disks: return [...DISKS, ...poolList.filter((p) => p.kind !== 'zfs').slice(0, 1).map((p) => `${A}pool/members?pool=${p.name}`)];
    case P.shares: return SHARES;
    case P.files: return [`${A}fm/locations`];
    // the group pages (pages/groups/): only reads their places already have
    case P.storage: return [`${A}monitor/disks`, `${A}shares/overview`];
    case P.protection: return [`${A}backup/state`, `${A}expiry/list`];
    case P.operations: return [`${A}health/list`, `${A}system/updates`, `${A}dc/state`, `${A}ups/status`, `${A}event/list?n=100`];
    case P.settings: return [`${A}config/list`];
    case P.setup: return [`${A}setup/list`];
    case P.firstRun: return [`${A}preset/list`, `${A}parts/list`, `${A}setup/list`];
    case P.nodes: return [`${A}node/list`];
    default: return [];
  }
}

