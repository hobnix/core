// Keyboard moves and node facts of the network map (web/src/netmap/access.js, #876). Run with node.
import { layoutGraph } from '../web/src/netmap/layout.js';
import { moveFocus, factsOf, readingOrder } from '../web/src/netmap/access.js';
import { SMALL, SMALL_RATES, big } from '../web/src/netmap/fixtures.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) ok++; else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

const lay = layoutGraph(SMALL);
const order = readingOrder(lay);
const lastOfTier0 = order.filter((n) => n.tier === 0).pop().id;
eq('down from wan goes to the gateway', moveFocus(lay, 'wan', 'ArrowDown'), 'gw');
eq('up from the gateway goes to wan', moveFocus(lay, 'gw', 'ArrowUp'), 'wan');
eq('up from a root stays', moveFocus(lay, 'wan', 'ArrowUp'), 'wan');
eq('down from a leaf stays', moveFocus(lay, 'nc-web', 'ArrowDown'), 'nc-web');
eq('right moves along the tier', moveFocus(lay, 'media', 'ArrowRight'), 'nextcloud');
eq('left at the start of a tier stays', moveFocus(lay, 'media', 'ArrowLeft'), 'media');
eq('right at the end of a tier does not leave it', moveFocus(lay, lastOfTier0, 'ArrowRight'), lastOfTier0);
eq('Home is the first node', moveFocus(lay, 'media', 'Home'), order[0].id);
eq('End is the last node', moveFocus(lay, 'media', 'End'), order[order.length - 1].id);
eq('an unknown id goes to the first node', moveFocus(lay, 'gone', 'ArrowDown'), order[0].id);
eq('another key stays', moveFocus(lay, 'media', 'x'), 'media');
eq('an empty graph gives no id', moveFocus(layoutGraph([]), 'a', 'Home'), '');

// Every node of the 100-node graph can be reached: from the first node, walk down and sideways.
const bl = layoutGraph(big(100).graph);
const seen = new Set([readingOrder(bl)[0].id]);
const todo = [...seen];
while (todo.length) {
  const id = todo.pop();
  for (const key of ['ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowUp']) { const nx = moveFocus(bl, id, key); if (!seen.has(nx)) { seen.add(nx); todo.push(nx); } }
}
eq('arrows reach every one of 100 nodes', seen.size, bl.nodes.length);

const nc = factsOf(lay, lay.nodes.find((n) => n.id === 'nextcloud'), SMALL_RATES);
eq('facts: name for the screen reader', nc.text, 'nextcloud, instance, running, receiving 2.4 MB/s, sending 90.0 KB/s, 1 service');
eq('facts: services', nc.services, ['cloud.example.org']);
eq('facts: parent', nc.parent, 'br0');
const old = factsOf(lay, lay.nodes.find((n) => n.id === 'old'), SMALL_RATES);
eq('facts: no rates are said so', old.text, 'old-vm, instance, stopped, no rates');
eq('facts: a node with no state', factsOf(lay, { id: 'x', label: 'x', kind: '', state: '' }, {}).text, 'x, node, unknown, no rates');
console.log(`  -> ${ok} checks`);
console.log(`  ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
