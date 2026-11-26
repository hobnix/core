// The state of the package index (`hs sys pkg index`: rows key, value; scripts/pkg-refresh.sh) turned into the one warning the top of the page shows.
// Same rules as `hs pkg list` (pkg-refresh.sh --warn): the index has expired; it was never fetched and the try failed; no fetch for 3 days.
// Installed packages keep running in every case; a null result means nothing to say (no state yet, or all is well).
const DAY = 86400;

export function indexState(list) {
  const m = {};
  for (const r of Array.isArray(list) ? list : []) if (Array.isArray(r) && r.length >= 2) m[r[0]] = r[1];
  return m;
}

const num = (v) => (v && v !== '-' && Number.isFinite(Number(v)) ? Number(v) : null);
const day = (t) => new Date(t * 1000).toISOString().slice(0, 10);

// { tone: 'warn', text } or null; `now` in epoch seconds
export function indexWarning(list, now = Date.now() / 1000) {
  const s = indexState(list);
  if (!Object.keys(s).length) return null;
  const exp = num(s.expires), ok = num(s.last_ok);
  const err = s.error && s.error !== '-' ? s.error : '';
  if (exp !== null && now > exp) return { tone: 'warn', text: `The package index expired on ${day(exp)}. Fetch a new one with hs pkg refresh. Installed packages keep running.` };
  if (ok === null && err) return { tone: 'warn', text: `The package index has not been fetched yet: ${err}. Installed packages keep running.` };
  if (ok !== null && now - ok > 3 * DAY) return { tone: 'warn', text: `The package index could not be fetched since ${day(ok)}${err ? `: ${err}` : ''}. Installed packages keep running.` };
  return null;
}
