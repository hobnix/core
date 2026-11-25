// The rows of the list Apps & VMs (pages/Workloads.svelte): containers and VMs (`sys ct list`) with the Docker apps (`sys docker apps`) nested under
// the container they run in, the filters of the address, and which rows show (docs/PLAN-workloads.md 3). Plain JS so that node can test it
// (tests/web-workloads.mjs).
import { isVm, isRunning } from './instances/kind.js';

export const PROVIDERS = { incus: 'Incus', docker: 'Docker' };
export const TYPES = { container: 'Container', vm: 'Virtual machine' };
export const DOCKER_HOST = 'docker';      // the locked system container every listed Docker app runs in

const value = (v) => (v && v !== '-' ? v : '');
export const portsOf = (a) => value(a.ports).split(',').filter(Boolean);

// The recipes (rows of `recipes list`: { name, cts, state }) that set up the instance `name`. An app that runs in Docker reports the instance docker:
// of those only the recipe docker set the container up, the others are rows under it.
export function recipesOf(name, recipes) {
  const names = (recipes ?? []).filter((r) => r.state !== 'not installed' && r.cts.includes(name)).map((r) => r.name);
  return name === DOCKER_HOST ? names.filter((n) => n === DOCKER_HOST) : names;
}

// The recipe of a Docker app: the one of the same name when a recipe manages it, else '' (no read ties a second copy under another name to its recipe)
export const recipeOfApp = (a, recipes) => (a.managed === 'recipe' && (recipes ?? []).some((r) => r.name === a.name) ? a.name : '');

const row = (r) => ({ ...r, kids: [], total: 0, context: false, hay: [r.name, ...r.apps, r.address, ...r.ports.map((p) => `${r.address}:${p}`), r.images].join('\n').toLowerCase() });

// cts: ctOf rows; apps: appOf rows; recipes: { name, cts, state }. `id` is unique over both kinds (an instance and a Docker app may share a name).
// A Docker app whose container is not in the list of instances stays in the list at the top, so that it is never lost.
export function buildRows({ cts = [], apps = [], recipes = [] }) {
  const top = cts.map((c) => row({ id: `i:${c.name}`, kind: 'instance', name: c.name, provider: 'incus', type: isVm(c) ? 'vm' : 'container', apps: recipesOf(c.name, recipes), address: value(c.address), ports: [], images: '', ct: c }));
  const hosts = new Map(top.map((r) => [r.name, r]));
  for (const a of apps) {
    const recipe = recipeOfApp(a, recipes);
    const child = row({ id: `d:${a.name}`, kind: 'docker', name: a.name, provider: 'docker', type: 'container', apps: recipe ? [recipe] : [], address: value(a.address), ports: portsOf(a), images: value(a.images), app: a });
    const host = hosts.get(a.parent);
    if (host) { host.kids.push(child); host.total += 1; } else top.push(child);
  }
  return top;
}

// The filters as the address says them (`?provider=docker&type=vm&q=photo`); an unknown value is "all". Without the capability docker there is no
// provider filter, so one in the address does nothing.
export function filtersOf(query, { docker = true } = {}) {
  const pick = (v, of) => (Object.hasOwn(of, v ?? '') ? v : '');
  return { provider: docker ? pick(query?.provider, PROVIDERS) : '', type: pick(query?.type, TYPES), q: String(query?.q ?? '') };
}
export const isFiltered = (f) => !!(f.provider || f.type || f.q.trim());

// does the row itself match: provider, type, and the text in its name, app, address (with its ports) or image
export function matches(r, f) {
  const q = f.q.trim().toLowerCase();
  return (!f.provider || r.provider === f.provider) && (!f.type || r.type === f.type) && (!q || r.hay.includes(q));
}

// The rows that show under the filters, each with its matching children. A row that does not match but has a matching child stays as the context of
// that child (`context: true`, drawn dimmed).
export function filterRows(rows, f) {
  return rows.flatMap((r) => {
    const kids = r.kids.filter((k) => matches(k, f));
    const own = matches(r, f);
    return own || kids.length ? [{ ...r, kids, context: !own, found: isFiltered(f) && kids.length > 0 }] : [];
  });
}

// A row is open at first; `closed` (names, kept for the session) are shut. A row with a child that a filter or the search found (`found`) is always
// open, whether the row matches itself or is only the context: its child is what was looked for.
export const isOpen = (r, closed) => r.found || !closed.has(r.name);
export const shownKids = (r, closed) => (isOpen(r, closed) ? r.kids : []);

// the container the Docker apps run in does not run, so none of them is listed
export const appsHidden = (r, docker = true) => docker && r.kind === 'instance' && r.name === DOCKER_HOST && !isRunning(r.ct);

// What the page shows from its two reads, which fail on their own: `ct` and `docker` are { data, error } of `sys ct list` and `sys docker apps`
// (`docker` = null without the capability). The whole page fails only when no read has data. `ctBanner` = the instances could not be read, but
// the Docker apps are there: said above them. `pageError` = what PageState gets (no data at all, or old instance rows that could not be refreshed).
export function pageState(ct, docker) {
  const hasData = ct.data != null || docker?.data != null;
  const ctBanner = !!ct.error && ct.data == null && hasData;
  return { hasData, ctBanner, pageError: ctBanner ? '' : ct.error?.message ?? '' };
}

