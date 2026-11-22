// The layout of the network map (web/src/netmap/layout.js, #874), run with node: no browser.
import { layoutGraph, KINDS } from '../web/src/netmap/layout.js';

let bad = 0, ok = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };
const n = (id, kind, parent = '-', label = '-') => ({ id, kind, parent, label, state: '-', rx_bytes: '-', tx_bytes: '-' });
const at = (g, id) => g.nodes.find((x) => x.id === id);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const ids = (g, tier) => g.nodes.filter((x) => x.tier === tier).sort((p, q) => p.x - q.x).map((x) => x.id).join('');

const e = layoutGraph([]);
check('empty graph: empty state, no nodes', e.empty === true && e.nodes.length === 0 && e.links.length === 0 && e.width === 0);
check('missing or odd input is empty too', layoutGraph(undefined).empty && layoutGraph(null).empty && layoutGraph({}).empty && layoutGraph([{ kind: 'wan' }, null, n('-', 'wan')]).empty);

const one = layoutGraph([n('a', 'wan', '-', 'Provider')]);
check('single node: tier 0, centred in the drawing', one.nodes.length === 1 && one.nodes[0].tier === 0 && one.nodes[0].x * 2 + one.nodes[0].w === one.width && one.links.length === 0 && !one.empty);

const chain = [n('wan', 'wan'), n('gw', 'gateway', 'wan'), n('host', 'host', 'gw'), n('br0', 'bridge', 'host'), n('c1', 'instance', 'br0'), n('s1', 'service', 'c1')];
const g = layoutGraph(chain);
check('tiers go down from the root, in rows below each other', ['wan', 'gw', 'host', 'br0', 'c1', 's1'].every((id, i) => at(g, id).tier === i) && at(g, 'gw').y > at(g, 'wan').y && at(g, 's1').y > at(g, 'c1').y);
check('one link per parent edge, from the parent bottom to the child top', g.links.length === 5 && g.links.every((l) => l.y2 > l.y1));
check('the size holds every node', g.nodes.every((x) => x.x >= 0 && x.y >= 0 && x.x + x.w <= g.width && x.y + x.h <= g.height));

const kids = [n('h', 'host'), ...['d', 'b', 'c', 'a'].map((i) => n(i, 'instance', 'h', i))];
const k = layoutGraph(kids);
const row = k.nodes.filter((x) => x.tier === 1).sort((a, b) => a.x - b.x);
check('siblings are ordered by label and spaced evenly', row.map((x) => x.id).join('') === 'abcd' && new Set(row.slice(1).map((x, i) => x.x - row[i].x)).size === 1);
check('the input order does not matter', same(layoutGraph(kids).nodes, layoutGraph([...kids].reverse()).nodes));

const wide = [n('h', 'host'), ...Array.from({ length: 20 }, (_, i) => n('i' + String(i).padStart(2, '0'), 'instance', 'h'))];
const w = layoutGraph(wide, { perRow: 8 });
const ys = new Set(w.nodes.filter((x) => x.tier === 1).map((x) => x.y));
check('a wide tier wraps into rows of at most perRow', ys.size === 3 && w.tiers[1].rows === 3 && w.nodes.every((x) => x.x >= 0 && x.x + x.w <= w.width));
check('the last wrapped row is centred', (() => { const last = w.nodes.filter((x) => x.tier === 1 && x.row === 2); return last.length === 4 && Math.abs((last[0].x + last[3].x + last[3].w) / 2 - w.width / 2) < 1e-9; })());
check('perRow below 1 is treated as 1', layoutGraph(wide, { perRow: 0 }).tiers[1].rows === 20);

const gen = layoutGraph([n('h', 'host'), n('x', 'toaster', 'h', 'Mystery')]);
check('an unknown kind is a generic node, a known one is not', at(gen, 'x').known === false && at(gen, 'h').known === true && at(gen, 'x').tier === 1 && at(gen, 'x').label === 'Mystery');
check('the label falls back to the id', at(layoutGraph([n('solo', 'wan')]), 'solo').label === 'solo');
check('every kind of the plan is known', KINDS.every((kd) => layoutGraph([n('a', kd)]).nodes[0].known));

