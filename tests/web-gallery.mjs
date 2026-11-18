// The component gallery (web/src/pages/Gallery.svelte, #449) has an entry, with at least one state, for every `ui` component and for the shared
// shell pieces. A new component without an entry fails here; so does an entry whose component is gone. Run with node.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

// The shell pieces that pages share (docs/PLAN-web-design.md 5.1, 5.2). The rest of shell/ is the frame or has one user (5.3).
const SHELL = ['Inbox', 'JobStrip', 'LinkedObjects', 'PageHeader', 'PageState', 'Spark', 'Table', 'UsageBar'];

const comps = (dir) => readdirSync(join(src, dir)).filter((f) => f.endsWith('.svelte')).map((f) => f.slice(0, -7)).sort();
const full = readFileSync(join(src, 'pages', 'Gallery.svelte'), 'utf8');
const page = full.slice(full.indexOf('</script>'));   // the markup only: the comment above it quotes the tag

// every <Entry ...> up to the next one: its name, where it lives, and whether it shows a state
const parts = page.split('<Entry ').slice(1);
const entries = parts.map((p) => {
  const head = p.slice(0, p.indexOf('>'));
  return { name: (head.match(/name="([^"]+)"/) || [])[1], from: (head.match(/from="([^"]+)"/) || [])[1] || 'ui', cells: (p.match(/class="cell/g) || []).length };
});
const have = (from) => entries.filter((e) => e.from === from).map((e) => e.name).sort();

const ui = comps('ui');
eq('every ui component has an entry', ui.filter((n) => !have('ui').includes(n)), []);
eq('no entry for a ui component that is gone', have('ui').filter((n) => !ui.includes(n)), []);
eq('every shared shell piece has an entry', SHELL.filter((n) => !have('shell').includes(n)), []);
eq('no entry for a shell piece that is gone', have('shell').filter((n) => !comps('shell').includes(n)), []);
eq('no entry twice', entries.map((e) => e.name).filter((n, i, a) => a.indexOf(n) !== i), []);
eq('every entry shows at least one state', entries.filter((e) => !e.cells).map((e) => e.name), []);
eq('the shell list names real files', SHELL.filter((n) => !comps('shell').includes(n)), []);

// the page is reachable: a route and a tree entry
eq('the route exists', /'\/developer\/components': Gallery/.test(readFileSync(join(src, 'routes.js'), 'utf8')), true);
eq('the tree links it', /path: '\/developer\/components'/.test(readFileSync(join(src, 'nav.js'), 'utf8')), true);

console.log(`  ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
