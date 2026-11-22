// Layout of the network map (#874, docs/PLAN-network-map.md part 3): a graph goes in, positions come out. Pure: no DOM, no timers, no random,
// the same input always gives the same output, and the input is never changed.
//
//   layoutGraph(graph, options?) -> { empty, width, height, nodes, links, tiers }
//
// Input: an array of rows, or { nodes: [rows] }. A row is what `hs sys netmap` (#872) prints, as an object:
//   { id, kind, parent, label, state, rx_bytes, tx_bytes }   ('-', '' or a missing field is "none"; only `id` is needed)
// Kinds with a known look: wan, gateway, host, bridge, instance, service. Any other kind is drawn as a generic node (known: false).
//
// Tiers: the tier of a node is its depth below its root (a node with no parent, or whose parent is not in the graph, is a root at tier 0).
// A parent cycle is cut at the member with the smallest id, which becomes a root. Disconnected components sit side by side at tier 0.
// Within a tier, children stay together under their parent's order; siblings are sorted by kind (KINDS order), label, id. A tier wider than
// `perRow` nodes wraps into more rows; every row is centred and its nodes are evenly spaced.
//
// Output: nodes [{ id, kind, known, tier, row, x, y, w, h, label, state, data }] (x, y = top-left corner), links [{ from, to, x1, y1, x2, y2 }]
// (parent bottom-centre to child top-centre), tiers [{ tier, y, rows }], and the size of the drawing. Rows of the input with no id or a repeated
// id (the first wins) are dropped. An empty graph gives { empty: true } with no nodes: the page shows its empty state.
export const KINDS = ['wan', 'gateway', 'host', 'bridge', 'instance', 'service'];
const DEFAULTS = { nodeW: 160, nodeH: 56, gapX: 24, gapY: 56, rowGap: 24, perRow: 8, pad: 16 };

const none = (v) => v === undefined || v === null || v === '' || v === '-';
const text = (v) => (none(v) ? '' : String(v));
const rank = (kind) => { const i = KINDS.indexOf(kind); return i < 0 ? KINDS.length : i; };
const cmpStr = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const order = (a, b) => rank(a.kind) - rank(b.kind) || cmpStr(a.label, b.label) || cmpStr(a.id, b.id);

function normalize(graph) {
  const list = Array.isArray(graph) ? graph : graph && Array.isArray(graph.nodes) ? graph.nodes : [];
  const byId = new Map();
  for (const r of list) {
    if (!r || none(r.id)) continue;
    const id = String(r.id);
    if (byId.has(id)) continue;
    const label = text(r.label);
    byId.set(id, { id, kind: text(r.kind), parent: text(r.parent), label: label || id, state: text(r.state), data: r });
  }
  return byId;
}

// Drops parents that are missing, are the node itself, or close a cycle (cut at the smallest id of the cycle).
function cutParents(byId) {
  const ids = [...byId.keys()].sort(cmpStr);
  for (const n of byId.values()) if (n.parent === n.id || !byId.has(n.parent)) n.parent = '';
  const done = new Set();
  for (const start of ids) {
    if (done.has(start)) continue;
    const path = [];
    const at = new Map();
    let cur = start;
    while (cur && !done.has(cur) && !at.has(cur)) { at.set(cur, path.length); path.push(cur); cur = byId.get(cur).parent; }
    if (cur && at.has(cur)) {
      const cycle = path.slice(at.get(cur)).sort(cmpStr);
      byId.get(cycle[0]).parent = '';
    }
    for (const id of path) done.add(id);
  }
}

export function layoutGraph(graph, options) {
  const o = { ...DEFAULTS, ...(options || {}) };
  const perRow = Math.max(1, Math.floor(o.perRow));
  const byId = normalize(graph);
  if (!byId.size) return { empty: true, width: 0, height: 0, nodes: [], links: [], tiers: [] };
  cutParents(byId);

  const kids = new Map();
  const roots = [];
  for (const n of byId.values()) {
    if (!n.parent) roots.push(n);
    else (kids.get(n.parent) || kids.set(n.parent, []).get(n.parent)).push(n);
  }
  roots.sort(order);
  for (const k of kids.values()) k.sort(order);

  // Tier by tier, children in the order of their parents.
  const tiers = [];
  let level = roots;
  while (level.length) {
    tiers.push(level);
    const next = [];
    for (const n of level) for (const c of kids.get(n.id) || []) next.push(c);
    level = next;
  }

  const stepX = o.nodeW + o.gapX;
  const widest = Math.min(perRow, Math.max(...tiers.map((t) => t.length)));
  const innerW = widest * o.nodeW + (widest - 1) * o.gapX;
  const width = innerW + 2 * o.pad;
  const pos = new Map();
  const tierInfo = [];
  let y = o.pad;
  tiers.forEach((members, tier) => {
    const rows = Math.ceil(members.length / perRow);
    tierInfo.push({ tier, y, rows });
    for (let r = 0; r < rows; r++) {
      const row = members.slice(r * perRow, (r + 1) * perRow);
      const rowW = row.length * o.nodeW + (row.length - 1) * o.gapX;
      const x0 = o.pad + (innerW - rowW) / 2;
      row.forEach((n, i) => pos.set(n.id, { tier, row: r, x: x0 + i * stepX, y: y + r * (o.nodeH + o.rowGap) }));
    }
    y += rows * o.nodeH + (rows - 1) * o.rowGap + o.gapY;
  });
  const height = y - o.gapY + o.pad;

  const nodes = [];
  const links = [];
  for (const members of tiers) {
    for (const n of members) {
      const p = pos.get(n.id);
      nodes.push({ id: n.id, kind: n.kind, known: KINDS.includes(n.kind), tier: p.tier, row: p.row, x: p.x, y: p.y, w: o.nodeW, h: o.nodeH, label: n.label, state: n.state, data: n.data });
      if (n.parent) {
        const a = pos.get(n.parent);
        links.push({ from: n.parent, to: n.id, x1: a.x + o.nodeW / 2, y1: a.y + o.nodeH, x2: p.x + o.nodeW / 2, y2: p.y });
      }
    }
  }
  return { empty: false, width, height, nodes, links, tiers: tierInfo };
}
