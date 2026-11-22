// Paints the traffic dots of the network map on a canvas (#875). One path per direction, one fill each, so a frame with 100 nodes is two draw calls.
// `ctx` is a 2d context already scaled to the drawing units of layout.js; `colors` = { rx, tx } as CSS colours read from the tokens.
import { dotFractions } from './dots.js';

export function paintDots(ctx, flows, t, colors, radius = 2.5) {
  for (const dir of ['rx', 'tx']) {
    ctx.beginPath();
    const up = dir === 'tx';
    for (const f of flows) {
      const n = up ? f.nTx : f.nRx;
      if (!n) continue;
      for (const p of dotFractions(f.len, n, up ? f.vTx : f.vRx, t, up)) {
        const x = f.x1 + (f.x2 - f.x1) * p, y = f.y1 + (f.y2 - f.y1) * p;
        ctx.moveTo(x + radius, y);
        ctx.arc(x, y, radius, 0, 6.283185307179586);
      }
    }
    ctx.fillStyle = colors[dir];
    ctx.fill();
  }
}
