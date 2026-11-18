<script>
  import { Chip, Checkbox, ChoiceList, Muted } from '../../ui/index.js';
  import { tip } from '../../ui/tooltip.svelte.js';
  // A list of free disks to pick from: checkboxes, or one-of-many rows with `single`. `picked` is a list of by-id names.
  import { shortId } from './disks.js';

  let { disks, loaded = true, picked = $bindable([]), single = false, empty = 'No free disks.' } = $props();

  const warnNote = (n) => /encrypt|old ZFS/.test(n);
  const toggle = (id) => { picked = picked.includes(id) ? picked.filter((x) => x !== id) : [...picked, id]; };
  const options = $derived(disks.map((d) => ({ id: d.id, label: shortId(d.id), text: [`${d.space ?? d.size} · ${d.type}`, ...d.notes].join(' · ') })));
</script>

<div role="group" aria-label="Free disks">
  {#if !disks.length}
    <Muted as="p">{loaded ? empty : 'Loading…'}</Muted>
  {:else if single}
    <ChoiceList {options} value={picked[0] ?? ''} onpick={(id) => (picked = [id])} label="Free disks" />
  {:else}
    <div class="list">
      {#each disks as d (d.id)}
        <div class="row" class:on={picked.includes(d.id)}>
          <Checkbox checked={picked.includes(d.id)} onchange={() => toggle(d.id)}>
            <span class="main"><code use:tip={d.id}>{shortId(d.id)}</code><Muted>{d.space ?? d.size} · {d.type}</Muted></span>
          </Checkbox>
          {#each d.notes as n}<Chip tone={warnNote(n) ? 'soft' : ''} style="white-space:nowrap">{n}</Chip>{/each}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .list { display: flex; flex-direction: column; border: 1px solid var(--line); max-height: 240px; overflow-y: auto; }
  .row { display: flex; align-items: center; gap: 10px; padding: 8px 10px; flex-wrap: wrap; justify-content: space-between; }
  .row + .row { border-top: 1px solid var(--line); }
  .row.on { background: color-mix(in oklch, var(--accent) 12%, transparent); }
  .main { display: inline-flex; flex-direction: column; gap: 1px; }
  code { font-size: 12px; }
</style>
