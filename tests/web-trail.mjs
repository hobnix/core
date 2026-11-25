// The breadcrumb trail and the marks of the tree (web/src/nav.js trailOf, nodeTrail, rowMark, withObjectRow; #1292, #1293). The object cases run
// over every kind of the registry (objects.js), so a new kind is covered without a line here. Plain node, no Svelte.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { P, poolPath, diskPath } from '../web/src/paths.js';
import { objects } from '../web/src/objects.js';
import { mainTree, offTree, nodeItems, trailOf, nodeTrail, rowMark, withObjectRow } from '../web/src/nav.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const flat = (items, out = []) => { for (const it of items) { out.push(it); if (it.children) flat(it.children, out); } return out; };
const labels = (path, o) => trailOf(path, o).map((c) => c.label);
const S = 'homeserver';

// the trail: parents only, derived from the tree
eq('Summary has no parent', trailOf('/'), []);
eq('a group has the server', trailOf(P.storage), [{ label: S, path: '/' }]);
eq('a list has the server and its group', trailOf(P.disks), [{ label: S, path: '/' }, { label: 'Storage', path: P.storage }]);
eq('an object page has everything above the object', labels(diskPath('sda')), [S, 'Storage', 'Disks']);
eq('a tab changes nothing', labels(diskPath('sda', 'smart')), [S, 'Storage', 'Disks']);
eq('a pool page ends on Pools, with or without its row in the items', [labels(poolPath('tank')), labels(poolPath('tank'), { items: nodeItems('main', null, null, [], [{ name: 'tank' }]) })], [[S, 'Storage', 'Pools'], [S, 'Storage', 'Pools']]);
eq('the server crumb carries the given name', trailOf(P.disks, { server: 'attic' })[0], { label: 'attic', path: '/' });
eq('a place outside the tree has the server only', offTree.map((it) => labels(it.path)), offTree.map(() => [S]));
eq('so has a guide and the first-run page', [labels(`${P.docs}/en/setup`), labels(P.firstRun)], [[S], [S]]);
eq('a page that is no row hangs under the row its address starts with', [labels(P.dockerNew), labels(`${P.docker}/app/photos`), labels(P.builder)], [[S, 'Apps', 'Docker'], [S, 'Apps', 'Docker'], [S, 'Apps', 'Marketplace']]);
eq('a settings page of a capability ends on Capabilities', labels(`${P.capabilities}/vps`), [S, 'Settings', 'Capabilities']);
eq('an unknown address has the server', labels('/nowhere'), [S]);
eq('an extension page is under the group of its package', nodeTrail('/extensions/demo', null, S, [{ name: 'demo', title: 'Demo', group: 'network' }]).map((c) => c.label), [S, 'Network']);

// a remote node: its own name and tree
for (const kind of ['peer', 'edge', 'vps']) {
  const node = { name: `n-${kind}`, kind, local: false, caps: null };
  eq(`${kind}: its pages have its name`, nodeTrail(P.nodeHealth, node, S, null).map((c) => c.label), [node.name]);
}
eq('a remote Summary has no parent', nodeTrail('/', { name: 'far', kind: 'peer', local: false }, S, null), []);
eq('this server as a node uses the local name', nodeTrail(P.disks, { name: S, kind: 'main', local: true }, S, null).map((c) => c.label), [S, 'Storage']);

// every kind of the registry: the trail ends on its list, the tree gets one temporary row under it
for (const [kind, def] of Object.entries(objects)) {
  const base = `${def.base}${encodeURIComponent('a b')}`;
  const path = def.tabs.length > 1 ? `${base}/${def.tabs[1].id}` : base;
  const trail = trailOf(path);
  eq(`${kind}: the trail ends on the list`, trail.at(-1)?.path, def.list);
  const before = JSON.stringify(mainTree);
  const items = withObjectRow(mainTree, path);
  const temp = flat(items).filter((i) => i.temp);
  const list = flat(items).find((i) => i.path === def.list);
  eq(`${kind}: one temporary row under the list, with the name`, [temp.length, temp[0]?.label, temp[0]?.path, list?.children?.at(-1) === temp[0], temp[0]?.storage], [1, 'a b', base, true, list?.storage]);
  eq(`${kind}: the temporary row is the open page, the list the parent`, [rowMark(base, path, trail), rowMark(def.list, path, trail), rowMark('/', path, trail)], ['current', 'parent', trail.length > 1 ? 'above' : 'parent']);
  eq(`${kind}: the static tree is not changed`, JSON.stringify(mainTree), before);
}
eq('leaving the page takes the row away', flat(withObjectRow(mainTree, P.disks)).some((i) => i.temp), false);

// a pool has a permanent row: no temporary one
const withPools = nodeItems('main', null, null, [], [{ name: 'tank' }, { name: 'fast' }]);
eq('a pool with its row gets no temporary row', withObjectRow(withPools, poolPath('tank')) === withPools, true);
const pt = trailOf(poolPath('tank'), { items: withPools });
eq('the pool row is the open page, Pools the parent, Storage above, its neighbour nothing', [poolPath('tank'), P.pools, P.storage, '/', poolPath('fast'), P.disks].map((p) => rowMark(p, poolPath('tank'), pt)), ['current', 'parent', 'above', 'above', '', '']);

// the marks of a plain page
const dt = trailOf(P.disks);
eq('the open row, its parent, the server above', [P.disks, P.storage, '/', P.pools].map((p) => rowMark(p, P.disks, dt)), ['current', 'parent', 'above', '']);
eq('a page under a row without a row of its own leaves that row the parent', rowMark(P.marketplace, P.builder, trailOf(P.builder)), 'parent');
eq('a row without a path is never marked', rowMark(undefined, P.disks, dt), '');

// no page passes its own breadcrumb, and the shared heads derive it
const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
const svelte = (dir, out = []) => { for (const e of readdirSync(dir, { withFileTypes: true })) { const p = join(dir, e.name); if (e.isDirectory()) svelte(p, out); else if (e.name.endsWith('.svelte')) out.push(p); } return out; };
eq('no component takes or passes a crumb', svelte(src).filter((f) => /\bcrumb=|\{crumb\}/.test(readFileSync(f, 'utf8'))), []);
eq('the shared heads draw the derived trail', ['shell/PageHeader.svelte', 'shell/Placeholder.svelte', 'pages/Section.svelte', 'pages/proxy/ProxyHead.svelte'].filter((f) => !readFileSync(join(src, f), 'utf8').includes('<PageTrail />')), []);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
