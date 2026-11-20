// Pure helpers of Timeline (plain JS so tests/web-timeline.mjs can load them in node).

// Newest first; entries without a time go last, ties keep their order.
export const newestFirst = (entries) =>
  (entries || []).map((e, i) => [e, i]).sort(([a, i], [b, j]) => (Number(b.time) || 0) - (Number(a.time) || 0) || i - j).map(([e]) => e);

// "today", "yesterday" or a local date key ("2026-11-18"); '' without a usable time. `now` in ms.
export function dayKey(epoch, now = Date.now()) {
  const t = Number(epoch);
  if (!t || t <= 0) return '';
  const d = new Date(t * 1000), n = new Date(now);
  const ymd = (x) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  if (ymd(d) === ymd(n)) return 'today';
  const y = new Date(n); y.setDate(n.getDate() - 1);
  return ymd(d) === ymd(y) ? 'yesterday' : ymd(d);
}

// Entries sorted newest first and cut into day groups: [{ day, entries }] (day as from dayKey; '' = no time).
export function groupByDay(entries, now = Date.now()) {
  const out = [];
  for (const e of newestFirst(entries)) {
    const day = dayKey(e.time, now);
    const last = out[out.length - 1];
    if (last && last.day === day) last.entries.push(e); else out.push({ day, entries: [e] });
  }
  return out;
}

// The dot state of a severity word; anything unknown is neutral, never an error.
const DOT = { ok: 'ok', info: 'info', warn: 'warn', warning: 'warn', bad: 'bad', error: 'bad', critical: 'bad' };
export const severityDot = (s) => DOT[s] ?? 'off';
