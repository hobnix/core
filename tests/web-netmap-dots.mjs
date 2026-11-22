// The traffic dots of the network map (web/src/netmap/dots.js, paint.js, #875), run with node: no browser. Also times the work of one frame for 100 nodes.
import { layoutGraph } from '../web/src/netmap/layout.js';
import { dotCount, dotSpeed, thickness, flowsFor, dotFractions, MAX_DOTS } from '../web/src/netmap/dots.js';
import { paintDots } from '../web/src/netmap/paint.js';
import { SMALL, SMALL_RATES, big } from '../web/src/netmap/fixtures.js';

let bad = 0, ok = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

check('no dots at zero, missing or odd rates', [0, undefined, null, -5, NaN, Infinity, '12'].every((r) => dotCount(r) === 0 && dotSpeed(r) === 0 && thickness(r) === 1));
check('dots grow with the rate and stop at the maximum', dotCount(100) >= 1 && dotCount(1e6) > dotCount(1e3) && dotCount(1e15) === MAX_DOTS);
check('speed grows with the rate and is capped', dotSpeed(1e6) > dotSpeed(1e3) && dotSpeed(1e15) === 160);
check('thickness grows with the rate and is capped', thickness(1e6) > thickness(1e3) && thickness(1e3) > 1 && thickness(1e15) === 6);

const lay = layoutGraph(SMALL);
const flows = flowsFor(lay.links, SMALL_RATES);
check('a link with no rate has no flow', !flows.some((f) => f.id === 'old') && flowsFor(lay.links, {}).length === 0 && flowsFor(lay.links, undefined).length === 0);
check('a link with a rate has a flow with dots', flows.length > 0 && flows.every((f) => f.nRx + f.nTx > 0 && f.len > 0));
check('a rate of only tx gives dots up, none down', (() => { const f = flowsFor(lay.links, { media: { rx: 0, tx: 5e5 } })[0]; return f.nRx === 0 && f.nTx > 0; })());

const f = dotFractions(100, 4, 40, 0.5, false);
check('fractions: n dots, all inside 0..1, evenly spaced', f.length === 4 && f.every((p) => p >= 0 && p < 1) && Math.abs(f[1] - f[0] - 0.25) < 1e-9);
check('fractions move forward with time, back when up', dotFractions(100, 1, 40, 1, false)[0] > dotFractions(100, 1, 40, 0, false)[0] && dotFractions(100, 1, 40, 1, true)[0] < dotFractions(100, 1, 40, 0, true)[0]);
check('fractions repeat after one gap', Math.abs(dotFractions(100, 2, 50, 1, false)[0] - dotFractions(100, 2, 50, 0, false)[0]) < 1e-9);
check('none for n = 0', dotFractions(100, 0, 40, 1, false).length === 0);

// paint with a recording context
const calls = { arc: 0, fill: 0, begin: 0, style: [] };
const ctx = { beginPath() { calls.begin++; }, moveTo() {}, arc() { calls.arc++; }, fill() { calls.fill++; }, set fillStyle(v) { calls.style.push(v); } };
paintDots(ctx, flows, 1.5, { rx: 'A', tx: 'B' });
const expect = flows.reduce((s, x) => s + x.nRx + x.nTx, 0);
check('paint: one path and one fill per direction, one arc per dot', calls.begin === 2 && calls.fill === 2 && calls.arc === expect && calls.style.join('') === 'AB');
const c2 = { arc: 0, fill: 0 }; paintDots({ beginPath() {}, moveTo() {}, arc() { c2.arc++; }, fill() { c2.fill++; }, set fillStyle(v) {} }, [], 0, { rx: 'A', tx: 'B' });
check('paint: no flows, no dots', c2.arc === 0);

// 100 nodes: the work of one frame (flows are made once per data change, the dots once per frame)
const b = big(100);
const bl = layoutGraph(b.graph);
check('the big fixture has 100 nodes', bl.nodes.length === 100);
const T0 = performance.now(); for (let i = 0; i < 100; i++) layoutGraph(b.graph); const tLayout = (performance.now() - T0) / 100;
const T1 = performance.now(); let bf; for (let i = 0; i < 100; i++) bf = flowsFor(bl.links, b.rates); const tFlows = (performance.now() - T1) / 100;
let arcs = 0; const cn = { beginPath() {}, moveTo() {}, arc() { arcs++; }, fill() {}, set fillStyle(v) {} };
for (let i = 0; i < 50; i++) paintDots(cn, bf, i / 30, { rx: 'A', tx: 'B' });   // warm up
arcs = 0;
const T2 = performance.now(); for (let i = 0; i < 300; i++) paintDots(cn, bf, i / 30, { rx: 'A', tx: 'B' }); const tFrame = (performance.now() - T2) / 300;
console.log(`  -> 100 nodes: layout ${tLayout.toFixed(3)} ms, flows ${tFlows.toFixed(3)} ms, one frame of dots (${Math.round(arcs / 300)} dots, no canvas) ${tFrame.toFixed(3)} ms`);
check('one frame of dots for 100 nodes computes in well under a frame (< 4 ms)', tFrame < 4);

console.log(`  ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
