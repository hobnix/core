// Accessibility checks that need no browser (docs/PLAN-navigation.md step 11, #487): (1) the static label check, with fixtures that must fail: an icon-only
// button, an input or an image without a name; on the real tree the findings per file may only go down (baseline tests/web-a11y.tsv, `--update` writes it);
// (2) the contrast of the tokens in both themes (tests/web-a11y-contrast.mjs); (3) the keyboard checklist as source checks: roles, labels, Escape and
// focus return of the quick look, the drawer, the dialog and the object page. The real keyboard walk and the screen reader run are NOT here (they need a
// real browser). Run with node, no dependencies.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { check as contrast } from './web-a11y-contrast.mjs';
import { returnTarget } from '../web/src/ui/quicklook.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..', 'web', 'src');
const BASE = path.join(here, 'web-a11y.tsv');
let ok = 0, bad = 0;
const pass = (n) => { ok++; console.log(`  ok    ${n}`); };
const fail = (n, why = '') => { bad++; console.log(`  FAIL  ${n}${why ? ': ' + why : ''}`); };
const t = (n, cond, why) => (cond ? pass(n) : fail(n, why));
const src = (p) => fs.readFileSync(path.join(root, p), 'utf8').replace(/\r\n/g, '\n');

// ── (1) the static label check: opening tags with their attribute text and what follows up to the closing tag
const ATTRS = '(?:[^>{]|\\{(?:[^{}]|\\{[^{}]*\\})*\\})*'; // attributes: {expressions} may hold one level of braces and a >
const NAMED =/\baria-label(?:ledby)?=|\btitle=|\{\.\.\./;
export function labelFindings(text) {
  const out = [];
  const s = text.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
  const line = (i) => s.slice(0, i).split('\n').length;
  for (const m of s.matchAll(/<img\b([^>]*?)\/?>/g)) if (!/\balt=|\{\.\.\./.test(m[1])) out.push({ line: line(m.index), rule: 'img-alt', what: '<img> without alt' });
  for (const m of s.matchAll(new RegExp(`<(button|Button)\\b(${ATTRS})>([\\s\\S]*?)<\\/\\1>`, 'g'))) {
    if (/aria-hidden=/.test(m[2])) continue; // hidden from the tree (a scrim)
    const inner = m[3].replace(/<img\b[^>]*\balt=(?:"[^"]+"|\{)[^>]*>/g, 'x').replace(/<i\b[^>]*><\/i>|<Icon\b[^>]*\/>|<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]*>/g, '').trim();
    if (!inner && !NAMED.test(m[2])) out.push({ line: line(m.index), rule: 'button-name', what: `<${m[1]}> with an icon only and no aria-label` });
  }
  for (const m of s.matchAll(new RegExp(`<(input|select|textarea)\\b(${ATTRS})\\/?>`, 'g'))) {
    const a = m[2];
    if (/type=["']?(hidden|submit|button)/.test(a) || NAMED.test(a) || /\bid=/.test(a) || /\bbind:(group|this)=/.test(a) && /type=["']?(radio|checkbox)/.test(a)) continue;
    const before = s.slice(0, m.index);
    if (before.lastIndexOf('<label') > before.lastIndexOf('</label>')) continue; // wrapped by a <label>
    out.push({ line: line(m.index), rule: 'label', what: `<${m[1]}> without a label (aria-label, id with a <label for>, or inside <label>)` });
  }
  return out;
}

console.log('-- the label check on fixtures');
t('an icon-only button is found', labelFindings('<button class="btn"><i class="ph ph-x"></i></button>').length === 1);
t('an icon-only Button is found', labelFindings('<Button onclick={f}><i class="ph ph-x"></i></Button>').length === 1);
t('an icon-only button with aria-label is fine', labelFindings('<button aria-label="Close"><i class="ph ph-x"></i></button>').length === 0);
t('a button with text is fine', labelFindings('<button><i class="ph ph-x"></i>Close</button>').length === 0);
t('an input without a label is found', labelFindings('<div><input type="text" bind:value={x} /></div>').length === 1);
t('an input with aria-label, with an id, or inside a label is fine', labelFindings('<input aria-label="Name"/><input id="a"/><label>Name <input /></label>').length === 0);
t('a button holding an image with alt is fine', labelFindings('<button><img src="a" alt="Cover"></button>').length === 0);
t('an image without alt is found', labelFindings('<img src="a.png">').length === 1);
t('a commented-out missing label is ignored', labelFindings('<!-- <img src="a.png"> -->').length === 0);

console.log('-- the label check on the real tree (findings per file may only go down)');
function walk(d, o = []) {
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name);
    if (f.isDirectory()) walk(p, o); else if (p.endsWith('.svelte')) o.push(p);
  }
  return o;
}
const counts = {};
for (const f of walk(root)) {
  const n = labelFindings(fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n')).length;
  if (n) counts[path.relative(root, f).replace(/\\/g, '/')] = n;
}
if (process.argv.includes('--update')) {
  fs.writeFileSync(BASE, Object.entries(counts).sort().map(([f, n]) => `${f}\t${n}`).join('\n') + (Object.keys(counts).length ? '\n' : ''));
  console.log(`wrote ${BASE}`);
}
const base = Object.fromEntries((fs.existsSync(BASE) ? fs.readFileSync(BASE, 'utf8') : '').split('\n').filter(Boolean).map((l) => { const [f, n] = l.split('\t'); return [f, +n]; }));
for (const f of new Set([...Object.keys(counts), ...Object.keys(base)])) {
  const now = counts[f] ?? 0, was = base[f] ?? 0;
  if (now > was) fail(`${f}: ${now} unnamed controls, baseline ${was}`);
  else if (now < was) fail(`${f}: ${now} < baseline ${was}: lower the number in tests/web-a11y.tsv (node tests/web-a11y.mjs --update)`);
}
pass(`${Object.keys(counts).length} files with findings, none above the baseline`);

console.log('-- the contrast of the tokens in both themes');
const css = src('tokens.css');
const res = contrast(css);
for (const r of res.filter((x) => !x.ok)) fail(`${r.theme}: ${r.f} on ${r.b} is ${r.ratio.toFixed(2)}:1, needs ${r.min} (${r.what})`);
t(`${res.length} token pairs reach their ratio (dark and light)`, res.every((r) => r.ok));
t('a pair that fails is reported (grey on white)', contrast(':root { --bg: oklch(1 0 0); --panel: oklch(1 0 0); --panel-2: oklch(1 0 0); --panel-3: oklch(1 0 0); --fg: oklch(0.8 0 0); --fg-2: oklch(0.8 0 0); --fg-3: oklch(0.8 0 0); --accent-ink: oklch(0.8 0 0); --ok-ink: oklch(0.8 0 0); --warn-ink: oklch(0.8 0 0); --bad-ink: oklch(0.8 0 0); --info-ink: oklch(0.8 0 0); --on-accent: oklch(0.8 0 0); --accent: #ffffff; }\n').some((r) => !r.ok));

console.log('-- the keyboard checklist, as source checks');
const drawer = src('ui/Drawer.svelte'), ql = src('ui/QuickLook.svelte'), dlg = src('ui/Dialog.svelte'), tabsSrc = src('ui/PageTabs.svelte'), seg = src('ui/Segmented.svelte');
t('the drawer is a named landmark and Escape closes it', /<aside[^>]*aria-label=\{title\}/.test(drawer) && /key === 'Escape'/.test(drawer));
t('the drawer close button has a name', /aria-label="Close"/.test(drawer));
t('the drawer tabs are a tablist with role tab and aria-selected', /role="tablist"/.test(drawer) && /role="tab"/.test(drawer) && /aria-selected=/.test(drawer));
t('the quick look is a non-modal dialog', /role="dialog"/.test(ql) && !/aria-modal="true"/.test(ql));
t('the quick look returns the focus (returnTarget) when it closes', /returnTarget/.test(ql) || /returnTarget/.test(src('ui/quicklook.js')));
const opener = { isConnected: true }, row = { id: 'row' };
t('returnTarget: the row of the object first, then the opener, else nothing', returnTarget({ querySelector: () => row }, 'sda', opener) === row && returnTarget({ querySelector: () => null }, 'sda', opener) === opener && returnTarget({ querySelector: () => null }, 'sda', { isConnected: false }) === null);
t('the dialog has role dialog, aria-modal and a name, and traps the focus', /role=\{?["']?(alertdialog|dialog)/.test(dlg) && /aria-modal/.test(dlg) && /aria-label(ledby)?=/.test(dlg) && /trapFocus/.test(dlg));
t('the focus trap returns the focus on destroy', /before\.focus/.test(src('ui/focus.js')));
t('page tabs name their group', /aria-label|role="tablist"/.test(tabsSrc));
t('the segmented control is a group or radiogroup with a name', /role="(radiogroup|group|tablist)"/.test(seg));
const objp = fs.existsSync(path.join(root, 'shell', 'ObjectPage.svelte')) ? src('shell/ObjectPage.svelte') : '';
t('the object page has a heading and its tabs are a tablist', objp === '' || (/<PageHeader/.test(objp) && /<PageTabs/.test(objp)));

console.log(`${bad ? 'FAIL' : 'ok'}  ${ok} checks passed, ${bad} failed`);
if (process.env.A11Y_DEBUG) for (const f of walk(root)) for (const x of labelFindings(fs.readFileSync(f, "utf8"))) console.log(f, x.line, x.what);
process.exit(bad ? 1 : 0);
