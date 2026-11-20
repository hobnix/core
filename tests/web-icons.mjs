// Every icon the interface draws by a literal name must be on the one list, web/src/ui/icons.js: `ph-<name>` in markup, `<Icon name="x">`,
// `icon="x"` on a component, `icon: 'x'` in data. Names built at run time (`ph-{x}`) are not checked here; Icon warns about them in dev builds.
// Also: the list has no duplicates. Run with node, no dependencies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
const { ICONS } = await import(new URL('../web/src/ui/icons.js', import.meta.url));
const known = new Set(ICONS);
let failed = 0, seen = 0;
const bad = (m) => { failed++; console.log('FAIL  ' + m); };
if (known.size !== ICONS.length) bad('ui/icons.js lists a name twice');

function walk(d, out = []) {
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name);
    if (f.isDirectory()) walk(p, out); else if (/\.(svelte|js)$/.test(p) && !p.endsWith('icons.js') && !p.endsWith('.gen.d.ts')) out.push(p);
  }
  return out;
}
const pats = [/\bph-([a-z0-9]+(?:-[a-z0-9]+)*)(?![a-z0-9{-])/g, /<Icon\b[^>]*\bname="([a-z0-9-]+)"/g, /\bicon="([a-z0-9-]+)"/g, /\bicon: '(?:ph-)?([a-z0-9-]+)'/g];
for (const f of walk(root)) {
  const s = fs.readFileSync(f, 'utf8');
  for (const re of pats) for (const m of s.matchAll(re)) {
    seen++;
    if (!known.has(m[1])) bad(`${path.relative(root, f)}: icon "${m[1]}" is not in ui/icons.js`);
  }
}
console.log(`${failed ? 'FAIL' : 'ok'}  ${seen} literal icon names checked against ${known.size} listed`);
process.exit(failed ? 1 : 0);
