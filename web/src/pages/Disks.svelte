<script>
  import { P, diskPath, withQuery } from '../paths.js';
  // Storage > Disks: every disk of this server in one list (/storage/disks, filter ?pool=<pool name>|none|missing). A row opens the quick look over the list
  // (?sel=<name>, so a reload, a pasted link and Back/Forward work: selection.svelte.js); "Open page" goes to the page of the disk (pages/disks/Disk.svelte), where the
  // SMART history, the self-tests and the actions of a single disk are. Changing pool membership (replace, remove, close, convert) stays on Pools; a free disk is added from here.
  import UsageBar from '../shell/UsageBar.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { StatusDot, Chip, Kv, Banner, Card, Muted, Segmented } from '../ui/index.js';
  import QuickLook from '../ui/QuickLook.svelte';
  import { onMount } from 'svelte';
  import { pools, loadPools } from '../pools.svelte.js';
  import { selected, select, close } from '../selection.svelte.js';
  import { route, go, url } from '../route.svelte.js';
  import { sleepText, sleepDot, powerText } from '../disk-sleep.js';
  import { openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import Button from '../ui/Button.svelte';
  import AddDisks from '../forms/storage/AddDisks.svelte';
  import ForgetDisk from '../forms/storage/ForgetDisk.svelte';
  import OtherDisk from '../forms/storage/OtherDisk.svelte';
  import { diskPool, sizeTxt, hoursTxt, dateOf } from './storage/pool.js';
  import { diskModel } from './disks/model.svelte.js';

  let { deck } = $props();

  onMount(() => { loadPools(); });
  // a pool job that ends may have added or removed a pool: read the pool list again then (from the job, not from a timer)
  const anyPoolJob = $derived(rowstate.active('pool', []).length > 0 || rowstate.active('migrate', []).length > 0);
  let wasBusy = false;
  $effect(() => { const b = anyPoolJob; if (wasBusy && !b) loadPools(true); wasBusy = b; });
  const TABS = $derived([{ id: 'all', label: 'All' }, ...pools.rows.map((p) => ({ id: p.name, label: p.name })), { id: 'none', label: 'Free' }, { id: 'missing', label: 'Missing' }]);
  const filter = $derived(TABS.some((t) => t.id === route.query.pool) ? route.query.pool : 'all');
  const setFilter = (id) => go(withQuery(P.disks, id === 'all' ? {} : { pool: id }));   // a new address: no ?sel= goes with it
  const selName = $derived(selected());

  const locked = $derived(!!deck?.data?.locked);
  const m = diskModel({ filter: () => filter, sel: () => selName });
  const sel = $derived(m.disk);
  const selMissing = $derived(m.gone);
  const lockTip = (t) => (locked ? 'The storage is locked' : t);
  const fsText = (d) => (d.fs && d.fs !== '-' ? d.fs : '–');
  const addToPool = (pool) => openCreate(AddDisks, { pool, variant: 'empty', snap: pool === m.snapName ? m.snapPool : false });
  const poolForNew = $derived(pools.rows.some((p) => p.name === filter) ? filter : m.snapName || (pools.rows[0]?.name ?? ''));
  const open = (d) => select(d.name);
  const openMissing = (x) => select(x.serial);
  const link = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(diskPath(name)); } };

  const columns = [
    { key: 'name', label: 'Disk' }, { key: 'pool', label: 'Pool', value: (d) => m.poolText(d) }, { key: 'role', label: 'Role', value: (d) => m.roleText(d), optional: true },
    { key: 'model', label: 'Model', value: (d) => m.modelOf(d), optional: true }, { key: 'size', label: 'Size', sort: 'num', value: (d) => d.size }, { key: 'fs', label: 'Format', value: (d) => fsText(d), optional: true },
    { key: 'smart', label: 'SMART', value: (d) => m.verdictOf(d) }, { key: 'temp', label: 'Temp', sort: 'num', value: (d) => Number(d.temp), optional: true },
    { key: 'hours', label: 'Power-on', sort: 'num', value: (d) => Number(d.hours), optional: true },
    { key: 'sleep', label: 'Sleep', value: (d) => sleepText(d.sleep), optional: true },
  ];
  const missCols = [{ key: 'model', label: 'Disk' }, { key: 'dev', label: 'Was' }, { key: 'serial', label: 'Serial' }, { key: 'seen', label: 'Last seen', sort: 'num', value: (x) => x.lastSeen }];
</script>

