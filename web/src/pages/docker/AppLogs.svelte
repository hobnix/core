<script>
  // The Logs tab of a Docker app drawer: the Compose log of the app, followed while the tab is open (a log stream, D15; the timed read only while the stream is down).
  import { logfeed } from '../../logfeed.svelte.js';
  import { Select, Checkbox, Muted } from '../../ui/index.js';

  let { app } = $props();
  let lines = $state('200');
  let follow = $state(true);
  let box = $state(null);

  const logs = logfeed({ stream: () => `/api/logs/stream/docker?target=${encodeURIComponent(app)}&lines=${lines}`, read: () => `/api/sys/docker/logs/${encodeURIComponent(app)}?lines=${lines}`, follow: () => follow, every: 5000 });
  const list = $derived(logs.lines);
  const cls = (l) => (/\b(error|err|fail|failed|crit|alert|emerg)\b/i.test(l) ? 'bad' : /\bwarn(ing)?\b/i.test(l) ? 'warn' : '');
  $effect(() => { if (follow && box && list.length) box.scrollTop = box.scrollHeight; });
</script>

<div class="lt">
  <div class="bar">
    <Select bind:value={lines} ariaLabel="Lines" options={['100', '200', '500', '1000']} />
    <Checkbox bind:checked={follow} label="Follow" />
  </div>
  <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
  <div class="log" bind:this={box} tabindex="0" role="log" aria-label="Compose log of {app}">
    {#if logs.error}
      <div class="bad">The log could not be read (is the app running?).</div>
    {:else if !logs.loaded}
      <Muted as="div">Loading…</Muted>
    {:else if !list.length}
      <Muted as="div">The app wrote nothing.</Muted>
    {:else}
      {#each list as l}<div class={cls(l)}>{l}</div>{/each}
    {/if}
  </div>
</div>

<style>
  .lt { display: flex; flex-direction: column; gap: 8px; padding: 12px 16px; }
  .bar { display: flex; align-items: center; gap: 14px; font-size: 12px; color: var(--fg-3); }
  .log { max-height: 46vh; min-height: 160px; overflow: auto; padding: 8px 10px; background: var(--bg); border: 1px solid var(--line); font: 11.5px/1.5 var(--mono); white-space: pre-wrap; word-break: break-word; }
  .warn { color: var(--warn); }
  .bad { color: var(--bad); }
</style>
