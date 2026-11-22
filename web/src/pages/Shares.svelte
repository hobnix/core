<script>
  import { P } from '../paths.js';
  import { tip } from '../ui/tooltip.svelte.js';
  // Storage > Shares: every share (the Samba shares of bulk, the instance volumes of fast) in one list (/storage/shares, filter ?pool=<pool name>). A row opens the quick
  // look over the list (?sel=<name>: selection.svelte.js); "Open page" goes to the page of the share (pages/shares/Share.svelte) with its permissions, snapshots and actions.
  // The folders of deleted shares are kept in the second view (?view=kept). The "in the backup" switch is NOT here (it lives on Backup): a share only shows a read-only badge.
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { StatusDot, Chip, Kv, Banner, Segmented, Card, Row, Muted } from '../ui/index.js';
  import QuickLook from '../ui/QuickLook.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { takeSelection } from '../select.svelte.js';
  import { selected, select, close } from '../selection.svelte.js';
  import { route, go, url } from '../route.svelte.js';
  import { openPlan, openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { sharePending, shareFailed } from './rows.js';
  import Button from '../ui/Button.svelte';
  import NewShare from '../forms/shares/NewShare.svelte';
  import { poolPath } from '../paths.js';
  import { filesLink } from '../files/links.js';
  import { pools, loadPools, poolOfRole } from '../pools.svelte.js';
  import { onMount } from 'svelte';
  import { shareModel, dash, sizeText, mountedBy } from './shares/model.svelte.js';
  import { sharePath } from './shares/path.js';

  onMount(() => { loadPools(); });

  let { deck } = $props();

  const POOLS = $derived([{ id: 'all', label: 'All' }, ...pools.rows.map((p) => ({ id: p.name, label: p.name }))]);
  // a ?pool= this server does not know shows all shares
  const pool = $derived(POOLS.some((p) => p.id === route.query.pool) ? route.query.pool : 'all');
  const view = $derived(route.query.view === 'kept' ? 'kept' : 'shares');
  const query = (o) => {
    const q = new URLSearchParams({ ...(pool !== 'all' ? { pool } : {}), ...(view === 'kept' ? { view } : {}), ...o });
    for (const [k, v] of [...q]) if (!v || v === 'all' || (k === 'view' && v === 'shares')) q.delete(k);
    return `${P.shares}${[...q].length ? `?${q}` : ''}`;
  };
  const selName = $derived(selected());
  // another page (Groups, Users) names a share to look at: it becomes the quick look
  $effect(() => { const n = takeSelection('shares'); if (n) select(n); });
  const locked = $derived(!!deck?.data?.locked);

  const m = shareModel({ sel: () => selName });
  const deleted = poll('/api/sys/shares/deleted', 60000, 'shares-deleted');
  const shares = $derived(m.all.filter((s) => pool === 'all' || s.pool === pool));
  const sel = $derived(shares.find((s) => s.name === selName) ?? null);
  const kept = $derived(rows(deleted).map((r) => ({ name: r[0], kind: r[1], size: Number(r[2]) || 0, disks: r[3] })));
  const host = $derived(deck?.data?.host ?? 'homeserver');
  const link = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(sharePath(name)); } };

  // the old Snapshots address (?view=snapshots) opens the Snapshots tab of the first ZFS share
  let snapOpened = false;
  $effect(() => {
    if (route.query.view === 'snapshots' && !snapOpened && m.overview.loaded) {
      snapOpened = true;
      const z = m.all.find((s) => !s.volume && !!s.disks && s.disks !== '-' && !s.disks.startsWith('data-') && !s.measured);
      if (z) go(sharePath(z.name, 'snapshots'));
    }
  });

  const VIEWS = $derived([{ value: 'shares', label: 'Shares' }, { value: 'kept', label: `Kept folders${deleted.loaded ? ` · ${kept.length}` : ''}` }]);
  const columns = [
    { key: 'name', label: 'Share' }, { key: 'kind', label: 'Kind', optional: true }, { key: 'pool', label: 'Pool', optional: true },
    { key: 'size', label: 'Size', sort: 'num', value: (s) => s.size }, { key: 'backup', label: 'Backup', optional: true },
    { key: 'cache', label: 'Cache', optional: true }, { key: 'disks', label: 'Where', optional: true }, { key: 'mounted', label: 'Mounted by', optional: true },
  ];
  const keptCols = [{ key: 'name', label: 'Kept folder' }, { key: 'kind', label: 'Kind' }, { key: 'size', label: 'Size', sort: 'num' }, { key: 'disks', label: 'Where' }, { key: 'actions', label: '', sort: false, align: 'right' }];
