// Pure helpers of the generic page (GenericPage.svelte, GenBlock.svelte): templates, row building, value formats. No Svelte here, so a test can run them.
import { bytes } from '../format.js';

// "{name}" -> the row's value; "{file|u}" -> URL-encoded. A missing value is an empty string.
export const tpl = (s, row = {}) => String(s ?? '').replace(/\{(\w+)(?:\|(\w+))?\}/g, (_, k, f) => { const v = row?.[k] ?? ''; return f === 'u' ? encodeURIComponent(v) : String(v); });

// the arguments of a plan declaration [area, arg, ...] with the row's values put in
export const planArgs = (plan, row) => plan.slice(1).map((a) => tpl(a, row));

// "-" is how the sys commands write "nothing" in a tab-separated field
const clean = (v) => (v === '-' ? '' : v);

// answer rows (arrays) -> objects by the declared columns: column i takes field `col` (default: its own position). `joins` add a field from another read.
// joins: [{ key, as, col }] with the answers [[row, ...], ...] in the same order: the join row whose FIRST field equals this row's `key` gives field `col`.
export function buildRows(answerRows, columns = [], joins = [], joinRows = []) {
  const maps = joins.map((j, i) => Object.fromEntries((joinRows[i] ?? []).map((r) => [r[0], r[j.col ?? 1]])));
  return answerRows.map((r) => {
    const o = {};
    columns.forEach((c, i) => { o[c.key] = clean(r[c.col ?? i]); });
    joins.forEach((j, i) => { o[j.as] = maps[i][o[j.key]]; });
    return o;
  });
}

const slug = (f) => String(f).replace(/^poster-/, '').replace(/\.png$/, '').replace(/-(\d+)$/, ' · seed $1').replace(/-/g, ' ');

// value formats of a column (`fmt`): bytes, datetime (epoch seconds), words (a file name as words)
export function fmtValue(fmt, v) {
  if (v === undefined || v === null || v === '') return '';
  if (fmt === 'bytes') return bytes(Number(v));
  if (fmt === 'datetime') return new Date(Number(v) * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
  if (fmt === 'words') return slug(v);
  return String(v);
}

// a dot column: the value -> [state, word]
export const dotOf = (col, v) => col.map?.[v] ?? ['off', v === undefined || v === '' ? 'not available' : String(v)];

// the switch columns read these as "on"
export const isOn = (v) => /^(1|yes|true|on|enabled)$/i.test(String(v ?? ''));

// The generic read path of an extension package: the words of a declared read ("list" or "state show") -> /api/sys/ext/<name>/list
export const extReadPath = (name, words) => `/api/sys/ext/${name}/${String(words).split(' ').map(encodeURIComponent).join('/')}`;

// The templates of a page (the page frame): list is the default
export const TEMPLATES = ['list', 'object', 'feed'];
export const templateOf = (spec) => (TEMPLATES.includes(spec?.template) ? spec.template : 'list');

// The `state` of a package page ({ read, dot, line }) and the first row of its read -> { state, line } for one dot and one line.
// dot and line are the number of a field of the row (a number, or a string of digits); any other string is the text itself. A dot that is not
// ok | warn | bad | info | off draws as off.
export function stateOfRow(st, row) {
  const at = (k) => (typeof k === 'number' || /^\d+$/.test(String(k)) ? clean((row ?? [])[Number(k)]) : String(k ?? ''));
  const dot = String(at(st?.dot) ?? '').toLowerCase();
  return { state: ['ok', 'warn', 'bad', 'info', 'off'].includes(dot) ? dot : 'off', line: String(at(st?.line) ?? '') };
}

// ---- blocks `log` and `progress` (#473) ----

// The last `max` lines of a log: a bounded view however long the stream runs (default 200, at least 1, at most 2000 like logfeed).
export const tailLines = (lines, max = 200) => {
  const n = Math.max(1, Math.min(2000, Math.floor(Number(max)) || 200));
  return lines.length > n ? lines.slice(-n) : lines;
};

// a declared address must be a path of this server's API, never another site
export const apiPath = (p) => (typeof p === 'string' && /^\/api\/[^\s]*$/.test(p) && !p.includes('..') ? p : '');

// the class of a log line (the colour is never the only signal: the line keeps its words)
export const logClass = (l) => (/\b(error|err|fail|failed|crit|alert|emerg)\b/i.test(l) ? 'bad' : /\bwarn(ing)?\b/i.test(l) ? 'warn' : '');

// the tone of a Progress bar for a state word (a job state or a read's own word); an unknown word is the running tone
const TONES = { ok: 'ok', done: 'ok', failed: 'bad', bad: 'bad', error: 'bad', warn: 'warn', waiting: 'warn', interrupted: 'warn' };
export const progressTone = (state) => TONES[String(state ?? '').toLowerCase()] ?? 'info';

// The bar of a `progress` block. From a read: `row` is the first row, value/max/state/labelCol are field numbers. From a job: `rec` is the parsed job
// record (jobrecords.js parseRecord). Returns { value, total, label, state, tone }; total is null when it is not known (a moving bar); null when nothing is there yet.
export function progressOf(block, row, rec) {
  if (block.job) {
    if (!rec) return null;
    return { value: rec.progress?.done ?? null, total: rec.progress?.total ?? null, label: block.label ?? rec.description, state: rec.state, tone: progressTone(rec.state) };
  }
  if (!row) return null;
  const at = (i) => (i === undefined ? '' : clean(row[i]) ?? '');
  const num = (i) => { const v = at(i); const n = v === '' ? NaN : Number(v); return Number.isFinite(n) ? n : null; };
  const state = at(block.state);
  return { value: num(block.value), total: num(block.max), label: at(block.labelCol) || block.label || '', state, tone: progressTone(state) };
}

// The `chart` block (#473): one field of every row of a read is a point, oldest first. Spark draws 0 to 100, so the points are scaled to `max` (default:
// the highest point, or 100 when all are 0) and `hot` (same unit as the points) becomes a percentage too. A field that is empty or `-` is skipped.
export function chartSeries(answerRows, col = 1, max = 0, hot = 0) {
  const pts = answerRows.map((r) => clean(r[col])).filter((v) => v !== '' && v !== undefined && Number.isFinite(Number(v))).map(Number);
  const top = max > 0 ? max : Math.max(0, ...pts) || 100;
  const pct = (n) => Math.max(0, Math.min(100, (n / top) * 100));
  return { values: pts.map(pct), last: pts.length ? pts[pts.length - 1] : null, max: top, hot: hot > 0 ? pct(hot) : 101 };
}

// The `stat` block (#473): tiles from the first row of a read, items [{ label, col, unit, fmt, map }] -> [{ label, value, unit, dot }]. `map` is a dot
// column's map ({ value: [state, word] }); a tile without `map` has no dot.
export function statTiles(firstRow, items = []) {
  const row = firstRow ?? [];
  return items.map((it) => {
    const raw = clean(row[it.col ?? 0]);
    return { label: it.label ?? '', value: fmtValue(it.fmt, raw), unit: raw === '' ? '' : it.unit ?? '', dot: it.map ? dotOf(it, raw) : null };
  });
}
