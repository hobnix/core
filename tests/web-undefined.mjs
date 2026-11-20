// Every .svelte file under web/src compiles without a free identifier: a name used in markup or script that nothing declares
// (a `ReferenceError` at run time, a blank page; svelte's compiler stays silent about it). The compiled client code is parsed and every
// referenced name must be declared somewhere in the file (scopes are flattened: it catches the missing name, not a shadowed one).
// Run from the repository root with node after `npm ci` in web/.
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'web');
const req = createRequire(join(root, 'package.json'));
let compile, acorn;
try {
  const m = await import(pathToFileURL(req.resolve('svelte/compiler')).href);
  compile = m.compile ?? m.default?.compile;
  const a = await import(pathToFileURL(req.resolve('acorn')).href);
  acorn = a.parse ? a : a.default;
} catch { console.log('  skip  web/node_modules is missing (npm ci in web/)'); process.exit(0); }

const GLOBALS = new Set(('undefined NaN Infinity globalThis window document navigator location history localStorage sessionStorage console setTimeout clearTimeout ' +
  'setInterval clearInterval requestAnimationFrame cancelAnimationFrame queueMicrotask fetch Promise Object Array String Number Boolean Symbol Math JSON Date RegExp Error ' +
  'TypeError RangeError Map Set WeakMap WeakSet URL URLSearchParams FormData Blob File FileReader Event CustomEvent KeyboardEvent MouseEvent EventSource WebSocket ' +
  'AbortController AbortSignal ResizeObserver MutationObserver IntersectionObserver Intl parseInt parseFloat isNaN isFinite encodeURIComponent decodeURIComponent ' +
  'encodeURI decodeURI atob btoa structuredClone matchMedia getComputedStyle alert confirm prompt performance crypto TextEncoder TextDecoder Uint8Array ' +
  'ArrayBuffer Path2D screen innerWidth innerHeight addEventListener removeEventListener Image HTMLElement Node Element DOMParser XMLSerializer Reflect Proxy BigInt arguments import process').split(' '));

function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? (e.name === 'node_modules' ? [] : files(join(dir, e.name))) : e.name.endsWith('.svelte') ? [join(dir, e.name)] : []);
}

function patternNames(p, out) {
  if (!p) return;
  if (p.type === 'Identifier') out.add(p.name);
  else if (p.type === 'ObjectPattern') p.properties.forEach((x) => patternNames(x.value ?? x.argument, out));
  else if (p.type === 'ArrayPattern') p.elements.forEach((x) => patternNames(x, out));
  else if (p.type === 'RestElement') patternNames(p.argument, out);
  else if (p.type === 'AssignmentPattern') patternNames(p.left, out);
}

function free(code) {
  const ast = acorn.parse(code, { ecmaVersion: 'latest', sourceType: 'module' });
  const declared = new Set(), used = [];
  (function walk(n, parent, key) {
    if (!n || typeof n.type !== 'string' || n.type === 'MetaProperty') return;
    switch (n.type) {
      case 'VariableDeclarator': patternNames(n.id, declared); break;
      case 'FunctionDeclaration': case 'FunctionExpression': case 'ArrowFunctionExpression':
        if (n.id) declared.add(n.id.name); n.params.forEach((p) => patternNames(p, declared)); break;
      case 'ClassDeclaration': case 'ClassExpression': if (n.id) declared.add(n.id.name); break;
      case 'CatchClause': patternNames(n.param, declared); break;
      case 'ImportSpecifier': case 'ImportDefaultSpecifier': case 'ImportNamespaceSpecifier': declared.add(n.local.name); break;
      case 'Identifier': {
        const prop = (parent.type === 'MemberExpression' && key === 'property' && !parent.computed)
          || ((parent.type === 'Property' || parent.type === 'MethodDefinition' || parent.type === 'PropertyDefinition') && key === 'key' && !parent.computed)
          || (parent.type === 'LabeledStatement' || parent.type === 'BreakStatement' || parent.type === 'ContinueStatement')
          || ((parent.type === 'ExportSpecifier' || parent.type === 'ImportSpecifier') && key !== 'local' && key !== 'exported')
          || (parent.type === 'ExportSpecifier');
        if (!prop) used.push(n.name);
        break;
      }
    }
    for (const k of Object.keys(n)) {
      const v = n[k];
      if (Array.isArray(v)) v.forEach((c) => walk(c, n, k)); else if (v && typeof v.type === 'string') walk(v, n, k);
    }
  })(ast, null, '');
  return [...new Set(used)].filter((u) => !declared.has(u) && !GLOBALS.has(u));
}

let ok = 0, bad = 0;
for (const f of files(join(root, 'src'))) {
  const rel = f.slice(root.length + 1).split(String.fromCharCode(92)).join('/');
  try {
    const { js } = compile(readFileSync(f, 'utf8'), { filename: f, generate: 'client', runes: undefined });
    const miss = free(js.code);
    if (miss.length) { bad++; console.log(`  FAIL  ${rel}: undefined ${miss.join(', ')}`); } else ok++;
  } catch (e) { bad++; console.log(`  FAIL  ${rel}: ${e.message.split('\n')[0]}`); }
}
console.log(`  ${ok} files without an undefined name${bad ? `, ${bad} FAILED` : ''}`);
process.exit(bad ? 1 : 0);
