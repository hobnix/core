// A page model (web/src/**/*.svelte.js) never returns a `$derived` constant by value: `return { all }` copies the first (empty) value and the list stays empty
// ("No shares yet" with shares). It must be a getter (`get all() { return all; }`). Run from the repository root with node.
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const src = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');
const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : e.name.endsWith('.svelte.js') ? [join(d, e.name)] : []));
let bad = 0;
for (const f of walk(src)) {
  const text = readFileSync(f, 'utf8');
  const derived = [...text.matchAll(/(?:const|let)\s+(\w+)\s*=\s*\$derived/g)].map((m) => m[1]);
  // the `return { ... }` object closing a function: names listed as plain shorthand members
  for (const m of text.matchAll(/^ {2}return \{([\s\S]*?)^ {2}\};?$/gm)) {
    const plain = m[1].replace(/get \w+\(\)\s*\{[^}]*\}/g, '').split(/[,\s]+/).filter(Boolean);
    for (const n of plain) if (derived.includes(n)) { bad++; process.stdout.write(`${f}: "${n}" is a $derived returned by value (use a getter)\n`); }
  }
}
process.exit(bad ? 1 : 0);
