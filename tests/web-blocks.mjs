// The pure logic of the chart and stat blocks (#473): chartSeries and statTiles in web/src/shell/generic.js.
import { chartSeries, statTiles } from '../web/src/shell/generic.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const rows = [['a', '10'], ['b', '20'], ['c', '-'], ['d', 'x'], ['e', '40']];
const s = chartSeries(rows, 1, 0, 0);
eq('empty, dash and non-numbers are skipped', s.values.length, 3);
eq('default max is the highest point', s.max, 40);
eq('points scale to percent', s.values, [25, 50, 100]);
eq('last is the newest point', s.last, 40);
eq('no hot means never hot', s.hot > 100, true);
eq('declared max scales', chartSeries(rows, 1, 200, 0).values, [5, 10, 20]);
eq('hot becomes a percentage', chartSeries(rows, 1, 100, 80).hot, 80);
eq('over max is clamped', chartSeries([['a', '500']], 1, 100).values, [100]);
eq('no rows: no values, no last, max 100', chartSeries([], 1), { values: [], last: null, max: 100, hot: 101 });
eq('a column other than 1', chartSeries([['5', '9']], 0, 10).values, [50]);

const t = statTiles(['12', '2048', 'up', '-'], [
  { label: 'Up', col: 0, unit: 'days' },
  { label: 'Disk', col: 1, fmt: 'bytes' },
  { label: 'Svc', col: 2, map: { up: ['ok', 'running'] } },
  { label: 'Q', col: 3, unit: 'items' },
  { label: 'Svc2', col: 2, map: { down: ['bad', 'stopped'] } },
]);
eq('value and unit', [t[0].value, t[0].unit, t[0].dot], ['12', 'days', null]);
eq('fmt applies', t[1].value !== '' && t[1].value !== '2048', true);
eq('a mapped value gets a dot', t[2].dot, ['ok', 'running']);
eq('a dash is empty and has no unit', [t[3].value, t[3].unit], ['', '']);
eq('an unmapped value is off with the value as word', t[4].dot, ['off', 'up']);
eq('no row: tiles with empty values', statTiles(null, [{ label: 'A' }]).map((x) => x.value), ['']);
eq('no items: no tiles', statTiles(['1'], []), []);

console.log(`  ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
