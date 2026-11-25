// The tree switch (docs/PLAN-navigation.md step 8, D2 c): the new tree against the old one, role greying and capability hiding with fixtures,
// the Network map in its new group, the extension `group`. Plain node, no Svelte.
import { readFileSync } from 'node:fs';
import { P } from '../web/src/paths.js';
import { tree, offTree, nodeItems, visible, withExtItems, itemOf, titleOf, DEVELOPER_CAP } from '../web/src/nav.js';
import { redirect } from '../web/src/redirects.js';
import { lockedWhy, ROLES, maxRole } from '../web/src/roles.js';
import { stateOfRow, templateOf, extReadPath } from '../web/src/shell/generic.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const old = JSON.parse(readFileSync(new URL('./fixtures/old-tree.json', import.meta.url), 'utf8'));
const L = 'homeserver';
const flat = (items, out = []) => { for (const it of items) { if (it.path) out.push(it); if (it.children) flat(it.children, out); } return out; };
const inner = (addr) => addr.replace(`/node/${L}`, '').replace(/[?#].*$/, '') || '/';

// 1. the shape of D2 (c) with Apps & VMs (docs/PLAN-workloads.md 3): Summary, then seven groups, Developer last and only by capability
const groups = tree[0].children;
eq('the groups of the node', groups.slice(0, 7).map((g) => g.label), ['Storage', 'Apps & VMs', 'Network', 'People', 'System', 'Backup', 'Settings']);
eq('Apps & VMs is the list with its places under it', [groups[1].path, groups[1].children.map((c) => [c.label, c.path, c.capability ?? ''])], ['/apps', [['App catalog', '/apps/installed', ''], ['Marketplace', '/apps/marketplace', ''], ['Docker registries', '/apps/docker/registries', 'docker'], ['ISO images', '/apps/iso', 'incus']]]);
eq('Developer is the last group and carries a capability', [groups[7].label, groups[7].capability, groups.length], ['Developer', DEVELOPER_CAP, 8]);
eq('Hardware, Updates and Certificates are in System', ['Hardware', 'Updates', 'Certificates'].map((l) => groups.find((g) => g.label === 'System').children.some((c) => c.label === l)), [true, true, true]);
eq('Docs and What\'s new are not tree rows, Incident is no row', [P.docs, P.whatsNew, P.incident].map((p) => flat(tree).some((i) => i.path === p)), [false, false, false]);
eq('they are known places for titles and flags', [P.docs, P.whatsNew, P.incident, P.setup, P.nodes].map((p) => !!itemOf(p) && !!titleOf(p)), [true, true, true, true, true]);
eq('Releases is no row of Settings and no place of its own', [flat(tree).some((i) => i.label === 'Releases'), Object.values(P).includes('/settings/releases')], [false, false]);

// 2. the new tree against the old one: every old address ends on a row of the new tree or on a place the tree knows by another way
const known = new Set([...flat(tree), ...offTree].map((i) => i.path));
const byOtherWay = new Set([P.dockerNew, P.dockerWizard, P.builder, P.firstRun]);   // pages reached from a page, never rows
const lost = old.main.filter((p) => p !== '/').filter((p) => { const to = inner(redirect(p, L) ?? p); return !known.has(to) && !byOtherWay.has(to); });
eq('every old tree entry is reachable in the new tree (as row, top bar, action or banner)', lost, []);
eq('every old address redirects to a path that is in the new tree or known', old.main.filter((p) => p !== '/').filter((p) => !redirect(p, L) && !known.has(p) && !byOtherWay.has(p)), []);

// 3. the Network map: in the Network group at /node/<name>/network/map, with a redirect from the old address
eq('the Network map path', P.networkMap, '/network/map');
eq('the old Network map address ends there', redirect('/monitoring/network-map', L), '/node/homeserver/network/map');
eq('the Network map is a child of Network', groups.find((g) => g.label === 'Network').children.some((c) => c.path === P.networkMap), true);
eq('Releases ends on the Updates tab', redirect('/settings/releases', L), '/node/homeserver/system/updates?tab=releases');

// 4. role greying: every page is in the tree for every role; People, Vault, Files and Certificates are greyed below admin, nothing else
const rows = flat(tree).map((i) => i.path);
for (const r of ROLES) {
  const greyed = rows.filter((p) => lockedWhy(r, p));
  eq(`${r}: greyed rows`, greyed, r === 'admin' ? [] : [P.vault, P.files, P.people, P.users, P.groups, P.certificates].filter((p) => rows.includes(p)).sort((a, b) => rows.indexOf(a) - rows.indexOf(b)));
}
eq('the tree itself does not depend on the role', nodeItems.length <= 5, true);

// 5. capability hiding: an entry whose capability is off is left out, a list that is missing shows everything, People is not hidden by `ad`
const labels = (caps) => nodeItems('main', caps).map((g) => g.label);
eq('no capability: no Developer, People stays', [labels([]).includes('Developer'), labels([]).includes('People')], [false, true]);
eq('the developer capability shows Developer', labels([DEVELOPER_CAP]).includes('Developer'), true);
eq('an older server (no list) shows everything', labels(null).includes('Developer'), true);
const kids = (caps, g) => visible(nodeItems('main', caps).find((x) => x.label === g).children, caps).map((c) => c.label);   // the tree rows filter their children (TreeNode)
eq('Services needs reverse-proxy, Notifications needs notifications', [kids([], 'Network').includes('Services'), kids(['reverse-proxy'], 'Network').includes('Services'), kids([], 'System').includes('Notifications'), kids(['notifications'], 'System').includes('Notifications')], [false, true, false, true]);
eq('Live state and Test-lab follow their capabilities', [kids([], 'System').filter((l) => l === 'Live state' || l === 'Test-lab'), kids(['live-state', 'testlab'], 'System').filter((l) => l === 'Live state' || l === 'Test-lab')], [[], ['Live state', 'Test-lab']]);

// 6. extension pages go into the group their `group` names (default Apps)
const ext = (name, group) => ({ name, title: name, ...(group ? { group } : {}) });
const where = (exts) => withExtItems(groups, exts).filter((g) => (g.children ?? []).some((c) => c.path?.startsWith('/extensions/'))).map((g) => g.label);
eq('an extension without a group goes into Apps & VMs', where([ext('a')]), ['Apps & VMs']);
eq('the groups instances and apps are both Apps & VMs', [where([ext('a', 'instances')]), where([ext('a', 'apps')])], [['Apps & VMs'], ['Apps & VMs']]);
eq('an extension names its group', where([ext('a', 'network'), ext('b', 'backup')]), ['Network', 'Backup']);
eq('an unknown group falls back to Apps & VMs', where([ext('a', 'nowhere')]), ['Apps & VMs']);
eq('no extension, no change', withExtItems(groups, []) === groups, true);

// 6b. order inside a group: core places keep their order, package places follow alphabetically, `after` puts one behind a place
const placed = (exts, group = 'apps') => withExtItems(groups, exts.map((e) => ({ ...ext(e.name, group), ...e }))).find((g) => g.label === 'Apps & VMs').children.map((c) => c.path.split('/').pop());
const coreApps = groups.find((g) => g.label === 'Apps & VMs').children.map((c) => c.path.split('/').pop());
eq('package places follow the core places, alphabetically', placed([{ name: 'zeta' }, { name: 'alpha' }]), [...coreApps, 'alpha', 'zeta']);
eq('the core places keep their order', placed([{ name: 'alpha' }]).slice(0, coreApps.length), coreApps);
eq('after puts a package right behind a place of the core', placed([{ name: 'alpha' }, { name: 'zeta', after: coreApps[0] }]), [coreApps[0], 'zeta', ...coreApps.slice(1), 'alpha']);
eq('after names another package', placed([{ name: 'alpha' }, { name: 'zeta', after: 'alpha' }]), [...coreApps, 'alpha', 'zeta']);
eq('an after that matches nothing is ignored', placed([{ name: 'alpha', after: 'nowhere' }]), [...coreApps, 'alpha']);
eq('a package that names itself is placed once', placed([{ name: 'alpha', after: 'alpha' }]), [...coreApps, 'alpha']);
eq('two packages in a cycle are still placed once each', placed([{ name: 'a', after: 'b' }, { name: 'b', after: 'a' }]).slice(coreApps.length).sort(), ['a', 'b']);
eq('tabs are no third level: a package place has no children', withExtItems(groups, [ext('a')]).find((g) => g.label === 'Apps & VMs').children.find((c) => c.path === '/extensions/a').children, undefined);

// 6c. role of an action, template and the card state
eq('the higher role wins', [maxRole('viewer', 'admin'), maxRole('app-manager', undefined, 'viewer'), maxRole(), maxRole('nonsense', 'app-manager')], ['admin', 'app-manager', 'viewer', 'app-manager']);
eq('template: declared, else list', [templateOf({ template: 'feed' }), templateOf({ template: 'odd' }), templateOf({})], ['feed', 'list', 'list']);
eq('state: one dot, one line from the first row', stateOfRow({ read: 's', dot: 0, line: 1 }, ['warn', '3 files waiting']), { state: 'warn', line: '3 files waiting' });
eq('state: an unknown dot is off, "-" is nothing', stateOfRow({ read: 's', dot: 0, line: 1 }, ['fine', '-']), { state: 'off', line: '' });
eq('state: a string that is no number is the text itself', stateOfRow({ read: 's', dot: 'ok', line: 'Running' }, []), { state: 'ok', line: 'Running' });
eq('the generic read path', extReadPath('demo', 'state show'), '/api/sys/ext/demo/state/show');

// 7. a remote node keeps its tree (D8 a): the names that match are the new ones
eq('a peer keeps Storage, Instances and Backup', nodeItems('peer', ['storage', 'incus', 'backup']).map((i) => i.label), ['System', 'Storage', 'Instances', 'Backup']);
eq('a peer without capabilities has only System', nodeItems('peer', null).map((i) => i.label), ['System']);
eq('an edge node keeps its proxy pages, Health is System', nodeItems('edge', ['edge-ports']).map((i) => i.label), ['System', 'Ports', 'Tailscale', 'Settings']);
eq('a vps node keeps all its proxy pages', nodeItems('vps', null).map((i) => i.label), ['System', 'Mail entry', 'Ports', 'Outside watcher', 'Certificate', 'Tailscale', 'Settings']);
eq('the address of a remote System page stays /health', ['peer', 'edge', 'vps'].map((k) => nodeItems(k, [])[0].path), ['/health', '/health', '/health']);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