</script>

<PageHeader title="Shares" crumb="Storage" sub={m.measured ? `Sizes measured ${m.measured}.` : 'Network shares, who may use them and what has been kept of them.'}>
  {#snippet actions()}
    {#if m.hasCache}<Button need="admin" icon="arrow-line-down" busy={rowstate.pending('admin', ['cache-mover'])} busyLabel="Emptying…" disabled={locked} tooltip={'Move the uploaded files from the SSD cache to the disks now'} onclick={() => openPlan('admin', ['cache-mover'], 'Empty the upload cache')}>Empty cache</Button>{/if}
    <Button need="admin" variant="primary" tooltip={locked ? 'Storage is locked' : 'Create a share'} disabled={locked} onclick={() => openCreate(NewShare)}><i class="ph ph-plus"></i>New share</Button>
  {/snippet}
</PageHeader>

<Row gap="4" wrap style="margin-bottom:14px">
  <Segmented label="View" value={view} options={VIEWS} onchange={(v) => go(query({ view: v }))} />
  {#if view === 'shares'}
    <Segmented label="Pool" value={pool} options={POOLS.map((p) => ({ value: p.id, label: p.label }))} onchange={(v) => go(query({ pool: v }))} />
  {/if}
</Row>

{#if view === 'kept'}
  <PageState loading={!deleted.loaded} hasData={deleted.data != null} error={deleted.error?.message ?? ''} empty={deleted.loaded && !kept.length} emptyIcon="folder-dashed"
             emptyTitle="No kept folders" emptyText="When a share is deleted its folder stays as a renamed copy until someone removes it for good.">
    <Banner tone="info">Deleting a share keeps its files as <code>name.deleted-date</code>, never published again. Remove a kept folder for good only when you are sure; copies in old backup snapshots stay until they age out.</Banner>
    <Card style="padding:4px 8px;overflow-x:auto">
      <Table id="kept" columns={keptCols} rows={kept} key="name" compact empty="No kept folders.">
        {#snippet cell(k, col)}
          {#if col.key === 'name'}<Row gap="2"><i class="ph ph-folder-dashed"></i><code>{k.name}</code></Row>{#if !sharePending(k.name, rowstate.pending) && shareFailed(k.name, rowstate.failed)} <span use:tip={shareFailed(k.name, rowstate.failed).error.what}><Chip tone="bad">failed</Chip></span>{/if}
          {:else if col.key === 'kind'}<Chip>{k.kind}</Chip>
          {:else if col.key === 'size'}{sizeText(k.size) || '–'}
          {:else if col.key === 'disks'}<Muted>{dash(k.disks) || '–'}</Muted>
          {:else}<Row gap="2" wrap justify="end">
            <Button need="admin" size="sm" icon="arrow-counter-clockwise" busy={rowstate.pending('shares', [k.name, 'undelete'])} busyLabel="Restoring…" disabled={locked} tooltip={'Bring the folder back as a share; nothing is overwritten'} onclick={() => openPlan('shares', [k.name, 'undelete'], `Restore ${k.name.replace(/\.deleted-\d{8}$/, '')}`)}>Restore</Button>
            <Button need="admin" variant="danger" size="sm" icon="trash-simple" busy={rowstate.pending('shares', [k.name, 'purge'])} disabled={locked} tooltip={locked ? 'Storage is locked' : 'Delete this folder and all its files for good'} onclick={() => openPlan('shares', [k.name, 'purge'], `Remove ${k.name} for good`)}>Remove for good</Button>
          </Row>{/if}
        {/snippet}
      </Table>
    </Card>
  </PageState>
{:else}
  <PageState loading={!m.overview.loaded} hasData={m.overview.data != null} error={m.overview.error?.message ?? ''} empty={m.overview.loaded && !shares.length} emptyIcon="folders"
             emptyTitle={pool === 'all' ? 'No shares yet' : `No shares on ${pool}`} emptyText={pool !== 'all' && pool === poolOfRole('apps') ? 'This pool holds the instances’ own volumes; network shares live on the data pool.' : 'A share is a folder that Windows and Linux computers on the network can open.'}>
    {#snippet emptyAction()}<Button need="admin" variant="primary" tooltip={locked ? 'Storage is locked' : 'Create a share'} disabled={locked} onclick={() => openCreate(NewShare)}><i class="ph ph-plus"></i>New share</Button>{/snippet}
    <div style="position:relative">
      <Card style="padding:4px 8px;overflow-x:auto">
        <Table id="shares" {columns} rows={shares} key="name" compact selected={sel?.name} onrow={(s) => select(s.name)} empty="No shares.">
          {#snippet cell(s, col)}
            {#if col.key === 'name'}<Row gap="2" style="display:inline-flex"><i class="ph {s.volume ? 'ph-cube' : s.kind === 'sensitive' ? 'ph-folder-lock' : 'ph-folder'}"></i><a href={url(sharePath(s.name))} onclick={(e) => link(e, s.name)}>{s.name}</a></Row>{#if m.doing(s)} <Muted><i class="ph ph-circle-notch spin"></i> {m.doing(s)}…</Muted>{:else if m.failure(s)} <Chip tone="bad">failed</Chip>{/if}
            {:else if col.key === 'kind'}<Muted>{s.kind}</Muted>
            {:else if col.key === 'pool'}<Chip>{s.pool}</Chip>
            {:else if col.key === 'size'}<span style="white-space:nowrap">{sizeText(s.size) || '–'}</span>
            {:else if col.key === 'backup'}{#if s.volume || s.kind === 'other'}<Muted>–</Muted>{:else}<StatusDot state={s.backup === 'on' ? 'ok' : 'off'} label={s.backup === 'on' ? 'in backup' : 'not in backup'} />{/if}
            {:else if col.key === 'cache'}<Muted>{dash(s.cache) || '–'}</Muted>
            {:else if col.key === 'disks'}<Muted>{dash(s.disks) || '–'}</Muted>
            {:else}<Muted>{dash(s.mounted) || '–'}</Muted>{/if}
          {/snippet}
        </Table>
      </Card>
      {#if selName}
        {#if sel}
          <QuickLook title={sel.name} chip={sel.volume ? 'volume' : sel.kind} state={m.failure(sel) ? 'bad' : m.doing(sel) ? 'info' : ''} stateLabel={m.failure(sel) ? 'failed' : m.doing(sel) ? `${m.doing(sel).toLowerCase()}…` : ''} rowKey={sel.name} href={sharePath(sel.name)} onclose={close}>
            <Kv items={[
              { k: 'Pool', v: sel.pool }, { k: 'Size', v: sizeText(sel.size) },
              { k: 'Network path', v: sel.volume ? '' : `\\\\${host}\\${sel.name}` }, { k: 'Where', v: dash(sel.disks) },
              { k: 'Backup', v: sel.volume || sel.kind === 'other' ? '' : sel.backup === 'on' ? 'in the nightly backup' : 'not in the backup' },
              { k: 'Mounted by', v: mountedBy(sel).map((x) => x.text).join(', ') },
            ]} />
            {#if m.failure(sel)}<div style="padding:12px 16px;margin:0"><ErrorNote error={m.failure(sel).error} ondismiss={() => rowstate.dismiss(m.failure(sel).id)} /></div>{/if}
            <p style="padding:12px 16px;margin:0"><a href={url(poolPath(sel.pool))} onclick={(e) => { e.preventDefault(); go(poolPath(sel.pool)); }}>Pool {sel.pool}</a></p>
            {#snippet actions()}
              {#if !sel.volume}<Button size="sm" icon="folder-open" disabled={locked} tooltip={locked ? 'Storage is locked' : 'Look at the files of this share in the file manager'} onclick={() => go(filesLink({ left: `share:${sel.name}` }))}>Browse</Button>{/if}
            {/snippet}
          </QuickLook>
        {:else if m.overview.loaded}
          <QuickLook title={selName} onclose={close}><Muted as="p" style="padding:12px 16px;margin:0">No share called “{selName}” {pool === 'all' ? 'exists' : `is on ${pool}`}. It may have been deleted or renamed.</Muted></QuickLook>
        {/if}
      {/if}
    </div>
  </PageState>
{/if}
