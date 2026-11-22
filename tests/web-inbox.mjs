// ErrorNote (web/src/ui/errornote.js) and the Inbox (web/src/shell/inbox.js), run with node.
import { resolveError, guideHref, offersReload } from '../web/src/ui/errornote.js';
import { problemItems, notificationItems, bellCount, newestId, eventHref } from '../web/src/shell/inbox.js';
let bad = 0;
const eq = (n, g, w) => { if (JSON.stringify(g) === JSON.stringify(w)) console.log(`  ok    ${n}`); else { bad++; console.log(`  FAIL  ${n}: got ${JSON.stringify(g)}, want ${JSON.stringify(w)}`); } };

const k = resolveError({ code: 'disk.full', what: 'Could not write' });
eq('a known code brings reason, next step and guide', [k.known, !!k.why, !!k.next, k.guide], [true, true, true, 'storage#free-up-space']);
eq('what the server sent wins over the catalogue', resolveError({ code: 'disk.full', why: 'Because.' }).why, 'Because.');
const u = resolveError({ code: 'x.never-heard', text: 'It broke' });
eq('an unknown code shows the English text only', [u.known, u.what, u.why, u.next, u.guide, u.code], [false, 'It broke', '', '', '', 'x.never-heard']);
eq('a code named like an object property is unknown', resolveError({ code: 'constructor' }).known, false);
eq('- is empty', resolveError({ code: '-', what: 'oops', why: '-' }).why, '');
eq('guide link, en', guideHref('storage#free-up-space'), '/docs/en/storage#free-up-space');
eq('guide link, de', guideHref('storage', 'de'), '/docs/de/storage');
eq('a javascript: guide is no link', guideHref('javascript:alert(1)'), '');
eq('an https guide is kept', guideHref('https://example.org/x'), 'https://example.org/x');

// PlanDialog (#488): the reload offer follows the code; the English match is the fallback; an unknown code keeps the plan's own text.
eq('reload offered by code', offersReload('plan.changed', 'x'), true);
eq('reload offered by the old text', offersReload('', 'The disk changed meanwhile'), true);
eq('no reload for another refusal', offersReload('vault.locked', 'The vault is closed'), false);
const pl = resolveError({ code: 'vault.locked', what: 'The vault is closed.' });
eq('a plan code that is not catalogued shows its reason as sent', [pl.known, pl.what, pl.code], [false, 'The vault is closed.', 'vault.locked']);

const rows = [['p1', 'SMART of sdb is failing. Details: x', '-', '100', '-'], ['p2', 'last successful backup is 30 hours old', 'acked', '90', '-'], ['mitigation:paused', 'paused', '-', '1', '-'], ['p3', 'a unit failed', '-', '80', '-']];
const ps = problemItems(rows);
eq('unacknowledged first, the pause row left out', ps.map((p) => [p.id, p.acked]), [['p1', false], ['p3', false], ['p2', true]]);
eq('a problem links to its object, else the Health page', ps.map((p) => p.href), ['/storage/disks', '/operations/health', '/protection/backup']);
eq('an acknowledgement with an end carries it', problemItems([['p9', 'x', 'acked', '5', '-', '1700000000', 'ann']])[0].until, 1700000000);
eq('no end is 0', ps[0].until, 0);
const ev = [
  { id: 5, time: 1, source: 'job', kind: 'failed', subject: 'hs-x', level: 'error', text: '', payload: { exit: 2 } },
  { id: 6, time: 2, source: 'job', kind: 'ok', subject: 'hs-y', level: 'info', text: '', payload: null },
  { id: 7, time: 3, source: 'health', kind: 'new', subject: 'p1', level: 'warn', text: 'x', payload: null },
  { id: 8, time: 4, source: 'storage', kind: 'pool-fault', subject: 'tank', level: 'warn', text: 'pool fault', payload: null },
];
const ns = notificationItems(ev);
eq('warn and error only, health and audit rows left out, newest first', ns.map((n) => n.id), [8, 5]);
eq('a notification links to its object', ns.map((n) => n.href), ['/storage/pools/tank', '/operations/jobs']);
eq('the count leaves out acknowledged problems', bellCount(ps, ns, 0), 2 + 2);
eq('read notifications drop out of the count', bellCount(ps, ns, newestId(ns)), 2);
eq('an unknown source goes to the event log', eventHref({ source: 'pkg.x', subject: 's' }), '/operations/events');
process.exit(bad ? 1 : 0);