<PageHeader title="Disks" crumb="Storage" sub="Every disk of this server: where it belongs, how healthy it is, what it has been through.">
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
    <div style="position:relative">
      <Card>
        {#if m.missing.length}
          <Table id="disks-missing" columns={missCols} rows={m.missing} key="serial" compact selected={selMissing?.serial} onrow={openMissing} empty="No disk is missing.">
            {#snippet cell(x, col)}
              {#if col.key === 'model'}<StatusDot state="warn" label={x.model || x.serial} />
              {:else if col.key === 'dev'}<code>{x.dev}</code>
              {:else if col.key === 'serial'}<code>{x.serial}</code>
              {:else}<Muted>{x.lastSeen ? dateOf(x.lastSeen) : '–'}</Muted>{/if}
            {/snippet}
          </Table>
        {:else}
          <Muted as="p">Nothing is missing: every disk the server has seen is still connected.</Muted>
        {/if}
      </Card>
      {#if selName}
        {#if selMissing}
          <QuickLook title={selMissing.model || selMissing.serial} chip="missing" state="warn" stateLabel="not connected" rowKey={selMissing.serial} onclose={close}>
            <Kv items={[{ k: 'Serial', v: selMissing.serial }, { k: 'Was', v: selMissing.dev }, { k: 'Size', v: sizeTxt(selMissing.size) }, { k: 'First seen', v: dateOf(selMissing.first) }, { k: 'Last seen', v: dateOf(selMissing.lastSeen) }, { k: 'Role', v: selMissing.role }]} />
            <Muted as="p" style="padding:12px 16px;margin:0">A missing disk can only be forgotten. If it is a pool member, replace it from its pool first.</Muted>
            {#snippet actions()}
              <Button need="admin" variant="danger" disabled={locked} tooltip={'Take this disk off the list for good'} onclick={() => openCreate(ForgetDisk, { serial: selMissing.serial, model: selMissing.model, dev: selMissing.dev })}><i class="ph ph-trash-simple"></i>Forget…</Button>
            {/snippet}
          </QuickLook>
        {:else if m.mon.loaded}
          <QuickLook title={selName} onclose={close}><Muted as="p" style="padding:12px 16px;margin:0">No missing disk has the serial “{selName}”.</Muted></QuickLook>
        {/if}
      {/if}
    </div>
  {:else}
    {#if deck?.data?.locked}<Banner tone="warn">Storage is locked: pool disks may be missing from this list until it is unlocked.</Banner>{/if}
    {#if m.missing.length && filter === 'all'}
      <Banner tone="warn">{m.missing.length} disk{m.missing.length === 1 ? ' is' : 's are'} missing since the last collector run.
        {#snippet action()}<Button size="sm" tooltip={'Show the disks that are missing'} onclick={() => setFilter('missing')}>Show</Button>{/snippet}
      </Banner>
    {/if}
    <div style="position:relative">
      <Card>
        <div style="overflow-x:auto"><Table id="disks" {columns} rows={m.visible} key="name" compact selected={sel?.name} onrow={open}
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
            {:else}<Muted style="white-space:nowrap">{hoursTxt(d.hours)}</Muted>{/if}
          {/snippet}
        </Table></div>
      </Card>
      {#if selName}
        {#if sel}
          <QuickLook title={sel.name} chip={m.poolText(sel)} state={m.stateOf(sel)} stateLabel={m.wordOf(sel)} rowKey={sel.name} href={diskPath(sel.name)} onclose={close}>
            <Kv items={[
              { k: 'Model', v: m.modelOf(sel) }, { k: 'Serial', v: m.serialOf(sel) }, { k: 'Size', v: sizeTxt(sel.size) }, { k: 'Format', v: fsText(sel) },
              { k: 'Pool', v: m.poolText(sel) }, { k: 'Role', v: diskPool(sel.role) ? m.roleText(sel) : sel.role },
              { k: 'Temperature', v: sel.temp && sel.temp !== '-' ? `${sel.temp} °C` : '' }, { k: 'Power-on', v: hoursTxt(sel.hours) },
            ]} />
            {#if m.doingOf(sel)}<div style="padding:12px 16px;margin:0"><Banner tone="info">{m.doingOf(sel)}… a job is running on this disk; the page follows it.</Banner></div>
            {:else if m.failureOfDisk(sel)}<div style="padding:12px 16px;margin:0"><ErrorNote error={m.failureOfDisk(sel).error} ondismiss={() => rowstate.dismiss(m.failureOfDisk(sel).id)} /></div>{/if}
            {#if m.verdicts[sel.name]?.reason && m.verdicts[sel.name].reason !== '-'}<p style="padding:12px 16px;margin:0">{m.verdicts[sel.name].reason}</p>{/if}
            {#snippet actions()}
              {#if m.isLoose(sel)}
                <Button need="admin" variant="primary" size="sm" disabled={locked} tooltip={lockTip('Pick this disk and see the plan')} onclick={() => addToPool(poolForNew)}><i class="ph ph-plus"></i>Add to a pool…</Button>
              {/if}
            {/snippet}
          </QuickLook>
        {:else if m.mon.loaded}
          <QuickLook title={selName} onclose={close}><Muted as="p" style="padding:12px 16px;margin:0">No disk called “{selName}” is connected. It may have been removed or renamed.</Muted></QuickLook>
        {/if}
      {/if}
    </div>
  {/if}
</PageState>
