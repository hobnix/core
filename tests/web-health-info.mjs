// The info rows of package health checks (web/src/pages/healthinfo.js), run with node.
import { infoRows } from '../web/src/pages/healthinfo.js';
import { problemItems, bellCount } from '../web/src/shell/inbox.js';
let bad = 0;
const eq = (n, g, w) => { if (JSON.stringify(g) === JSON.stringify(w)) console.log(`  ok    ${n}`); else { bad++; console.log(`  FAIL  ${n}: got ${JSON.stringify(g)}, want ${JSON.stringify(w)}`); } };

eq('a row names its package, title and message', infoRows([['games', 'pc', 'Games', 'the PC is switched off']]), [{ key: 'games:pc', pkg: 'games', title: 'Games', text: 'the PC is switched off' }]);
eq('- is empty: the title falls back to the package', infoRows([['games', 'pc', '-', '-']]), [{ key: 'games:pc', pkg: 'games', title: 'games', text: '' }]);
eq('no rows, no list', [infoRows([]), infoRows(undefined)], [[], []]);
eq('a blank line is skipped', infoRows([[]]), []);
// the badge and the bell count problems and notifications only: the info rows are a separate read
eq('info rows are not problems', problemItems([]).length, 0);
eq('info rows do not count in the bell', bellCount(problemItems([]), []), 0);
if (bad) { console.log(`${bad} failed`); process.exit(1); }
