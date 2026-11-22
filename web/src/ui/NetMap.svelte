<script>
  // The network map (#875, docs/PLAN-network-map.md part 4): nodes and links in SVG, the traffic as moving dots on a canvas laid over it.
  // The positions come from netmap/layout.js; the dots from netmap/dots.js. Props:
  //   graph  rows of `hs sys netmap` as objects ({ id, kind, parent, label, state, ... }), or { nodes }
  //   rates  { [nodeId]: { rx, tx } } bytes per second (rx reaches the node, dots move down; tx leaves it, dots move up). No entry or 0 = no dots.
  //   label  the accessible name of the map
  // `prefers-reduced-motion`: no animation; a link with traffic is drawn thicker instead. The animation also stops while the tab is hidden and when
  // no link has traffic. Colours and look: the `.nm-*` rules in base.css, tokens only. The access part (focus, popover) is #876.
  import { layoutGraph } from '../netmap/layout.js';
  import { flowsFor } from '../netmap/dots.js';
  import { paintDots } from '../netmap/paint.js';

  let { graph = [], rates = {}, label = 'Network map' } = $props();

  const lay = $derived(layoutGraph(graph));
  const flows = $derived(flowsFor(lay.links, rates));
  const byTo = $derived(new Map(flows.map((f) => [f.id, f])));

  let reduced = $state(false);
  let canvas = $state();
  let rxEl = $state();
  let txEl = $state();

  $effect(() => {
    const q = window.matchMedia('(prefers-reduced-motion: reduce)');
    reduced = q.matches;
    const on = () => (reduced = q.matches);
    q.addEventListener('change', on);
    return () => q.removeEventListener('change', on);
  });

  const SHORT = 22;
  const short = (s) => (s.length > SHORT ? s.slice(0, SHORT - 1) + '…' : s);
  const GOOD = ['running', 'up', 'ok', 'online', 'active'], BAD = ['error', 'failed', 'bad', 'down-error'], WARN = ['frozen', 'degraded', 'warn', 'starting', 'stopping'];
  const tone = (s) => (GOOD.includes(s) ? 'ok' : BAD.includes(s) ? 'bad' : WARN.includes(s) ? 'warn' : 'off');

  // The canvas loop: starts when there are dots to move and motion is allowed, ends otherwise.
  $effect(() => {
    if (!canvas || reduced || !flows.length || !lay.width) return;
    const ctx = canvas.getContext('2d');
    let raf = 0, last = 0, t0 = 0, colors = { rx: '', tx: '' };
    const readColors = () => { colors = { rx: getComputedStyle(rxEl).color, tx: getComputedStyle(txEl).color }; };
    const size = () => {
      const dpr = window.devicePixelRatio || 1;
      const w = Math.max(1, Math.round(canvas.clientWidth * dpr)), h = Math.max(1, Math.round(canvas.clientHeight * dpr));
      if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
      return canvas.width / lay.width;
    };
    const frame = (now) => {
      raf = requestAnimationFrame(frame);
      if (now - last < 30) return;                       // about 30 frames a second is enough for dots
      last = now;
      if (!t0) { t0 = now; readColors(); }
      const k = size();
      ctx.setTransform(k, 0, 0, k, 0, 0);
      ctx.clearRect(0, 0, lay.width, lay.height);
      paintDots(ctx, flows, (now - t0) / 1000, colors);
    };
    const visible = () => { cancelAnimationFrame(raf); raf = 0; if (!document.hidden) { readColors(); raf = requestAnimationFrame(frame); } };
    document.addEventListener('visibilitychange', visible);
    raf = requestAnimationFrame(frame);
    return () => { cancelAnimationFrame(raf); document.removeEventListener('visibilitychange', visible); ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, canvas.width, canvas.height); };
  });
</script>

{#if lay.empty}
  <p class="nm-empty">Nothing to draw yet.</p>
{:else}
  <div class="nm" style="aspect-ratio:{lay.width} / {lay.height}; max-width:{lay.width}px">
    <svg class="nm-svg" viewBox="0 0 {lay.width} {lay.height}" role="img" aria-label={label}>
      {#each lay.links as l (l.to)}
        <line class="nm-link" class:busy={reduced && byTo.has(l.to)} x1={l.x1} y1={l.y1} x2={l.x2} y2={l.y2} style={reduced && byTo.has(l.to) ? `stroke-width:${byTo.get(l.to).width}px` : undefined} />
      {/each}
      {#each lay.nodes as n (n.id)}
        <g class="nm-node k-{n.known ? n.kind : 'other'}" transform="translate({n.x} {n.y})">
          <title>{n.label} ({n.kind || 'node'}{n.state ? ', ' + n.state : ''})</title>
          <rect class="nm-box" width={n.w} height={n.h} />
          <circle class="nm-dot {tone(n.state)}" cx="14" cy="16" r="4" />
          <text class="nm-kind" x="24" y="20">{n.kind || 'node'}{n.state ? ' · ' + n.state : ''}</text>
          <text class="nm-name" x="12" y={n.h - 14}>{short(n.label)}</text>
        </g>
      {/each}
    </svg>
    <canvas class="nm-dots" bind:this={canvas} aria-hidden="true"></canvas>
    <span class="nm-c nm-c-rx" bind:this={rxEl} aria-hidden="true"></span>
    <span class="nm-c nm-c-tx" bind:this={txEl} aria-hidden="true"></span>
  </div>
{/if}
