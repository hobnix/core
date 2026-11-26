// The registry of objects that can have a page of their own (docs/PLAN-navigation.md, #453): a kind -> where its list is, where its pages live, its name and its tabs.
// Data only (no component), so that nav.js and the node tests can import it. The component of a kind is one line in `objectPages` of routes.js.
// `pageFor` (routes.js), `itemOf` and `titleOf` (nav.js) read it, so a new object adds one line here and one there, not a special case per function.
// An object page is /<group>/<kind>/<id>[/<tab>] (D6): `base` is the path up to the id. `tabs` is [] while the page has none (the pool page has no tabs yet).
import { P } from './paths.js';

export const objects = {
  pool: { label: 'Pool', list: P.pools, base: `${P.pools}/`, tabs: [] },
  disk: { label: 'Disk', list: P.disks, base: `${P.disks}/`, tabs: [{ id: 'overview', label: 'Overview' }, { id: 'smart', label: 'SMART' }, { id: 'tests', label: 'Tests' }, { id: 'files', label: 'Files' }] },
  user: { label: 'User', list: P.users, base: `${P.users}/`, tabs: [{ id: 'overview', label: 'Overview' }, { id: 'groups', label: 'Groups' }, { id: 'access', label: 'Access' }] },
  instance: { label: 'Instance', list: P.appsGroup, base: `${P.appsGroup}/instance/`, tabs: [{ id: 'overview', label: 'Overview' }, { id: 'config', label: 'Config' }, { id: 'network', label: 'Network' }, { id: 'console', label: 'Console' }] },
  // a Docker app (compose project) in the container docker; its name may be the name of an instance, so the kind is in the address. Instances and Docker apps share one list.
  // Which tabs one app has depends on who manages it (pages/docker/apps.js pageTabs).
  'docker-app': { label: 'Docker app', list: P.appsGroup, base: `${P.appsGroup}/docker-app/`, tabs: [{ id: 'overview', label: 'Overview' }, { id: 'compose', label: 'Compose' }, { id: 'logs', label: 'Logs' }] },
  share: { label: 'Share', list: P.shares, base: `${P.shares}/`, tabs: [{ id: 'overview', label: 'Overview' }, { id: 'access', label: 'Access' }, { id: 'snapshots', label: 'Snapshots' }] },
};

// the object an INNER path names: { kind, id, tab } (id decoded, tab '' when there is none), or null
export function objectOf(path) {
  for (const [kind, def] of Object.entries(objects)) {
    if (!path.startsWith(def.base) || path.length === def.base.length) continue;
    const [id, tab = ''] = path.slice(def.base.length).split('/');
    let name = id;
    try { name = decodeURIComponent(id); } catch { /* a malformed name stays as written */ }
    return { kind, id: name, tab };
  }
  return null;
}
