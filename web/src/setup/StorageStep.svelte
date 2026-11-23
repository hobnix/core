<script>
  import { P } from '../paths.js';
  // The storage step: import a ZFS pool that is on the disks, or make a pool from empty disks. Both open a plan (the same `pool` change the
  // Pools page uses); the disks it only shows are listed with the way out. Next moves on, whatever was done here.
  import { onMount } from 'svelte';
  import Table from '../shell/Table.svelte';
  import Button from '../ui/Button.svelte';
  import Checkbox from '../ui/Checkbox.svelte';
  import Field from '../ui/Field.svelte';
  import TextInput from '../ui/TextInput.svelte';
  import Banner from '../ui/Banner.svelte';
  import { get } from '../api.js';
  import { openPlan, ui } from '../ui.svelte.js';
  import { go } from '../route.svelte.js';
  import { pools, loadPools } from '../pools.svelte.js';
  import { sizeTxt } from '../pages/storage/pool.js';
  import { groups, poolNameOk, suggestName, nothingText, evenPair } from './storage.js';
  let { save = $bindable(null) } = $props();
  // read once when the step opens: the disks only change when somebody changes them here
  let disc = $state({ rows: [], loaded: false });
  const load = () => get('/api/sys/storage/discover').then((d) => { disc = { rows: d.rows ?? [], loaded: true }; }).catch(() => { disc = { rows: [], loaded: false }; });
  onMount(() => { loadPools(true); load(); });
  // a plan that was open has closed: what it did (an import, a new pool) shows at once
  let wasOpen = false;
  $effect(() => { const open = !!ui.dialog; if (wasOpen && !open) { loadPools(true); load(); } wasOpen = open; });
  const g = $derived(groups(disc.rows));
  const names = $derived(pools.rows.map((p) => p.name));
  let picked = $state({});
  let typed = $state('');
  let touched = $state(false);
  const name = $derived(touched ? typed : suggestName(names));
  const ids = $derived(g.empty.map((d) => d.id).filter((id) => picked[id]));
  const nameBad = $derived(!poolNameOk(name) ? 'Use 1 to 12 lowercase letters and digits, starting with a letter, and not a reserved word.' : names.includes(name) ? 'A pool with this name exists.' : '');
  const why = $derived(!evenPair(ids.length) ? 'Tick an even number of disks, at least two.' : nameBad);
  const nothing = $derived(disc.loaded ? nothingText(g, pools.rows) : '');
  const label = (r) => [r.kind, r.label, r.state].filter(Boolean).join(' ');
  const pickCols = [{ key: 'pool', label: 'Pool' }, { key: 'disks', label: 'Disks', value: (r) => r.disks.length }, { key: 'go', label: '', sort: false }];
  const emptyCols = [{ key: 'pick', label: '', sort: false }, { key: 'id', label: 'Disk' }, { key: 'size', label: 'Size', sort: 'num' }, { key: 'bus', label: 'Bus', optional: true }, { key: 'model', label: 'Model', optional: true }];
  const shownCols = [{ key: 'id', label: 'Disk' }, { key: 'what', label: 'Holds', value: label }];
  save = () => true;
</script>

{#if nothing}<Banner tone="info">{nothing}</Banner>{/if}

{#if g.importable.length}
  <div class="muted">Pools to import</div>
  <Table id="first-run-import" columns={pickCols} rows={g.importable} key="pool">
    {#snippet cell(row, col)}
      {#if col.key === 'go'}
        <Button size="sm" tooltip="Bring this pool in under its own name; nothing on the disks is erased" onclick={() => openPlan('pool', [row.pool, 'import', '--use', 'data'], 'Import the pool ' + row.pool)}>Import</Button>
      {:else}{col.value ? col.value(row) : row[col.key]}{/if}
    {/snippet}
  </Table>
{/if}

{#if g.empty.length}
  <div class="muted">Empty disks</div>
  <Table id="first-run-empty" columns={emptyCols} rows={g.empty} key="id">
    {#snippet cell(row, col)}
      {#if col.key === 'pick'}<Checkbox checked={!!picked[row.id]} label="" onchange={(e) => { picked[row.id] = e.target.checked; }} />
      {:else if col.key === 'size'}{sizeTxt(row.size)}
      {:else}{row[col.key] || '-'}{/if}
    {/snippet}
  </Table>
  <Field label="Name of the new pool" error={touched ? nameBad : ''}>
    <TextInput value={name} oninput={(e) => { typed = e.target.value; touched = true; }} autocomplete="off" spellcheck={false} />
  </Field>
  <div>
    <Button variant="primary" disabled={!!why} tooltip={why || 'Show the plan for a new mirror pool on the ticked disks'}
            onclick={() => openPlan('pool', [name, 'add', '--use', 'data', '--disks', ids.join(',')], 'Create the pool ' + name)}>Create the pool</Button>
  </div>
  {#if g.empty.length === 1}<p class="muted">A pool needs two disks; add one more.</p>{/if}
{/if}

{#if g.shown.length}
  <div class="muted">Shown only</div>
  <Table id="first-run-shown" columns={shownCols} rows={g.shown} key="id" />
  <p class="muted">These disks hold data and are not offered for a new pool. To use one, erase it on its disk page first.
    <Button variant="ghost" size="sm" tooltip="Open the disks page" onclick={() => go(P.disks)}>Disks</Button></p>
{/if}
