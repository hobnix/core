// The rates of the network map page (web/src/netmap/rates.js, #877) and the made-up counters of demo mode (web/demo/engine.js netmapFrame), run with node.
import { ratesFrom, graphOf, hrefOf } from '../web/src/netmap/rates.js';
import { fixture, netmapFrame } from '../web/demo/engine.js';
import { layoutGraph } from '../web/src/netmap/layout.js';

let bad = 0, ok = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

const a = { t: 1000, rows: [['wan', '0', '0'], ['host', '1000', '500'], ['bridge:br0', '-', '10'], ['instance:x', '5', '5']] };
const b = { t: 3000, rows: [['wan', '4000', '2000'], ['host', '1000', '400'], ['bridge:br0', '50', '30'], ['instance:y', '1', '1']] };
const r = ratesFrom(a, b);
check('bytes per second from two readings', r.wan.rx === 2000 && r.wan.tx === 1000);
check('a counter that stands still is a zero rate', r.host.rx === 0);
check('a counter that went down (reset) gives no value for that side', r.host.tx === undefined);
check('a `-` gives no value, the other side stays', r['bridge:br0'].rx === undefined && r['bridge:br0'].tx === 10);
check('a node missing from one reading has no entry', !('instance:x' in r) && !('instance:y' in r));
check('no previous reading, or no time between: no rates', Object.keys(ratesFrom(null, b)).length === 0 && Object.keys(ratesFrom(b, { ...b })).length === 0);

const fx = fixture('healthy');
const g = graphOf(fx.reads['netmap/topology']);
check('the demo graph has the chain and more than ten nodes', g.length > 10 && ['wan', 'gateway', 'host'].every((id) => g.some((n) => n.id === id)));
check('every demo node lays out (no orphan)', layoutGraph(g).nodes.length === g.length);
check('hrefOf: instance, service, host and bridge have a page, an unknown kind none', hrefOf({ kind: 'instance' }) && hrefOf({ kind: 'service' }) && hrefOf({ kind: 'host' }) && hrefOf({ kind: 'bridge' }) && hrefOf({ kind: 'x' }) === '');

const f1 = netmapFrame(fx, 1_000_000), f2 = netmapFrame(fx, 1_002_000), again = netmapFrame(fx, 1_000_000);
check('demo frames: same time, same frame', JSON.stringify(f1) === JSON.stringify(again));
const ids = new Set(g.map((n) => n.id));
check('demo frames name only nodes of the graph', f1.rows.length > 5 && f1.rows.every((x) => ids.has(x[0])));
const dr = ratesFrom(f1, f2);
check('demo frames: every running node has traffic, a stopped one none', f1.rows.every((x) => {
  const stopped = g.find((n) => n.id === x[0]).state === 'stopped';
  return stopped ? dr[x[0]].rx === 0 : dr[x[0]].rx > 0 && dr[x[0]].tx > 0;
}));
check('demo counters only grow over a minute', Array.from({ length: 30 }, (_, i) => i).every((i) => {
  const p = netmapFrame(fx, 5e6 + i * 2000), q = netmapFrame(fx, 5e6 + (i + 1) * 2000);
  return q.rows.every((row, k) => Number(row[1]) >= Number(p.rows[k][1]) && Number(row[2]) >= Number(p.rows[k][2]));
}));

console.log(`  -> ${ok} checks`);
process.exit(bad ? 1 : 0);
