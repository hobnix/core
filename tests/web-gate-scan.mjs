// Finds the buttons of the web pages that start a change (open a plan, open a form that plans, start a job) and the least role each one needs,
// read from the same table the server uses (scripts/lib/sys-roles.tsv, ADR 0012). tests/web-roles-ui.mjs fails for a button without a matching `need`.
// `node tests/web-gate-scan.mjs` lists every change button and its state. Plain node, no dependencies.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(root, 'web/src');
const RANK = { viewer: 0, 'app-manager': 1, admin: 2 };

// area -> least role, from the plan/start rows of the server's table (an area with two roles keeps the higher)
export function serverAreaRoles() {
  const out = {};
  for (const line of readFileSync(join(root, 'scripts/lib/sys-roles.tsv'), 'utf8').split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [row, role, cls] = line.split('\t');
    if (cls !== 'plan' && cls !== 'start') continue;
    const area = row.split(' ')[0];
    if (!(area in out) || RANK[role] > RANK[out[area]]) out[area] = role;
  }
  return out;
}

const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]));

// the text of a balanced {...} or (...) starting at `i` (which holds the opener)
function balanced(s, i) {
  const open = s[i], close = open === '{' ? '}' : ')';
  let depth = 0, q = '';
  for (let j = i; j < s.length; j++) {
    const c = s[j];
    if (q) { if (c === '\\') j++; else if (c === q) q = ''; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === open) depth++;
    else if (c === close && --depth === 0) return s.slice(i, j + 1);
  }
  return s.slice(i);
}

// every <Button ...> opening tag of a source: { tag, line }
function buttonTags(src) {
  const out = [];
  let from = 0;
  for (;;) {
    const at = src.indexOf('<Button', from);
    if (at < 0) return out;
    from = at + 7;
    if (!/[\s>]/.test(src[at + 7] ?? '')) continue;
    let depth = 0, q = '', j = at + 7;
    for (; j < src.length; j++) {
      const c = src[j];
      if (q) { if (c === q) q = ''; continue; }
      if (depth === 0 && (c === '"' || c === "'")) { q = c; continue; }
      if (c === '{') depth++;
      else if (c === '}') depth--;
      else if (c === '>' && depth === 0 && src[j - 1] !== '=') break;
    }
    out.push({ tag: src.slice(at, j + 1), line: src.slice(0, at).split('\n').length });
  }
}

const attr = (tag, name) => {
  const m = new RegExp(`[\\s]${name}=`).exec(tag);
  if (!m) return null;
  const i = m.index + m[0].length;
  if (tag[i] === '{') return balanced(tag, i).slice(1, -1);
  if (tag[i] === '"' || tag[i] === "'") return tag.slice(i + 1, tag.indexOf(tag[i], i + 1));
  return '';
};

// the body of a function declared in the source (function name(...) {...} or const name = ...), '' when there is none
function declBody(src, name) {
  const m = new RegExp(`(?:^|\\n)([ \\t]*)(?:async\\s+)?(?:function\\s+${name}\\b|(?:const|let)\\s+${name}\\s*=)`).exec(src);
  if (!m) return '';
  const start = m.index + m[0].length;
  const rest = src.slice(start);
  const next = new RegExp(`\\n${m[1]}(?:export\\s+)?(?:async\\s+)?(?:function|const|let|\\$:|\\$effect|onMount|import)\\b`).exec(rest);
  return rest.slice(0, next ? next.index : 4000);
}

// what a piece of code changes: known areas by literal, and whether some change is there without a literal area
function changesOf(code, src, areas, seen, file) {
  const found = new Set();
  let unknown = false;
  for (const m of code.matchAll(/\b(openPlan|plan|start)\(\s*([`'"])([a-z][a-z/-]*)\2/g)) {
    if (m[3] in areas) found.add(m[3]);
    else if (m[1] === 'openPlan') unknown = true;
  }
  if (/\bopenPlan\(\s*[^`'"\s]/.test(code)) unknown = true;
  for (const m of code.matchAll(/\bopenCreate\(\s*(\w+)/g)) {
    const comp = m[1];
    const imp = new RegExp(`import\\s+${comp}\\s+from\\s+['"]([^'"]+)['"]`).exec(src);
    const target = imp && resolve(dirname(file), imp[1]);
    if (target && existsSync(target)) {
      const sub = changesOf(readFileSync(target, 'utf8'), readFileSync(target, 'utf8'), areas, seen, target);
      sub.areas.forEach((a) => found.add(a));
      if (sub.unknown || !sub.areas.length) unknown = true;
    } else unknown = true;
  }
  for (const m of code.matchAll(/\b([A-Za-z_]\w*)\(/g)) {
    const name = m[1];
    if (seen.has(file + name)) continue;
    const body = declBody(src, name);
    if (!body) continue;
    seen.add(file + name);
    const sub = changesOf(body, src, areas, seen, file);
    sub.areas.forEach((a) => found.add(a));
    unknown ||= sub.unknown;
  }
  return { areas: [...found], unknown };
}

// pages that only an admin can open (the page frame refuses them below): their buttons need no gate of their own
const SKIP = [/\/forms\//, /\/setup\//, /\/files\//, /shell\/PlanDialog/, /shell\/Shell/, /pages\/Vault/, /pages\/Users/, /pages\/Groups/, /pages\/TestLab/];

export function scan() {
  const areas = serverAreaRoles();
  const rows = [];
  for (const file of walk(SRC).filter((f) => f.endsWith('.svelte')).sort()) {
    const rel = file.slice(SRC.length + 1).replaceAll('\\', '/');
    if (SKIP.some((r) => r.test('/' + rel))) continue;
    const src = readFileSync(file, 'utf8');
    for (const { tag, line } of buttonTags(src)) {
      const click = attr(tag, 'onclick');
      if (!click) continue;
      const { areas: hit, unknown } = changesOf(click, src, areas, new Set(), file);
      if (!hit.length && !unknown) continue;
      const want = hit.reduce((r, a) => (RANK[areas[a]] > RANK[r] ? areas[a] : r), unknown && !hit.length ? 'admin' : 'viewer');
      const need = attr(tag, 'need');
      rows.push({ rel, line, want, need: need === null ? '' : need.replace(/['"{}]/g, ''), dynamic: need !== null && /[{$]/.test(need) , areas: hit, unknown });
    }
  }
  return rows;
}

// a button with a change of unknown area only needs some `need` (the author chose it); a known area needs at least the server's role
export const lacking = (rows) => rows.filter((r) => !r.need || (!r.dynamic && r.areas.length && RANK[r.need] < RANK[r.want]));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const rows = scan();
  for (const r of rows) console.log(`${lacking([r]).length ? 'MISSING' : 'ok     '} ${r.rel}:${r.line}\twant ${r.want}\thas ${r.need || '-'}\t${r.areas.join(',')}${r.unknown ? ' ?' : ''}`);
  console.log(`${rows.length} change buttons, ${lacking(rows).length} without a matching need`);
}
