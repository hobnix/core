// The coded error of #488, as plain functions (tests/web-inbox.mjs runs them with node). One shape for a refused plan, a failed job and a page that
// cannot read: { code, what, why, next, guide }. `what` is the English text the server sent. A code the web knows may bring its own `why`, `next` and
// `guide`; a code it does not know shows the English text as it came and nothing else. Nothing here is HTML: the parts are shown as plain text.

// code -> { why, next, guide } for the codes the web knows. Add a code here when its guide section exists. `next` is one command or one page.
export const KNOWN = {
  'disk.full': { why: 'The disk has no free space left.', next: 'hs disk <disk> health', guide: 'storage#free-up-space' },
};

const clean = (v) => (v == null || v === '-' ? '' : String(v).trim());

// The guide link: `slug#section` -> /docs/<lang>/slug#section of the web interface; an absolute http(s) address is kept; anything else is no link.
export function guideHref(guide, lang = 'en') {
  const g = clean(guide);
  if (!g) return '';
  if (/^https?:\/\//i.test(g)) return g;
  if (/^[a-z0-9][a-z0-9-]*(#[a-z0-9-]+)?$/i.test(g)) return `/docs/${lang === 'de' ? 'de' : 'en'}/${g}`;
  return '';
}

// -> { code, what, why, next, guide, known }. A field the caller sets wins over the catalogue, so a server that sends the full shape is shown as sent.
export function resolveError(e = {}) {
  const code = clean(e.code);
  const k = Object.hasOwn(KNOWN, code) ? KNOWN[code] : null;
  return {
    code,
    what: clean(e.what) || clean(e.text) || clean(e.message) || code,
    why: clean(e.why) || k?.why || '',
    next: clean(e.next) || k?.next || '',
    guide: clean(e.guide) || k?.guide || '',
    known: !!k,
  };
}

// The "reload" offer of a plan that changed meanwhile (ADR 0028 point 6: act on the code, not the text). The code name is not in a catalogue yet
// (scripts/lib/error-codes.tsv comes with the scripts half of #488, 0.12); until a script prints it, the old English match stays as the fallback.
export const RELOAD_CODES = ['plan.changed'];
export const offersReload = (code, text = '') => RELOAD_CODES.includes(clean(code)) || String(text ?? '').includes('changed meanwhile');
