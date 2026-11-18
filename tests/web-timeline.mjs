// Timeline helpers (web/src/ui/timeline.js): order, day groups, severity dots.
import { newestFirst, dayKey, groupByDay, severityDot } from '../web/src/ui/timeline.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

const now = new Date(2026, 10, 18, 12, 0, 0).getTime();
const at = (d, h) => new Date(2026, 10, d, h, 0, 0).getTime() / 1000;

console.log('-- order');
const e = [{ id: 'a', time: at(18, 9) }, { id: 'b', time: at(18, 11) }, { id: 'c' }, { id: 'd', time: at(18, 9) }];
check('newest first, no time last, ties keep order', newestFirst(e).map((x) => x.id).join('') === 'badc', newestFirst(e).map((x) => x.id).join(''));
check('the input is not changed', e[0].id === 'a');
check('no list, no entries', newestFirst(undefined).length === 0);

console.log('-- days');
check('today and yesterday', dayKey(at(18, 1), now) === 'today' && dayKey(at(17, 23), now) === 'yesterday');
check('older day is a date key', dayKey(at(3, 10), now) === '2026-11-03');
check('no time, no day', dayKey(0, now) === '' && dayKey(undefined, now) === '' && dayKey('-', now) === '');
const g = groupByDay([{ id: 1, time: at(17, 8) }, { id: 2, time: at(18, 8) }, { id: 3, time: at(18, 10) }, { id: 4, time: at(3, 8) }, { id: 5 }], now);
check('groups: today, yesterday, date, unknown', g.map((x) => x.day).join('|') === 'today|yesterday|2026-11-03|', g.map((x) => x.day).join('|'));
check('today holds two, newest first', g[0].entries.map((x) => x.id).join('') === '32');

console.log('-- severity');
check('known words', severityDot('error') === 'bad' && severityDot('warn') === 'warn' && severityDot('info') === 'info' && severityDot('ok') === 'ok');
check('unknown is neutral', severityDot('weird') === 'off' && severityDot(undefined) === 'off');

console.log(`\n${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
