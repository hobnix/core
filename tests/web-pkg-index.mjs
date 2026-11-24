// The package index warning (web/src/pages/pkgindex.js) from the rows of `hs sys pkg index`, and that the chip follows the event.
import { readFileSync } from 'node:fs';
import { indexWarning } from '../web/src/pages/pkgindex.js';

let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

const now = 1800000000, day = 86400;
const rows = (o) => Object.entries(o).map(([k, v]) => [k, String(v)]);
const fine = rows({ repo: 'official', last_ok: now - 3600, last_try: now - 3600, error: '-', expires: now + 10 * day, notified: '-' });

check('no state yet: no warning, no throw', indexWarning([], now) === null && indexWarning(undefined, now) === null);
check('a recent fetch: no warning', indexWarning(fine, now) === null);
check('the last fetch is 4 days old: a warning with the date and the reason', /could not be fetched since 2027-01-1\d: no route/.test(indexWarning(rows({ last_ok: now - 4 * day, error: 'no route', expires: now + 5 * day }), now)?.text));
check('2 days old: no warning', indexWarning(rows({ last_ok: now - 2 * day, error: 'x', expires: '-' }), now) === null);
check('never fetched and the try failed: a warning', /not been fetched yet: dns/.test(indexWarning(rows({ last_ok: '-', error: 'dns', expires: '-' }), now)?.text));
check('never fetched and no error: no warning', indexWarning(rows({ last_ok: '-', error: '-', expires: '-' }), now) === null);
check('an expired index: a warning that says hs pkg refresh', /expired on 2027-01-1\d.*hs pkg refresh/.test(indexWarning(rows({ last_ok: now, error: '-', expires: now - day }), now)?.text));
check('unknown expiry (-) is not expired', indexWarning(rows({ last_ok: now, error: '-', expires: '-' }), now) === null);

const shell = readFileSync(new URL('../web/src/shell/Shell.svelte', import.meta.url), 'utf8');
check('the top-bar update count follows the live topic system-updates', /'\/api\/sys\/system\/updates'\), 60000, 'system-updates'\)/.test(shell));
check('the warning reads hs sys pkg index through the topic pkg-index', /\/api\/sys\/pkg\/index.*'pkg-index'/.test(shell));
const topics = readFileSync(new URL('../scripts/lib/event-topics.tsv', import.meta.url), 'utf8').split('\n').filter((l) => /^index\.(changed|failed)\t/.test(l));
check('index.changed and index.failed wake the update count, the Apps versions and the warning',
  topics.length === 2 && topics.every((l) => ['system-updates', 'recipes-versions', 'pkg-index', 'pkg-market'].every((t) => l.split('\t')[1].split(',').includes(t))));

console.log(`${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
