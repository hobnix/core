<script>
  // The network map (#875, docs/PLAN-network-map.md part 4): nodes and links in SVG, the traffic as moving dots on a canvas laid over it.
  // The positions come from netmap/layout.js; the dots from netmap/dots.js. Props:
  //   graph  rows of `hs sys netmap` as objects ({ id, kind, parent, label, state, ... }), or { nodes }
  //   rates  { [nodeId]: { rx, tx } } bytes per second (rx reaches the node, dots move down; tx leaves it, dots move up). No entry or 0 = no dots.
  //   label  the accessible name of the map
  //   hrefFor  (row) => the address of the page of that node, or '' / null for none (the detail and the table then show no link); the map page (#877) supplies it
  //   table  true starts in the table view
  // `prefers-reduced-motion`: no animation; a link with traffic is drawn thicker instead. The animation also stops while the tab is hidden and when
  // no link has traffic. Colours and look: the `.nm-*` rules in base.css, tokens only.
  // Without a mouse (#876, part 5): one node is in the tab order (roving tabindex); the arrow keys move to the parent, the first child and the
  // neighbours of the tier, Home and End to the first and last node (netmap/access.js); Enter or Space opens the detail popover (UI SDK
  // Popover, ADR 0030), Escape closes it and focus returns to the node. Each node is named for a screen reader with its kind, state and rates.
  // The table view has the same facts and is the text alternative of the map.
  import { layoutGraph } from '../netmap/layout.js';
  import { flowsFor } from '../netmap/dots.js';
  import { paintDots } from '../netmap/paint.js';
  import { moveFocus, factsOf, readingOrder } from '../netmap/access.js';
  import { Popover, PopoverContent, PopoverTitle, PopoverClose } from '@ui-sdk/svelte/popover';
  import Button from './Button.svelte';
  import Kv from './Kv.svelte';

  let { graph = [], rates = {}, label = 'Network map', hrefFor = null, table = false } = $props();

  const lay = $derived(layoutGraph(graph));
  const flows = $derived(flowsFor(lay.links, rates));
  const byTo = $derived(new Map(flows.map((f) => [f.id, f])));
  const ordered = $derived(readingOrder(lay));
  const facts = $derived(new Map(lay.nodes.map((n) => [n.id, factsOf(lay, n, rates)])));
  const hrefOf = (n) => (hrefFor && hrefFor(n.data)) || '';

  let showTable = $state(table);
  let cur = $state('');                                   // the node that is in the tab order
  const focusId = $derived(lay.nodes.some((n) => n.id === cur) ? cur : ordered[0] ? ordered[0].id : '');
  let els = {};                                           // node id -> its <g>
  let open = $state(false);
  let openId = $state('');
  const shown = $derived(lay.nodes.find((n) => n.id === openId));
  const shownFacts = $derived(shown ? facts.get(shown.id) : null);
  const MOVES = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End'];

  // The popover has no trigger button (the node is the trigger), so the SDK does not know where focus was: move it into the detail ourselves.
  function show(n) { cur = n.id; openId = n.id; open = true; setTimeout(() => document.querySelector('.np-content')?.focus(), 60); }
  function key(e, n) {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); show(n); return; }
    if (e.altKey || e.ctrlKey || e.metaKey || !MOVES.includes(e.key)) return;
    e.preventDefault();
    const to = moveFocus(lay, n.id, e.key);
    cur = to;
    if (els[to]) els[to].focus();
  }

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
  <div class="nm-bar">
    <Button size="sm" icon={showTable ? 'share-network' : 'list-bullets'} onclick={() => (showTable = !showTable)}>{showTable ? 'Show the map' : 'Show as a table'}</Button>
    {#if !showTable}<span class="nm-hint">Arrow keys move between nodes, Enter shows the details.</span>{/if}
  </div>
  {#if showTable}
    <div class="tablescroll">
      <table class="table nm-table">
        <caption class="nm-cap">{label}: the same facts as the map</caption>
        <thead><tr><th>Name</th><th>Kind</th><th>State</th><th>Receiving</th><th>Sending</th><th>Under</th><th>Services</th><th>Page</th></tr></thead>
        <tbody>
          {#each ordered as n (n.id)}
            {@const f = facts.get(n.id)}
            <tr>
              <th scope="row">{f.name}</th><td>{f.kind}</td><td>{f.state}</td><td>{f.rx}</td><td>{f.tx}</td><td>{f.parent || '–'}</td><td>{f.services.join(', ') || '–'}</td>
              <td>{#if hrefOf(n)}<a href={hrefOf(n)}>Open</a>{:else}–{/if}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {:else}
    <div class="nm" style="aspect-ratio:{lay.width} / {lay.height}; max-width:{lay.width}px">
      <svg class="nm-svg" viewBox="0 0 {lay.width} {lay.height}" role="group" aria-label={label}>
        {#each lay.links as l (l.to)}
          <line class="nm-link" class:busy={reduced && byTo.has(l.to)} x1={l.x1} y1={l.y1} x2={l.x2} y2={l.y2} style={reduced && byTo.has(l.to) ? `stroke-width:${byTo.get(l.to).width}px` : undefined} />
        {/each}
        {#each lay.nodes as n (n.id)}
          <g class="nm-node k-{n.known ? n.kind : 'other'}" transform="translate({n.x} {n.y})" role="button" tabindex={n.id === focusId ? 0 : -1} aria-label={facts.get(n.id).text}
             aria-haspopup="dialog" bind:this={els[n.id]} onkeydown={(e) => key(e, n)} onclick={() => show(n)} onfocus={() => (cur = n.id)}>
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
    {#if shown && shownFacts}
      <Popover bind:open>
        <PopoverContent class="np-content" side="bottom" align="start" sideOffset={6} anchor={{ getBoundingClientRect: () => (els[openId] ? els[openId].getBoundingClientRect() : { x: 0, y: 0, width: 0, height: 0 }) }} initialFocus="content" finalFocus={() => els[openId]}>
          <PopoverTitle class="np-title">{shown.label}</PopoverTitle>
          <div class="np-body">
            <Kv items={[
              { k: 'Kind', v: shownFacts.kind }, { k: 'State', v: shownFacts.state },
              { k: 'Receiving', v: shownFacts.rx }, { k: 'Sending', v: shownFacts.tx },
              { k: 'Under', v: shownFacts.parent }, { k: 'Services', v: shownFacts.services.join(', ') },
            ]} />
            {#if hrefOf(shown)}<a class="np-link" href={hrefOf(shown)}>Open its page</a>{/if}
          </div>
          <PopoverClose class="np-close" aria-label="Close">×</PopoverClose>
        </PopoverContent>
      </Popover>
    {/if}
  {/if}
{/if}
