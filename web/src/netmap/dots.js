// The traffic dots of the network map (#875, docs/PLAN-network-map.md part 4): pure functions, no DOM, no timers. The component feeds them the
// layout (layout.js) and the rates and asks, per frame, where each dot is. A rate is bytes per second; the page takes it from two counter readings.
//   rates: { [nodeId]: { rx, tx } }   rx = traffic that reaches the node (dots move down its link), tx = traffic it sends (dots move up)
export const MAX_DOTS = 12;

const num = (v) => (typeof v === 'number' && v > 0 && isFinite(v) ? v : 0);
const lg = (rate) => Math.log2(1 + rate / 1024);          // 1 KiB/s = 1, 1 MiB/s = 10, 1 GiB/s = 20

// How many dots a link carries: none at zero, then growing slowly with the rate (log scale), at most MAX_DOTS.
export const dotCount = (rate) => (num(rate) ? Math.min(MAX_DOTS, 1 + Math.floor(lg(rate) / 1.5)) : 0);
// Their speed in drawing units per second: slow at a trickle, 160 at most.
export const dotSpeed = (rate) => (num(rate) ? Math.min(160, 24 + 12 * lg(rate)) : 0);
// The static stand-in for `prefers-reduced-motion`: the width of the link line.
export const thickness = (rate) => (num(rate) ? Math.min(6, 1.5 + 0.35 * lg(rate)) : 1);

// One flow per link with a rate: [{ id, x1, y1, x2, y2, len, rx, tx, nRx, nTx, vRx, vTx, width }]. Links with no traffic either way are left out.
export function flowsFor(links, rates) {
  const out = [];
  for (const l of links || []) {
    const r = (rates && rates[l.to]) || {};
    const rx = num(r.rx), tx = num(r.tx);
    if (!rx && !tx) continue;
    const len = Math.hypot(l.x2 - l.x1, l.y2 - l.y1);
    out.push({ id: l.to, x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2, len, rx, tx, nRx: dotCount(rx), nTx: dotCount(tx), vRx: dotSpeed(rx), vTx: dotSpeed(tx), width: thickness(Math.max(rx, tx)) });
  }
  return out;
}

// Fractions (0..1) along the link, parent to child, of `n` dots moving at `v` units per second after `t` seconds. `up` runs the other way.
export function dotFractions(len, n, v, t, up) {
  if (!n || !len) return [];
  const gap = len / n;
  const shift = (t * v) % gap;
  const f = [];
  for (let i = 0; i < n; i++) { const p = (i * gap + shift) / len; f.push(up ? 1 - p : p); }
  return f;
}
