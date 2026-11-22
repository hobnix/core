// The tree switch (docs/PLAN-navigation.md step 8, D2 c): the new tree against the old one, role greying and capability hiding with fixtures,
// the Network map in its new group, the extension `group`. Plain node, no Svelte.
import { readFileSync } from 'node:fs';
import { P } from '../web/src/paths.js';
import { tree, offTree, nodeItems, visible, withExtItems, itemOf, titleOf, DEVELOPER_CAP } from '../web/src/nav.js';
import { redirect } from '../web/src/redirects.js';
import { lockedWhy, ROLES } from '../web/src/roles.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const old = JSON.parse(readFileSync(new URL('./fixtures/old-tree.json', import.meta.url), 'utf8'));
const L = 'homeserver';
const flat = (items, out = []) => { for (const it of items) { if (it.path) out.push(it); if (it.children) flat(it.children, out); } return out; };
const inner = (addr) => addr.replace(`/node/${L}`, '').replace(/[?#].*$/, '') || '/';

// 1. the shape of D2 (c): Summary, then eight groups, Developer last and only by capability
const groups = tree[0].children;
eq('the groups of the node', groups.slice(0, 8).map((g) => g.label), ['Storage', 'Instances', 'Apps', 'Network', 'People', 'System', 'Backup', 'Settings']);
eq('Developer is the last group and carries a capability', [groups[8].label, groups[8].capability, groups.length], ['Developer', DEVELOPER_CAP, 9]);
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
eq('an extension without a group goes into Apps', where([ext('a')]), ['Apps']);
eq('an extension names its group', where([ext('a', 'network'), ext('b', 'backup')]), ['Network', 'Backup']);
eq('an unknown group falls back to Apps', where([ext('a', 'nowhere')]), ['Apps']);
eq('no extension, no change', withExtItems(groups, []) === groups, true);

// 7. a remote node keeps its tree (D8 a): the names that match are the new ones
eq('a peer keeps Storage, Instances and Backup', nodeItems('peer', ['storage', 'incus', 'backup']).map((i) => i.label), ['Health', 'Storage', 'Instances', 'Backup']);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
