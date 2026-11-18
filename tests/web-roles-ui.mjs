// The role-aware web interface (web/src/roles.js, nav.js): fixture sessions per role (viewer, app-manager, admin) get exactly the right pages,
// the right change rights, and a refusal in words. Pure functions, run with node.
import { ROLES, roleOk, pageRole, canSee, forRole, areaRole, refusal } from '../web/src/roles.js';
import { nodeItems, mainTree } from '../web/src/nav.js';
import { readFileSync } from 'node:fs';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };
const paths = (items) => items.flatMap((i) => [...(i.path ? [i.path] : []), ...paths(i.children ?? [])]);
const exts = [{ name: 'demo', title: 'Demo', icon: 'flask' }];
const tree = (role) => paths(nodeItems('main', null, exts, [], [], role));

eq('the roles are ordered viewer < app-manager < admin', ROLES, ['viewer', 'app-manager', 'admin']);
eq('a role may do what its own level or a lower one asks', [roleOk('admin', 'viewer'), roleOk('app-manager', 'app-manager'), roleOk('viewer', 'viewer')], [true, true, true]);
eq('a role may not do what a higher one asks', [roleOk('viewer', 'app-manager'), roleOk('app-manager', 'admin'), roleOk('viewer', 'admin')], [false, false, false]);
eq('an unknown role on either side is refused (as the server)', [roleOk('root', 'viewer'), roleOk('admin', 'root'), roleOk('', 'viewer')], [false, false, false]);

// the pages
const admin = tree('admin'), mgr = tree('app-manager'), view = tree('viewer');
eq('an admin sees every page of the tree', admin, paths(nodeItems('main', null, exts, [], [])));
for (const p of ['/identity', '/identity/users', '/settings/general', '/settings/advanced', '/settings/capabilities', '/nodes', '/marketplace', '/setup', '/storage/files', '/storage/vault', '/extensions/demo'])
  eq(`${p}: only an admin sees it`, [admin.includes(p), mgr.includes(p), view.includes(p)], [true, false, false]);
for (const p of ['/', '/instances', '/instances/apps', '/instances/docker', '/storage/pools', '/storage/disks', '/storage/shares', '/protection/backup', '/operations/health', '/operations/events', '/monitoring/hardware', '/settings/access'])
  if (p !== '/') eq(`${p}: every role sees it`, [admin.includes(p), mgr.includes(p), view.includes(p)], [true, true, true]);
eq('Settings holds only Users and access for a role below admin', paths(nodeItems('main', null, [], [], [], 'viewer')).filter((p) => p.startsWith('/settings')), ['/settings', '/settings/access']);
eq('the groups of the hidden pages are gone (no empty Identity or Extensions)', [view.includes('/identity'), nodeItems('main', null, exts, [], [], 'viewer').some((i) => i.label === 'Extensions')], [false, false]);
eq('a role does not change the tree it is given', mainTree === forRole(mainTree, 'admin') ? 'same' : 'copy', 'copy');
eq('the pool pages stay for a viewer', paths(nodeItems('main', null, [], [], [{ name: 'tank', role: 'data' }], 'viewer')).includes('/storage/pools/tank'), true);
eq('a remote node is not filtered by role (its pages only read)', nodeItems('peer', ['storage'], null, [], [], 'viewer').length, 2);

// the guard of a page opened by its address
eq('a page opened by address: admin pages refuse a viewer', [canSee('viewer', '/identity/users'), canSee('app-manager', '/settings/general'), canSee('viewer', '/settings/access'), canSee('viewer', '/instances')], [false, false, true, true]);
eq('an unlisted page needs no more than a viewer', pageRole('/something/new'), 'viewer');
eq('the longest prefix wins', [pageRole('/settings/general'), pageRole('/settings/access'), pageRole('/settings/access/x'), pageRole('/settings/capabilities/vps')], ['admin', 'viewer', 'viewer', 'admin']);

// the changes
eq('the app areas are an app manager\'s', ['apps', 'ct', 'recipes', 'docker', 'docker-app', 'docker-registry', 'jobs'].map(areaRole), Array(7).fill('app-manager'));
eq('every other area is an admin\'s', ['system', 'pool', 'shares', 'users', 'config', 'pkg/bundle'].map(areaRole), Array(6).fill('admin'));
eq('a viewer may make no change', ['ct', 'system'].map((a) => roleOk('viewer', areaRole(a))), [false, false]);
eq('an app manager may make app changes only', ['ct', 'system'].map((a) => roleOk('app-manager', areaRole(a))), [true, false]);
eq('the refusal says both roles', refusal('viewer', 'admin'), 'Your role (viewer) may not do this. It needs admin.');

// the wiring (source checks: the components are not run in node)
const src = (p) => readFileSync(new URL(`../web/src/${p}`, import.meta.url), 'utf8');
eq('the session role is taken from /api/session and /api/login', /ui\.role = user\?\.role/.test(src('App.svelte')) && /ui\.role = s\?\.role/.test(src('App.svelte')), true);
eq('the tree and the search are built for the role', [/ui\.role\)/.test(src('shell/Tree.svelte')), /ui\.role\)/.test(src('shell/Search.svelte'))], [true, true]);
eq('the page frame says "not for your role" instead of a broken page', /Not for your role/.test(src('shell/PageFrame.svelte')), true);
eq('the plan dialog shows a refusal without asking', /dialog\.refused/.test(src('shell/PlanDialog.svelte')), true);
eq('the button hides itself below its `need`', /need \|\| can\(need\)/.test(src('ui/Button.svelte')), true);
eq('users and access shows a role below admin only its own sessions', /Sessions own/.test(src('settings/AccessPage.svelte')) && /AccessPage/.test(src('routes.js')), true);
eq('the shell does not read admin rows for a lower role', /admin \? '\/api\/sys\/node\/list'/.test(src('shell/Shell.svelte')) && /!admin \? '' : '\/api\/sys\/users\/list'/.test(src('shell/Shell.svelte')), true);

console.log(`${ok} passed, ${bad} failed`);
process.exit(bad ? 1 : 0);
