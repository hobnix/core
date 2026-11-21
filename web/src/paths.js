// The named places of the interface: one table `place key -> inner path`. Pages, the tree, the routes and the prefetch table spell a path through
// it (`go(P.disks)`), never as a literal, so moving a page is a one-line change here (docs/PLAN-navigation.md, step 0 and #452).
// These are INNER paths (route.path); `url()`/`go()` of route.svelte.js put the node in front. A literal path is a test failure (tests/web-select.mjs).
export const P = Object.freeze({
  summary: '/',
  // groups
  storage: '/storage', instances: '/instances', identity: '/identity', protection: '/protection', operations: '/operations', monitoring: '/monitoring',
  developer: '/developer', settings: '/settings',
  // storage
  pools: '/storage/pools', incident: '/storage/incident', disks: '/storage/disks', shares: '/storage/shares', files: '/storage/files',
  encryption: '/storage/encryption', vault: '/storage/vault',
  // instances and apps
  apps: '/instances/apps', iso: '/instances/iso', services: '/instances/services', docker: '/instances/docker', registries: '/instances/docker/registries',
  dockerNew: '/instances/docker/new', dockerWizard: '/instances/docker/wizard', marketplace: '/marketplace', builder: '/marketplace/builder',
  network: '/network',
  // identity
  groups: '/identity/groups', users: '/identity/users', certificates: '/identity/certificates',
  // monitoring, protection, operations
  hardware: '/monitoring/hardware', diagnostics: '/monitoring/diagnostics', liveState: '/monitoring/live-state', testLab: '/monitoring/test-lab',
  backup: '/protection/backup', expiry: '/protection/expiry',
  health: '/operations/health', notifications: '/operations/notifications', events: '/operations/events', whatsNew: '/operations/whats-new',
  components: '/developer/components', docs: '/docs', setup: '/setup', firstRun: '/setup/first-run', nodes: '/nodes',
  // settings
  settingsGeneral: '/settings/general', settingsNetwork: '/settings/network', settingsStorage: '/settings/storage', settingsBackups: '/settings/backups',
  settingsAccess: '/settings/access', settingsUpdates: '/settings/updates', releases: '/settings/releases', capabilities: '/settings/capabilities',
  settingsAdvanced: '/settings/advanced',
  // pages of a remote node (edge, vps: the proxy pages; every remote kind: its health)
  nodeHealth: '/health', mail: '/mail', ports: '/ports', watcher: '/watcher', certificate: '/certificate', tailscale: '/tailscale',
});

// pages with a name or a topic in the address
export const poolPath = (name) => `${P.pools}/${name}`;
// the page of one disk: /storage/disks/<name>[/<tab>] (D6); Overview has no tab segment
export const diskPath = (name, tab = '') => `${P.disks}/${encodeURIComponent(name)}${!tab || tab === 'overview' ? '' : `/${encodeURIComponent(tab)}`}`;
export const dockerAppPath = (name) => `${P.docker}/app/${encodeURIComponent(name)}`;
export const capabilityPath = (name) => `${P.capabilities}/${name}`;
export const extensionPath = (name) => `/extensions/${name}`;
export const nodePath = (name) => `/node/${encodeURIComponent(name)}`;
// a list address with its filter (`?pool=`)
export const withQuery = (path, query) => {
  const q = new URLSearchParams(query).toString();
  return q ? `${path}?${q}` : path;
};
