// The three web roles (ADR 0012) as the interface sees them. The server decides (scripts/web-serve.py answers 403 with the needed role); this file only
// decides what is SHOWN, so a person does not click into a refusal. The role comes from `GET /api/session` (`role`). Plain JS: tests import it in node.
//
// The page table follows the `x-hs-role` of the `sys` rows a page reads or changes (docs/api/openapi.json, scripts/lib/sys-roles.tsv): a page that
// reads an admin row is an admin page (only the secret ones are hidden, see ADMIN_ONLY); a page whose changes are the app rows (apps, ct, recipes, docker*) is open to an app manager for those.
export const ROLES = ['viewer', 'app-manager', 'admin'];
const rank = (r) => ROLES.indexOf(r);

// true when `have` may do what `need` asks; an unknown role on either side is refused (the server's role_ok)
export const roleOk = (have, need) => rank(have) >= 0 && rank(need) >= 0 && rank(have) >= rank(need);

// The pages a role may open (design behaviour 4.9, docs/PLAN-web-design.md): every page is open to every role, a viewer sees it without plans and with its
// action buttons drawn disabled (ui/Button `need`). The one exception is a page whose whole content is admin secrets, which a viewer should not even see
// listed: the Vault and the user / token / identity pages. Those need admin, are left out of the tree, and say "Not for your role" when opened by address.
const ADMIN_ONLY = ['/identity', '/storage/vault'];
export function pageRole(path) {
  return ADMIN_ONLY.some((p) => path === p || path.startsWith(p + '/')) ? 'admin' : 'viewer';
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
