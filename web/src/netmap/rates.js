import { P } from '../paths.js';
// Counters to rates for the network map page (#877). Plain JS, no runes, so that node can test it (tests/web-netmap-rates.mjs).
// A frame is what the counters stream sends: { t: epoch ms of the reading, rows: [[id, rx_bytes, tx_bytes], ...] } (totals, `-` = not readable).

const num = (v) => {
  if (v === '-' || v === '' || v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

// Two readings -> { [id]: { rx, tx } } bytes per second. A node missing from one reading, a `-`, a counter that went down (a reset) or two readings
// with no time between them give no entry for that side: no old value is ever shown as a rate.
export function ratesFrom(prev, cur) {
  const out = {};
  if (!prev || !cur) return out;
  const dt = (cur.t - prev.t) / 1000;
  if (!(dt > 0)) return out;
  const before = new Map((prev.rows || []).map((r) => [r[0], r]));
  for (const r of cur.rows || []) {
    const p = before.get(r[0]);
    if (!p) continue;
    const e = {};
    for (const [k, i] of [['rx', 1], ['tx', 2]]) {
      const a = num(p[i]), b = num(r[i]);
      if (a !== null && b !== null && b >= a) e[k] = (b - a) / dt;
    }
    if (Object.keys(e).length) out[r[0]] = e;
  }
  return out;
}

// The rows of `hs sys netmap` (arrays) -> the objects NetMap takes.
export const graphOf = (rows) => (rows || []).map((r) => ({ id: r[0], kind: r[1], parent: r[2], label: r[3], state: r[4], rx_bytes: r[5] ?? '-', tx_bytes: r[6] ?? '-' }));

// The inner path (paths.js) of a node's page, '' where there is none; the page puts the node in front with url() (route.svelte.js).
export function hrefOf(row) {
  switch (row.kind) {
    case 'instance': return P.appsGroup;
    case 'service': return P.services;
    case 'host': return P.hardware;
    case 'wan': case 'gateway': case 'bridge': return P.network;
    default: return '';
  }
}
