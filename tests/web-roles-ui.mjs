// The role-aware web interface (web/src/roles.js, nav.js): fixture sessions per role (viewer, app-manager, admin) get exactly the right pages,
// the right change rights, and a refusal in words. Pure functions, run with node.
import { ROLES, roleOk, pageRole, canSee, lockedWhy, areaRole, refusal } from '../web/src/roles.js';
import { nodeItems } from '../web/src/nav.js';
import { readFileSync } from 'node:fs';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };
const paths = (items) => items.flatMap((i) => [...(i.path ? [i.path] : []), ...paths(i.children ?? [])]);
const exts = [{ name: 'demo', title: 'Demo', icon: 'flask' }];
const tree = () => paths(nodeItems('main', null, exts, [], []));

eq('the roles are ordered viewer < app-manager < admin', ROLES, ['viewer', 'app-manager', 'admin']);
eq('a role may do what its own level or a lower one asks', [roleOk('admin', 'viewer'), roleOk('app-manager', 'app-manager'), roleOk('viewer', 'viewer')], [true, true, true]);
eq('a role may not do what a higher one asks', [roleOk('viewer', 'app-manager'), roleOk('app-manager', 'admin'), roleOk('viewer', 'admin')], [false, false, false]);
eq('an unknown role on either side is refused (as the server)', [roleOk('root', 'viewer'), roleOk('admin', 'root'), roleOk('', 'viewer')], [false, false, false]);

// the pages: every role sees every page; the ones above the role are greyed (lockedWhy), never left out
const all = tree();
const greyed = (role) => all.filter((p) => lockedWhy(role, p));
eq('every role sees every page of the tree (no page is hidden)', ROLES.map(() => all.includes('/identity') && all.includes('/storage/vault') && all.includes('/instances')), [true, true, true]);
eq('the tree does not depend on the role (nodeItems takes none)', nodeItems.length <= 5, true);
eq('an admin has no greyed page', greyed('admin'), []);
for (const r of ['viewer', 'app-manager'])
  eq(`${r}: the greyed pages are exactly the admin ones`, greyed(r).every((p) => p === '/storage/vault' || p.startsWith('/identity')) && ['/identity', '/identity/users', '/storage/vault'].every((p) => greyed(r).includes(p)), true);
for (const p of ['/instances', '/instances/apps', '/storage/pools', '/storage/disks', '/storage/shares', '/protection/backup', '/operations/health', '/settings/access', '/settings/general', '/nodes', '/marketplace', '/extensions/demo'])
  eq(`${p}: open to every role (a viewer without plans, buttons disabled)`, ROLES.map((r) => lockedWhy(r, p)), ['', '', '']);
eq('the reason names the role, as tooltip and accessible name', [lockedWhy('viewer', '/storage/vault'), lockedWhy('app-manager', '/identity/users'), lockedWhy('admin', '/identity')], ['Needs the admin role', 'Needs the admin role', '']);
eq('the pool pages are in the tree', paths(nodeItems('main', null, [], [], [{ name: 'tank', role: 'data' }])).includes('/storage/pools/tank'), true);
eq('a remote node keeps its pages (they only read)', nodeItems('peer', ['storage'], null, [], []).length, 2);

// the guard of a page opened by its address
eq('a page opened by address: admin pages refuse a viewer', [canSee('viewer', '/identity/users'), canSee('app-manager', '/storage/vault'), canSee('viewer', '/settings/access'), canSee('viewer', '/settings/general'), canSee('admin', '/identity')], [false, false, true, true, true]);
eq('an unlisted page needs no more than a viewer', pageRole('/something/new'), 'viewer');
eq('the longest prefix wins', [pageRole('/settings/general'), pageRole('/settings/access'), pageRole('/settings/access/x'), pageRole('/settings/capabilities/vps')], ['viewer', 'viewer', 'viewer', 'viewer']);
eq('the secret pages need admin, with their sub-pages', [pageRole('/identity'), pageRole('/identity/users'), pageRole('/storage/vault'), pageRole('/storage/vault/x'), pageRole('/storage/vaults')], ['admin', 'admin', 'admin', 'admin', 'viewer']);

// the changes
eq('the app areas are an app manager\'s', ['apps', 'ct', 'recipes', 'docker', 'docker-app', 'docker-registry', 'jobs'].map(areaRole), Array(7).fill('app-manager'));
eq('every other area is an admin\'s', ['system', 'pool', 'shares', 'users', 'config', 'pkg/bundle'].map(areaRole), Array(6).fill('admin'));
eq('a viewer may make no change', ['ct', 'system'].map((a) => roleOk('viewer', areaRole(a))), [false, false]);
eq('an app manager may make app changes only', ['ct', 'system'].map((a) => roleOk('app-manager', areaRole(a))), [true, false]);
eq('the refusal says both roles', refusal('viewer', 'admin'), 'Your role (viewer) may not do this. It needs admin.');

// the wiring (source checks: the components are not run in node)
const src = (p) => readFileSync(new URL(`../web/src/${p}`, import.meta.url), 'utf8');
eq('the session role is taken from /api/session and /api/login', /ui\.role = user\?\.role/.test(src('App.svelte')) && /ui\.role = s\?\.role/.test(src('App.svelte')), true);
const row = src('shell/TreeNode.svelte'), trow = src('shell/TreeRow.svelte'), card = src('pages/Section.svelte'), shell = src('shell/Shell.svelte');
eq('tree rows and section cards grey a locked page with a lock and the reason, never remove it', [/lockedWhy\(ui\.role, item\.path\)/.test(row), /ph-lock-simple/.test(trow), /aria-label=\{needs/.test(trow), /lockedWhy\(ui\.role, c\.path\)/.test(card), /canSee/.test(card), /forRole/.test(src('nav.js'))], [true, true, true, true, false, false]);
eq('the search lists every page (it is built without a role)', !/ui\.role/.test(src('shell/Search.svelte')), true);
eq('a greyed row is not prefetched (nothing of it is read)', /!needs && prefetchRoute/.test(row), true);
eq('the page frame names the role that may open the page and renders no page then', /Only the \$\{need\} role/.test(src('shell/PageFrame.svelte')) && /\{#if refused\}[\s\S]*\{:else if off\}/.test(src('shell/PageFrame.svelte')), true);
eq('the page frame says "not for your role" instead of a broken page', /Not for your role/.test(src('shell/PageFrame.svelte')), true);
eq('the plan dialog shows a refusal without asking', /dialog\.refused/.test(src('shell/PlanDialog.svelte')), true);
const btn = src('ui/Button.svelte');
eq('the button is drawn disabled below its `need`, with the refusal as its tooltip, never removed', [/!!need && !can\(need\)/.test(btn), /disabled=\{off\}/.test(btn), /refusal\(ui\.role, need\)/.test(btn), /use:tip=\{why\}/.test(btn), /\{#if !need/.test(btn)], [true, true, true, true, false]);
eq('users and access shows a role below admin only its own sessions', /Sessions own/.test(src('settings/AccessPage.svelte')) && /AccessPage/.test(src('routes.js')), true);
eq('no admin read is issued below admin: the shell polls them only for admin, and prefetches only pages the role may open', /canSee\(ui\.role, pg\)/.test(shell) && /admin \? '\/api\/sys\/node\/list'/.test(src('shell/Shell.svelte')) && /!admin \? '' : '\/api\/sys\/users\/list'/.test(src('shell/Shell.svelte')), true);

console.log(`${ok} passed, ${bad} failed`);
process.exit(bad ? 1 : 0);
