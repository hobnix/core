// The named places of the interface: one table `place key -> inner path`. Pages, the tree, the routes and the prefetch table spell a path through
// it (`go(P.disks)`), never as a literal, so moving a page is a one-line change here (docs/PLAN-navigation.md, step 0 and #452).
// These are INNER paths (route.path); `url()`/`go()` of route.svelte.js put the node in front. A literal path is a test failure (tests/web-select.mjs).
export const P = Object.freeze({
  summary: '/',
  // groups (D2 c: Storage, Instances, Apps, Network, People, System, Backup, Settings; Developer only while its capability is on)
  storage: '/storage', instances: '/instances', appsGroup: '/apps', people: '/people', system: '/system', backupGroup: '/backup',
  developer: '/developer', settings: '/settings',
  // storage
  pools: '/storage/pools', incident: '/storage/incident', disks: '/storage/disks', shares: '/storage/shares', files: '/storage/files',
  encryption: '/storage/encryption', vault: '/storage/vault',
  // instances
  iso: '/instances/iso',
  // apps
  apps: '/apps/installed', docker: '/apps/docker', registries: '/apps/docker/registries',
  dockerNew: '/apps/docker/new', dockerWizard: '/apps/docker/wizard', marketplace: '/apps/marketplace', builder: '/apps/marketplace/builder',
  // network
  network: '/network', services: '/network/services', networkMap: '/network/map',
  // people
  groups: '/people/groups', users: '/people/users',
  // system: Hardware, Updates (with the Releases tab) and Certificates live here (D2 c)
  health: '/system/health', events: '/system/events', notifications: '/system/notifications', hardware: '/system/hardware', updates: '/system/updates',
  certificates: '/system/certificates', diagnostics: '/system/diagnostics', liveState: '/system/live-state', testLab: '/system/test-lab', whatsNew: '/system/whats-new',
  // backup
  backup: '/backup/overview', expiry: '/backup/expiry',
  components: '/developer/components', docs: '/docs', setup: '/setup', firstRun: '/setup/first-run', nodes: '/nodes',
  // settings
  settingsGeneral: '/settings/general', settingsNetwork: '/settings/network', settingsStorage: '/settings/storage', settingsBackups: '/settings/backups',
  settingsAccess: '/settings/access', capabilities: '/settings/capabilities', settingsExtensions: '/settings/extensions', settingsAdvanced: '/settings/advanced',
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
