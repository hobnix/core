<script>
  import { Button, Dialog, Select, Checkbox, Row, Muted } from '../../ui/index.js';
  // The last lines of an instance's journal (`hs sys ct logs <ct> [lines]`, read only), in a window over the page.
  import { poll } from '../../data.svelte.js';
  import { ui } from '../../ui.svelte.js';

  let { ct } = $props();

  let lines = $state('200');
  let follow = $state(true);
  let box = $state(null);

  const logs = poll(() => (follow || !logs?.loaded ? `/api/sys/ct/logs/${encodeURIComponent(ct)}?lines=${lines}` : ''), 4000);
  const text = $derived((logs.data?.text ?? '').trimEnd());
  const list = $derived(text ? text.split('\n') : []);

  const cls = (l) => (/\b(error|err|fail|failed|crit|alert|emerg)\b/i.test(l) ? 'bad' : /\bwarn(ing)?\b/i.test(l) ? 'warn' : '');
  const close = () => { ui.create = null; };

  // keep the newest line in view while following
  $effect(() => { if (follow && box && list.length) box.scrollTop = box.scrollHeight; });
</script>

<Dialog title={`Logs · ${ct}`} labelledby="ilt" width="960px" onclose={close}>
  <div class="il">
    <Row>
      <div id="ilt" class="dialog-title" style="flex:1">Logs · {ct}</div>
      <Select bind:value={lines} ariaLabel="Lines" options={['100', '200', '500', '1000']} />
      <Checkbox bind:checked={follow} label="Follow" />
      <Button onclick={close}>Close</Button>
    </Row>
    <div class="log" bind:this={box}>
      {#if logs.error && !logs.data}
        <div class="bad">The log could not be read (is the instance running, is the storage unlocked?).</div>
      {:else if !logs.loaded}
        <Muted as="div">Loading…</Muted>
      {:else if !list.length}
        <Muted as="div">The instance wrote nothing.</Muted>
      {:else}
        {#each list as l}<div class={cls(l)}>{l}</div>{/each}
      {/if}
    </div>
  </div>
</Dialog>

<style>
  .il { display: flex; flex-direction: column; gap: 12px; padding: 18px; height: min(640px, calc(100dvh - 40px)); }
  .log { flex: 1; min-height: 0; overflow: auto; padding: 8px 10px; border-radius: var(--r); background: var(--bg); font-family: var(--mono); font-size: 11.5px; line-height: 1.5; white-space: pre-wrap; word-break: break-word; }
  .warn { color: var(--warn); }
  .bad { color: var(--bad); }
</style>
