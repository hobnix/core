// The three web roles (ADR 0012) as the interface sees them. The server decides (scripts/web-serve.py answers 403 with the needed role); this file only
// decides what is SHOWN, so a person does not click into a refusal. The role comes from `GET /api/session` (`role`). Plain JS: tests import it in node.
//
// The page table follows the `x-hs-role` of the `sys` rows a page reads or changes (docs/api/openapi.json, scripts/lib/sys-roles.tsv): a page that
// reads an admin row is an admin page (only the secret ones are hidden, see ADMIN_ONLY); a page whose changes are the app rows (apps, ct, recipes, docker*) is open to an app manager for those.
import { P } from './paths.js';
export const ROLES = ['viewer', 'app-manager', 'admin'];
const rank = (r) => ROLES.indexOf(r);

// true when `have` may do what `need` asks; an unknown role on either side is refused (the server's role_ok)
export const roleOk = (have, need) => rank(have) >= 0 && rank(need) >= 0 && rank(have) >= rank(need);

// the higher of the roles that are given (an empty or unknown one counts for nothing): a page role and an action role together
export const maxRole = (...rs) => rs.filter((r) => rank(r) >= 0).reduce((a, b) => (rank(b) > rank(a) ? b : a), 'viewer');

// The page table (design behaviour 4.9, docs/PLAN-web-design.md): EVERY page is listed for EVERY role, nothing is hidden. A page above the role is drawn
// greyed with a lock and the reason (`lockedWhy`), stays clickable, and opens "Not for your role" without reading anything. The pages that need admin are
// the ones whose whole content is admin secrets: the Vault, the user / token / identity pages and the file manager (it lists file names of every share, `fm` rows are admin, #946). The server decides; this only explains.
const ADMIN_PAGES = [P.people, P.certificates, P.vault, P.files];
export function pageRole(path) {
  return ADMIN_PAGES.some((p) => path === p || path.startsWith(p + '/')) ? 'admin' : 'viewer';
}
export const canSee = (role, path) => roleOk(role, pageRole(path));

// the reason a page is greyed for `role` ('' when it is open to it): the tooltip and the accessible name of the row
export const lockedWhy = (role, path) => (canSee(role, path) ? '' : `Needs the ${pageRole(path)} role`);

// the least role of a change by its area (the first word of the `hs sys` row): the app rows are open to an app manager, everything else is admin
const APP_AREAS = new Set(['apps', 'ct', 'recipes', 'docker', 'docker-app', 'docker-registry', 'token']);
export const areaRole = (area) => (APP_AREAS.has(String(area).split('/')[0]) ? 'app-manager' : 'admin');

// the sentence for a refusal: the same words whether the server said it (403 body) or the interface knew before asking
export const refusal = (have, need) => `Your role (${have}) may not do this. It needs ${need}.`;
