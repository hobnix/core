<script>
  import { P, diskPath, withQuery } from '../paths.js';
  // Storage > Disks: every disk of this server in one list (/storage/disks, filter ?pool=<pool name>|none|missing). No quick look here (owner decision 2026-11-22: the table
  // already shows what it would show): the name and the "Open disk" button at the end of a row go to the page of the disk (pages/disks/Disk.svelte), where the
  // SMART history, the self-tests and the actions of a single disk are. A missing disk has a "Forget" button. Changing pool membership (replace, remove, close, convert) stays on Pools; a free disk is added from here.
  import UsageBar from '../shell/UsageBar.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { StatusDot, Chip, Banner, Card, Muted, Segmented } from '../ui/index.js';
  import { onMount } from 'svelte';
  import { pools, loadPools } from '../pools.svelte.js';
  import { route, go, url } from '../route.svelte.js';
  import { sleepText, sleepDot, powerText } from '../disk-sleep.js';
  import { openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import Button from '../ui/Button.svelte';
  import AddDisks from '../forms/storage/AddDisks.svelte';
  import ForgetDisk from '../forms/storage/ForgetDisk.svelte';
  import OtherDisk from '../forms/storage/OtherDisk.svelte';
  import { diskPool, hoursTxt, dateOf } from './storage/pool.js';
  import { diskModel } from './disks/model.svelte.js';

  let { deck } = $props();

  onMount(() => { loadPools(); });
  // a pool job that ends may have added or removed a pool: read the pool list again then (from the job, not from a timer)
  const anyPoolJob = $derived(rowstate.active('pool', []).length > 0 || rowstate.active('migrate', []).length > 0);
  let wasBusy = false;
  $effect(() => { const b = anyPoolJob; if (wasBusy && !b) loadPools(true); wasBusy = b; });
  const TABS = $derived([{ id: 'all', label: 'All' }, ...pools.rows.map((p) => ({ id: p.name, label: p.name })), { id: 'none', label: 'Free' }, { id: 'missing', label: 'Missing' }]);
  const filter = $derived(TABS.some((t) => t.id === route.query.pool) ? route.query.pool : 'all');
  const setFilter = (id) => go(withQuery(P.disks, id === 'all' ? {} : { pool: id }));  

  const locked = $derived(!!deck?.data?.locked);
  const m = diskModel({ filter: () => filter });
  const lockTip = (t) => (locked ? 'The storage is locked' : t);
  const fsText = (d) => (d.fs && d.fs !== '-' ? d.fs : '–');
  const addToPool = (pool) => openCreate(AddDisks, { pool, variant: 'empty', snap: pool === m.snapName ? m.snapPool : false });
  const poolForNew = $derived(pools.rows.some((p) => p.name === filter) ? filter : m.snapName || (pools.rows[0]?.name ?? ''));
  const link = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(diskPath(name)); } };

  const columns = [
    { key: 'name', label: 'Disk' }, { key: 'pool', label: 'Pool', value: (d) => m.poolText(d) }, { key: 'role', label: 'Role', value: (d) => m.roleText(d), optional: true },
    { key: 'model', label: 'Model', value: (d) => m.modelOf(d), optional: true }, { key: 'size', label: 'Size', sort: 'num', value: (d) => d.size }, { key: 'fs', label: 'Format', value: (d) => fsText(d), optional: true },
    { key: 'smart', label: 'SMART', value: (d) => m.verdictOf(d) }, { key: 'temp', label: 'Temp', sort: 'num', value: (d) => Number(d.temp), optional: true },
    { key: 'hours', label: 'Power-on', sort: 'num', value: (d) => Number(d.hours), optional: true },
    { key: 'sleep', label: 'Sleep', value: (d) => sleepText(d.sleep), optional: true },
    { key: 'act', label: '', sort: false, align: 'right', width: '1%' },
  ];
  const missCols = [{ key: 'model', label: 'Disk' }, { key: 'dev', label: 'Was' }, { key: 'serial', label: 'Serial' }, { key: 'seen', label: 'Last seen', sort: 'num', value: (x) => x.lastSeen }, { key: 'act', label: '', sort: false, align: 'right', width: '1%' }];
</script>

