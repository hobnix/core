// Access to the network map without a mouse (#876, docs/PLAN-network-map.md part 5): pure functions, no DOM. The component feeds them the layout
// (layout.js) and the rates; they answer which node the arrow key goes to and which facts a node has (the same for the screen reader name,
// the detail popover and the table view, so the three never disagree).
import { bytes } from '../format.js';

// Nodes in reading order: tier, then row, then left to right.
export const readingOrder = (lay) => [...lay.nodes].sort((a, b) => a.tier - b.tier || a.row - b.row || a.x - b.x);

// The node a key moves to from `id` (the same id when there is nowhere to go):
//   ArrowLeft / ArrowRight  the previous / next node of the same tier (rows of a wrapped tier count as one line), no wrap-around
//   ArrowUp                 the parent        ArrowDown  the first child        Home / End  the first / last node in reading order
export function moveFocus(lay, id, key) {
  const all = readingOrder(lay);
  if (!all.length) return '';
  const at = all.findIndex((n) => n.id === id);
  if (at < 0 || key === 'Home') return all[0].id;
  if (key === 'End') return all[all.length - 1].id;
  const cur = all[at];
  if (key === 'ArrowLeft' || key === 'ArrowRight') {
    const nb = all[at + (key === 'ArrowLeft' ? -1 : 1)];
    return nb && nb.tier === cur.tier ? nb.id : id;
  }
  if (key === 'ArrowUp') { const l = lay.links.find((x) => x.to === id); return l ? l.from : id; }
  if (key === 'ArrowDown') { const kids = new Set(lay.links.filter((x) => x.from === id).map((x) => x.to)); const k = all.find((n) => kids.has(n.id)); return k ? k.id : id; }
  return id;
}

const num = (v) => (typeof v === 'number' && v > 0 && isFinite(v) ? v : 0);
export const rate = (v) => (num(v) ? `${bytes(v)}/s` : '0 B/s');

// The facts of one node: { id, name, kind, state, rx, tx, services: [label], parent, text }. `rates` as for the map; no entry = no traffic known.
export function factsOf(lay, node, rates) {
  const r = (rates && rates[node.id]) || null;
  const kids = new Set(lay.links.filter((x) => x.from === node.id).map((x) => x.to));
  const parent = lay.links.find((x) => x.to === node.id);
  const byId = new Map(lay.nodes.map((n) => [n.id, n]));
  const services = readingOrder(lay).filter((n) => kids.has(n.id) && n.kind === 'service').map((n) => n.label);
  const kind = node.kind || 'node';
  const state = node.state || 'unknown';
  const rx = r ? rate(r.rx) : '–', tx = r ? rate(r.tx) : '–';
  const text = `${node.label}, ${kind}, ${state}` + (r ? `, receiving ${rx}, sending ${tx}` : ', no rates') + (services.length ? `, ${services.length} ${services.length === 1 ? 'service' : 'services'}` : '');
  return { id: node.id, name: node.label, kind, state, rx, tx, services, parent: parent && byId.get(parent.from) ? byId.get(parent.from).label : '', text };
}