const cyc = layoutGraph([n('a', 'host', 'c'), n('b', 'bridge', 'a'), n('c', 'instance', 'b'), n('d', 'service', 'c')]);
check('a cycle is cut at the smallest id, nothing is lost', cyc.nodes.length === 4 && at(cyc, 'a').tier === 0 && at(cyc, 'b').tier === 1 && at(cyc, 'c').tier === 2 && at(cyc, 'd').tier === 3);
check('a node that is its own parent is a root', at(layoutGraph([n('a', 'host', 'a')]), 'a').tier === 0);
check('a parent that is not in the graph makes a root', at(layoutGraph([n('a', 'instance', 'ghost')]), 'a').tier === 0);

const dis = layoutGraph([n('w1', 'wan'), n('g1', 'gateway', 'w1'), n('w2', 'wan'), n('g2', 'gateway', 'w2'), n('lone', 'instance')]);
check('disconnected components share tier 0 side by side', ['w1', 'w2', 'lone'].every((id) => at(dis, id).tier === 0 && at(dis, id).y === at(dis, 'w1').y) && new Set(['w1', 'w2', 'lone'].map((id) => at(dis, id).x)).size === 3);
check('each child follows its own parent', at(dis, 'g1').x < at(dis, 'g2').x && at(dis, 'g1').tier === 1);

const dup = layoutGraph([n('a', 'wan', '-', 'first'), n('a', 'host', '-', 'second')]);
check('a repeated id keeps the first row', dup.nodes.length === 1 && dup.nodes[0].label === 'first');

const input = JSON.stringify(chain);
layoutGraph(chain);
check('the input is not changed', JSON.stringify(chain) === input);
check('same input, same output', same(layoutGraph(chain), layoutGraph(JSON.parse(input))));
check('an object with nodes works like an array', same(layoutGraph({ nodes: chain }), layoutGraph(chain)));

// Stability: a small change moves only what must move.
const base = [n('w', 'wan'), n('g', 'gateway', 'w'), n('h', 'host', 'g'), ...['a', 'b', 'c'].map((i) => n(i, 'instance', 'h', i))];
const b0 = layoutGraph(base);
const b1 = layoutGraph(base.map((r) => (r.id === 'b' ? { ...r, state: 'running', rx_bytes: '99' } : r)));
check('a state or counter change moves nothing', same(b0.nodes.map((x) => [x.id, x.x, x.y]), b1.nodes.map((x) => [x.id, x.x, x.y])) && b0.width === b1.width);
const b2 = layoutGraph([...base, n('d', 'instance', 'h', 'd')]);
check('a node added to a tier leaves the other tiers where they are', ['w', 'g', 'h'].every((id) => at(b0, id).y === at(b2, id).y) && at(b2, 'a').y === at(b0, 'a').y);
check('the tier keeps its order after an addition', ids(b2, 3) === 'abcd');
const b3 = layoutGraph(base.filter((r) => r.id !== 'c'));
check('removing a node keeps the order of the rest', ids(b3, 3) === 'ab' && at(b3, 'h').y === at(b0, 'h').y);

const dozens = [n('w', 'wan'), n('g', 'gateway', 'w'), n('h', 'host', 'g'), n('br0', 'bridge', 'h'), ...Array.from({ length: 40 }, (_, i) => n('c' + i, 'instance', 'br0')), ...Array.from({ length: 40 }, (_, i) => n('s' + i, 'service', 'c' + i))];
const big = layoutGraph(dozens);
const boxes = big.nodes;
const clash = boxes.some((p, i) => boxes.some((q, j) => j > i && p.x < q.x + q.w && q.x < p.x + p.w && p.y < q.y + q.h && q.y < p.y + p.h));
check('a few dozen nodes: all placed, none overlapping', boxes.length === dozens.length && !clash);

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