<PageHeader title="Disks" sub="Every disk of this server: where it belongs, how healthy it is, what it has been through.">
  {#snippet actions()}
    <Button need="admin" disabled={locked} tooltip={lockTip('Look at a USB or hot-plug disk: mount it read-only, copy from it, eject it')} onclick={() => openCreate(OtherDisk, {})}><i class="ph ph-usb"></i>Other disk</Button>
    <Button need="admin" variant="primary" disabled={locked || !m.counts.none} tooltip={lockTip(m.counts.none ? 'Pick free disks and see the plan' : 'There is no free disk')} onclick={() => addToPool(poolForNew)}><i class="ph ph-plus"></i>Add disks to a pool</Button>
  {/snippet}
</PageHeader>
{#if m.pw.power.length}<Muted as="p">{#each m.pw.power as x, i}{i ? ' · ' : ''}{powerText(x)}{/each}</Muted>{/if}

<div style="margin-bottom:14px;max-width:100%"><Segmented label="Filter" value={filter} options={TABS.map((t) => ({ value: t.id, label: t.label, count: m.counts[t.id] ?? '' }))} onchange={setFilter} /></div>

<PageState loading={!m.mon.loaded} hasData={m.mon.data != null} error={m.mon.error?.message ?? ''} empty={m.mon.loaded && !m.all.length && !m.missing.length} emptyIcon="hard-drive" emptyTitle="No disks found"
           emptyText="The disks could not be listed. Is the storage locked or the collector not running?">
  {#if filter === 'missing'}
    <div>
      <Card>
        {#if m.missing.length}
          <Table id="disks-missing" columns={missCols} rows={m.missing} key="serial" compact empty="No disk is missing.">
            {#snippet cell(x, col)}
              {#if col.key === 'model'}<StatusDot state="warn" label={x.model || x.serial} />
              {:else if col.key === 'dev'}<code>{x.dev}</code>
              {:else if col.key === 'serial'}<code>{x.serial}</code>
              {:else if col.key === 'act'}<Button need="admin" variant="ghost" size="sm" class="btn-icon" icon="trash-simple" label="Forget {x.model || x.serial}" disabled={locked} tooltip={lockTip('Take this disk off the list for good')} onclick={() => openCreate(ForgetDisk, { serial: x.serial, model: x.model, dev: x.dev })} />
              {:else if col.key === 'seen'}<Muted>{x.lastSeen ? dateOf(x.lastSeen) : '–'}</Muted>{/if}
            {/snippet}
          </Table>
        {:else}
          <Muted as="p">Nothing is missing: every disk the server has seen is still connected.</Muted>
        {/if}
      </Card>
    </div>
  {:else}
    {#if deck?.data?.locked}<Banner tone="warn">Storage is locked: pool disks may be missing from this list until it is unlocked.</Banner>{/if}
    {#if m.missing.length && filter === 'all'}
      <Banner tone="warn">{m.missing.length} disk{m.missing.length === 1 ? ' is' : 's are'} missing since the last collector run.
        {#snippet action()}<Button size="sm" tooltip={'Show the disks that are missing'} onclick={() => setFilter('missing')}>Show</Button>{/snippet}
      </Banner>
    {/if}
    <div>
      <Card>
        <div style="overflow-x:auto"><Table id="disks" {columns} rows={m.visible} key="name" compact
               empty={filter === 'none' ? 'Every disk belongs to a pool, the system or the backup.' : 'No disks here.'}>
          {#snippet cell(d, col)}
            {#if col.key === 'name'}<a href={url(diskPath(d.name))} onclick={(e) => link(e, d.name)}><code>{d.name}</code></a>{#if m.doingOf(d)} <Chip>{m.doingOf(d).toLowerCase()}…</Chip>{/if}
            {:else if col.key === 'pool'}<Chip>{m.poolText(d)}</Chip>
            {:else if col.key === 'role'}<Muted>{diskPool(d.role) ? m.roleText(d) : ''}</Muted>
            {:else if col.key === 'model'}<Muted>{m.modelOf(d)}</Muted>
            {:else if col.key === 'size'}<span style="white-space:nowrap"><UsageBar free={d.free} size={d.size} width={96} /></span>
            {:else if col.key === 'fs'}<Muted style="white-space:nowrap">{fsText(d)}</Muted>
            {:else if col.key === 'smart'}<StatusDot state={m.stateOf(d)} label={m.wordOf(d)} />
            {:else if col.key === 'temp'}<span style="white-space:nowrap">{d.temp && d.temp !== '-' ? `${d.temp} °C` : '–'}</span>
            {:else if col.key === 'sleep'}{#if d.sleep}<StatusDot state={sleepDot(d.sleep)} label={sleepText(d.sleep)} />{:else}<Muted>–</Muted>{/if}
            {:else if col.key === 'act'}<Button variant="ghost" size="sm" class="btn-icon" icon="arrow-square-out" label="Open disk" tooltip={'Open disk'} onclick={() => go(diskPath(d.name))} />
            {:else}<Muted style="white-space:nowrap">{hoursTxt(d.hours)}</Muted>{/if}
          {/snippet}
        </Table></div>
      </Card>
    </div>
  {/if}
</PageState>
