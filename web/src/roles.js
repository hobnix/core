// The three web roles (ADR 0012) as the interface sees them. The server decides (scripts/web-serve.py answers 403 with the needed role); this file only
// decides what is SHOWN, so a person does not click into a refusal. The role comes from `GET /api/session` (`role`). Plain JS: tests import it in node.
//
// The page table follows the `x-hs-role` of the `sys` rows a page reads or changes (docs/api/openapi.json, scripts/lib/sys-roles.tsv): a page that
// reads an admin row is an admin page, a page whose changes are the app rows (apps, ct, recipes, docker*) is open to an app manager for those.
export const ROLES = ['viewer', 'app-manager', 'admin'];
const rank = (r) => ROLES.indexOf(r);

// true when `have` may do what `need` asks; an unknown role on either side is refused (the server's role_ok)
export const roleOk = (have, need) => rank(have) >= 0 && rank(need) >= 0 && rank(have) >= rank(need);

// the least role of a page, by inner path; the longest matching prefix wins; a page not listed is open to a viewer (it only reads viewer rows)
const PAGES = [
  ['/identity', 'admin'],            // users list, groups, access: admin reads
  ...['general', 'network', 'storage', 'backups', 'updates', 'releases', 'capabilities', 'advanced'].map((p) => [`/settings/${p}`, 'admin']),   // config list, updates, capabilities
  // /settings itself and /settings/access stay open: the Sessions card is for everybody (their own; AccessPage.svelte shows nothing else to a lower role)
  ['/nodes', 'admin'],
  ['/marketplace', 'admin'],         // pkg market and install are admin rows
  ['/setup', 'admin'],
  ['/storage/files', 'admin'],       // the file manager pairs and trashes through admin rows
  ['/storage/vault', 'admin'],       // vault list and usage
  ['/extensions', 'admin'],          // ext list
  ['/operations/notifications', 'viewer'],
];
export function pageRole(path) {
  let best = 'viewer', len = -1;
  for (const [p, r] of PAGES) if ((path === p || path.startsWith(p + '/')) && p.length > len) { best = r; len = p.length; }
  return best;
}
export const canSee = (role, path) => roleOk(role, pageRole(path));

// the tree without the pages a role may not open; a group whose pages are all gone goes too (a group with its own path stays while it is allowed)
export function forRole(items, role) {
  const out = [];
  for (const it of items ?? []) {
    const own = it.path ? canSee(role, it.path) : true;
    const kids = it.children ? forRole(it.children, role) : undefined;
    if (it.path && !own && !kids?.length) continue;
    if (!it.path && it.children && !kids.length) continue;
    out.push(kids ? { ...it, children: kids } : it);
  }
  return out;
}

// the least role of a change by its area (the first word of the `hs sys` row): the app rows are open to an app manager, everything else is admin
const APP_AREAS = new Set(['apps', 'ct', 'recipes', 'docker', 'docker-app', 'docker-registry', 'jobs']);
export const areaRole = (area) => (APP_AREAS.has(String(area).split('/')[0]) ? 'app-manager' : 'admin');

// the sentence for a refusal: the same words whether the server said it (403 body) or the interface knew before asking
export const refusal = (have, need) => `Your role (${have}) may not do this. It needs ${need}.`;
