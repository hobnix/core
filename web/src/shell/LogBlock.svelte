<script>
  // The `log` block of a package page (#473): the tail of a declared log. It follows the log stream of the server (logfeed.svelte.js: one EventSource, no
  // timer while it is up), keeps at most `lines` lines (default 200, never more than 2000) and shows the newest one. A `follow = false` block reads once.
  //   block: { stream: '/api/logs/stream/<kind>?target=..', read: '/api/sys/..' (the timed fallback while the stream is down), lines?, follow?, every?, empty?, title? }
  // A log may hold secrets: nothing is kept beyond the view. Both addresses must be paths of this server's API.
  import { logfeed } from '../logfeed.svelte.js';
  import { tr } from '../i18n.js';
  import PageState from './PageState.svelte';
  import { tailLines, apiPath, logClass } from './generic.js';

  let { block } = $props();

  const stream = apiPath(block.stream);
  const read = apiPath(block.read);
  const feed = logfeed({ stream: () => stream, read: () => read, follow: () => block.follow !== false, every: (block.every ?? 5) * 1000, max: Math.min(2000, Math.max(1, Number(block.lines) || 200)) });
  const list = $derived(tailLines(feed.lines, block.lines));
  let box = $state(null);

  // keep the newest line in view while following
  $effect(() => { if (block.follow !== false && box && list.length) box.scrollTop = box.scrollHeight; });
</script>

<div class="card gb">
  {#if block.title}<div class="gh"><b>{block.title}</b></div>{/if}
  <PageState loading={!feed.loaded} error={feed.error?.message ?? ''} hasData={feed.loaded} empty={feed.loaded && !list.length} emptyIcon="scroll" emptyTitle={tr('Nothing logged yet')} emptyText={block.empty ?? ''}>
    <div class="log" bind:this={box} role="log" aria-label={block.title || tr('Log')}>
      {#each list as l}<div class={logClass(l)}>{l}</div>{/each}
    </div>
  </PageState>
</div>

<style>
  .gb { padding: 14px 16px; gap: 10px; }
  .gh { display: flex; align-items: center; gap: 8px; font-size: 14px; }
  .log { max-height: 420px; overflow: auto; padding: 8px 10px; background: var(--bg); font-family: var(--mono); font-size: 11.5px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; }
  .warn { color: var(--warn); }
  .bad { color: var(--bad); }
</style>
