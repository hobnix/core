// path -> page. One line per page; a page that is not listed shows the placeholder. Pages get `deck` (the shared status document) as a prop.
import Summary from './pages/Summary.svelte';
import Instances from './pages/Instances.svelte';
import Shares from './pages/Shares.svelte';
import Health from './pages/Health.svelte';
import Pools from './pages/Pools.svelte';
import Incident from './pages/storage/Incident.svelte';
import Disks from './pages/Disks.svelte';
import Files from './pages/Files.svelte';
import Encryption from './pages/Encryption.svelte';
import Vault from './pages/Vault.svelte';
import Network from './pages/Network.svelte';
import Groups from './pages/Groups.svelte';
import Users from './pages/Users.svelte';
import Hardware from './pages/Hardware.svelte';
import Backup from './pages/Backup.svelte';
import SettingsPage from './settings/SettingsPage.svelte';
import AccessPage from './settings/AccessPage.svelte';
import Releases from './settings/Releases.svelte';
import CapsOverview from './settings/CapsOverview.svelte';
import CapabilitySettings from './settings/CapabilitySettings.svelte';
import Setup from './pages/Setup.svelte';
import FirstRun from './pages/FirstRun.svelte';
import Expiry from './pages/Expiry.svelte';
import IsoLibrary from './pages/IsoLibrary.svelte';
import Extension from './pages/Extension.svelte';
import Apps from './pages/Apps.svelte';
import Marketplace from './pages/Marketplace.svelte';
import PackageBuilder from './pages/PackageBuilder.svelte';
import Services from './pages/Services.svelte';
import Docker from './pages/Docker.svelte';
import Registries from './pages/docker/Registries.svelte';
import AppEditPage from './pages/docker/AppEditPage.svelte';
import AppWizardPage from './pages/docker/AppWizardPage.svelte';
import Docs from './pages/Docs.svelte';
import Certificates from './pages/Certificates.svelte';
import Notifications from './pages/Notifications.svelte';
import Events from './pages/Events.svelte';
import WhatsNew from './pages/WhatsNew.svelte';
import Data from './pages/Data.svelte';
import LiveState from './pages/LiveState.svelte';
import TestLab from './pages/TestLab.svelte';
// A page behind `lazy()` is its own chunk, loaded when it is first opened (PageFrame awaits it): the map and the UI SDK it pulls in do not weigh on every page (ADR 0030).
const lazy = (load) => ({ lazy: load });
const Gallery = lazy(() => import('./pages/Gallery.svelte'));
const NetworkMap = lazy(() => import('./pages/NetworkMap.svelte'));
import Section from './pages/Section.svelte';
import Proxy from './pages/Proxy.svelte';
import ProxyPorts from './pages/ProxyPorts.svelte';
import ProxyTailscale from './pages/ProxyTailscale.svelte';
import ProxySettings from './pages/ProxySettings.svelte';
import Nodes from './pages/Nodes.svelte';
import NodeSummary from './shell/NodeSummary.svelte';
import NodeHealth from './pages/nodes/NodeHealth.svelte';
import NodeFacts from './pages/nodes/NodeFacts.svelte';
import { P } from './paths.js';
import { objectOf } from './objects.js';
import Disk from './pages/disks/Disk.svelte';
import User from './pages/identity/User.svelte';
import Share from './pages/shares/Share.svelte';
import Instance from './pages/instances/Instance.svelte';

// the component of each kind in objects.js (one line per object page)
const objectPages = { pool: Pools, disk: Disk, user: User, share: Share, instance: Instance };

export const routes = {
  [P.summary]: Summary,
  [P.instances]: Instances,
  [P.storage]: Section,
  [P.identity]: Section,
  [P.protection]: Section,
  [P.operations]: Section,
  [P.monitoring]: Section,
  [P.pools]: Pools,
  [P.incident]: Incident,
  [P.disks]: Disks,
  [P.shares]: Shares,
  [P.files]: Files,
  [P.encryption]: Encryption,
  [P.vault]: Vault,
  [P.network]: Network,
  [P.groups]: Groups,
  [P.users]: Users,
  [P.certificates]: Certificates,
  [P.hardware]: Hardware,
  [P.backup]: Backup,
  [P.health]: Health,
  [P.expiry]: Expiry,
  [P.iso]: IsoLibrary,
  [P.apps]: Apps,
  [P.marketplace]: Marketplace,
  [P.builder]: PackageBuilder,
  [P.services]: Services,
  [P.docker]: Docker,
  [P.registries]: Registries,
  [P.dockerNew]: AppEditPage,
  [P.dockerWizard]: AppWizardPage,
  [P.notifications]: Notifications,
  [P.events]: Events,
  [P.whatsNew]: WhatsNew,
  [P.diagnostics]: Data,
  [P.networkMap]: NetworkMap,
  [P.liveState]: LiveState,
  [P.testLab]: TestLab,
  [P.developer]: Section,
  [P.components]: Gallery,
  [P.docs]: Docs,
  [P.setup]: Setup,
  [P.firstRun]: FirstRun,
  [P.settings]: Section,
  [P.settingsGeneral]: SettingsPage,
  [P.settingsNetwork]: SettingsPage,
  [P.settingsStorage]: SettingsPage,
  [P.settingsBackups]: SettingsPage,
  [P.settingsAccess]: AccessPage,
  [P.settingsUpdates]: SettingsPage,
  [P.releases]: Releases,
  [P.capabilities]: CapsOverview,
  [P.settingsAdvanced]: SettingsPage,
  [P.nodes]: Nodes,
};

// The pages of a REMOTE node, by its kind (the main node uses `routes`). They read the node's status document, never a local read.
// An edge or vps node: the proxyserver pages (Summary is the old /proxy page); a peer: summaries of its document. The address /node/<name>/health is the same for all.
const edgeRoutes = {
  [P.summary]: Proxy, [P.nodeHealth]: NodeHealth, [P.mail]: Proxy, [P.ports]: ProxyPorts, [P.watcher]: Proxy, [P.certificate]: Proxy, [P.tailscale]: ProxyTailscale, [P.settings]: ProxySettings,
};
const peerRoutes = {
  [P.summary]: NodeSummary, [P.nodeHealth]: NodeHealth, [P.storage]: NodeFacts, [P.instances]: NodeFacts, [P.backup]: NodeFacts,
};
export const nodeRoutes = { vps: edgeRoutes, edge: edgeRoutes, peer: peerRoutes };

// Address without a node -> address with the local node (redirects.js, pure so that a test can run it); route.svelte.js applies it.
export { redirect, VPS_NODE } from './redirects.js';

// The page for an INNER path (route.path: the address without /node/<name>): the exact path, or a guide (/docs/<lang>/<slug>).
export function pageFor(path, kind = 'main') {
  if (kind !== 'main') return (nodeRoutes[kind] ?? peerRoutes)[path];
  const obj = objectOf(path);
  if (obj) return objectPages[obj.kind];
  return routes[path] ?? (path.startsWith('/docs/') ? Docs : path.startsWith('/extensions/') ? Extension : path.startsWith('/settings/capabilities/') ? CapabilitySettings : path.startsWith('/instances/docker/app/') ? AppEditPage : undefined);
}
