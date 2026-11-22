// WCAG contrast of the design tokens in both themes (web/src/tokens.css, docs/PLAN-navigation.md step 11). The dark and the light block are read from the
// file, oklch() (also the relative colours that derive from the accent) is converted to sRGB, translucent colours are laid over the background, and every
// text pair must reach 4.5:1. Exports `check`, `ratio`, `parseTokens` for tests/web-a11y.mjs. Run with node, no dependencies.
import fs from 'node:fs';

const DEFAULT_ACCENT = '#9184d9';
const hexToRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const clamp = (c) => Math.min(1, Math.max(0, c));

function oklabToLinear([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3, m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3, s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
}
function linearToOklab([r, g, b]) {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b), m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b), s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
}
const rad = Math.PI / 180;
const fromLch = (L, C, h) => oklabToLinear([L, C * Math.cos(h * rad), C * Math.sin(h * rad)]).map(clamp);

// one channel of a relative colour: a number, `c`, `h`, or calc(<c|h> <+|-|*> <number>)
function channel(tok, c, h) {
  tok = tok.trim();
  if (tok === 'c') return c;
  if (tok === 'h') return h;
  const m = /^calc\(\s*([ch])\s*([-+*])\s*([\d.]+)\s*\)$/.exec(tok);
  if (m) { const base = m[1] === 'c' ? c : h, n = +m[3]; return m[2] === '*' ? base * n : m[2] === '+' ? base + n : base - n; }
  return Number(tok);
}

// -> { rgb: linear sRGB, a } or null
export function parseColor(value, vars, accent) {
  const v = value.trim();
  let m;
  if ((m = /^var\((--[\w-]+)\)$/.exec(v))) return m[1] in vars ? parseColor(vars[m[1]], vars, accent) : null;
  if (/^#[0-9a-f]{6}$/i.test(v)) return { rgb: hexToRgb(v).map(lin), a: 1 };
  if ((m = /^oklch\(from var\(--accent\)\s+(.+)\)$/.exec(v))) {
    const [, A, B] = linearToOklab(accent);
    const toks = m[1].match(/calc\([^)]*\)|\S+/g);
    const [L, C, H] = toks.map((t, i) => (i === 0 ? Number(t) : channel(t, Math.hypot(A, B), (Math.atan2(B, A) / rad + 360) % 360)));
    return { rgb: fromLch(L, C, H), a: 1 };
  }
  if ((m = /^oklch\(([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+))?\)$/.exec(v))) return { rgb: fromLch(+m[1], +m[2], +m[3]), a: m[4] === undefined ? 1 : +m[4] };
  return null;
}
const over = (top, under) => ({ rgb: top.rgb.map((c, i) => c * top.a + under.rgb[i] * (1 - top.a)), a: 1 });
const luminance = ({ rgb: [r, g, b] }) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
export function ratio(fg, bg) {
  const l1 = luminance(over(fg, bg)), l2 = luminance(bg);
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
}

// the custom properties per theme: dark = :root {...}, light = :root[data-theme='light'] {...} on top of dark
export function parseTokens(css) {
  const block = (re) => { const m = re.exec(css); const out = {}; if (m) for (const d of m[1].matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)) out[d[1]] = d[2].trim(); return out; };
  const dark = block(/^:root\s*\{([\s\S]*?)^\}/m);
  const light = { ...dark, ...block(/^:root\[data-theme='light'\]\s*\{([\s\S]*?)^\}/m) };
  return { dark, light };
}

// [foreground, background, minimum ratio, what]
const BGS = ['--bg', '--panel', '--panel-2'];
export const PAIRS = [
  ...[...BGS, '--panel-3'].flatMap((bg) => [['--fg', bg, 4.5, 'text'], ['--fg-2', bg, 4.5, 'secondary text']]),
  ...BGS.map((bg) => ['--fg-3', bg, 4.5, 'hint text']),
  ...BGS.flatMap((bg) => ['--accent-ink', '--ok-ink', '--warn-ink', '--bad-ink', '--info-ink'].map((fg) => [fg, bg, 4.5, 'coloured text'])),
  ['--on-accent', '--accent', 4.5, 'text on the accent'],
];

export function check(css, accentHex = DEFAULT_ACCENT) {
  const accent = hexToRgb(accentHex).map(lin);
  const res = [];
  for (const [theme, vars] of Object.entries(parseTokens(css))) {
    const v = { ...vars, '--accent': accentHex };
    for (const [f, b, min, what] of PAIRS) {
      const fg = parseColor(v[f] ?? '', v, accent), bg = parseColor(v[b] ?? '', v, accent);
      if (!fg || !bg) { res.push({ theme, f, b, min, what, ratio: NaN, ok: false }); continue; }
      const r = ratio(fg, bg);
      res.push({ theme, f, b, min, what, ratio: r, ok: r >= min });
    }
  }
  return res;
}

if (process.argv[1]?.endsWith('web-a11y-contrast.mjs')) {
  const css = fs.readFileSync(new URL('../web/src/tokens.css', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  const res = check(css);
  for (const r of res.filter((x) => !x.ok)) console.log(`FAIL  ${r.theme}: ${r.f} on ${r.b} is ${r.ratio.toFixed(2)}:1, needs ${r.min} (${r.what})`);
  console.log(`${res.some((r) => !r.ok) ? 'FAIL' : 'ok'}  ${res.length} token pairs checked in both themes`);
  process.exit(res.some((r) => !r.ok) ? 1 : 0);
}
