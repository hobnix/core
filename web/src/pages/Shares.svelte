<script>
  import { P } from '../paths.js';
  import { tip } from '../ui/tooltip.svelte.js';
  // Storage > Shares: every share (the Samba shares of bulk, the instance volumes of fast) in one list, with its permissions, snapshots and
  // history in a drawer; the folders of deleted shares are kept in the second view. /storage/shares?pool=<pool name> filters, ?view=snapshots opens
  // the Snapshots tab. The "in the backup" switch is NOT here (it lives on Backup): a share only shows a read-only badge.
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { StatusDot, Chip, Kv, Drawer, Split, Banner, Segmented, Card, Row, Muted } from '../ui/index.js';
  import { poll, rows } from '../data.svelte.js';
  import { takeSelection, setSelection } from '../select.svelte.js';
  import { route, go } from '../route.svelte.js';
  import { bytes } from '../format.js';
  import { openPlan, openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { sharePending, shareFailed } from './rows.js';
  import Button from '../ui/Button.svelte';
  import NewShare from '../forms/shares/NewShare.svelte';
  import RenameShare from '../forms/shares/RenameShare.svelte';
  import DeleteShare from '../forms/shares/DeleteShare.svelte';
  import RestoreShare from '../forms/shares/RestoreShare.svelte';
  import AddAccess from '../forms/shares/AddAccess.svelte';
  import ShareParity from './storage/ShareParity.svelte';
  import { parseSize } from './storage/pool.js';
  import { filesLink } from '../files/links.js';
  import { pools, loadPools, poolOfRole } from '../pools.svelte.js';
  import { onMount } from 'svelte';

  onMount(() => { loadPools(); });

  let { deck } = $props();

  const POOLS = $derived([{ id: 'all', label: 'All' }, ...pools.rows.map((p) => ({ id: p.name, label: p.name }))]);
  // a ?pool= this server does not know shows all shares
  const pool = $derived(POOLS.some((p) => p.id === route.query.pool) ? route.query.pool : 'all');
  const view = $derived(route.query.view === 'kept' ? 'kept' : 'shares');
  const query = (o) => {
    const q = new URLSearchParams({ ...(pool !== 'all' ? { pool } : {}), ...(view === 'kept' ? { view } : {}), ...o });
    for (const [k, v] of [...q]) if (!v || v === 'all' || (k === 'view' && v === 'shares')) q.delete(k);
    return `/storage/shares${[...q].length ? `?${q}` : ''}`;
  };
  let selName = $state('');
  let tab = $state('info');
  $effect(() => { const n = takeSelection('shares'); if (n) { selName = n; tab = 'info'; } });
  const locked = $derived(!!deck?.data?.locked);

  const overview = poll('/api/sys/shares/overview', 30000, 'shares-overview');
  const deleted = poll('/api/sys/shares/deleted', 60000, 'shares-deleted');
  const cts = poll('/api/sys/ct/list', 30000);

  // name, kind, path, cache, size_bytes, measured, backup, disks, mounted_in (name(ro|rw), comma separated)
  const samba = $derived(rows(overview).map((r) => ({
    name: r[0], kind: r[1], path: r[2], cache: r[3], size: Number(r[4]) || 0, measured: r[5], backup: r[6], disks: r[7], mounted: r[8],
    pool: (r[2] ?? '').split('/')[1] || poolOfRole('data'), volume: false,
  })));
  // ct list: name, type, state, ..., disk (col 9): the instances' own volumes on fast (read only here; the instance owns them)
  const volumes = $derived(rows(cts).filter((r) => r[9] && r[9] !== '-').map((r) => ({
    name: r[0], kind: 'volume', path: '', cache: '-', size: parseSize(r[9]), measured: '', backup: '-', disks: poolOfRole('apps'), mounted: r[0], pool: poolOfRole('apps'), volume: true,
  })));
  const all = $derived([...samba, ...volumes]);
  const shares = $derived(all.filter((s) => pool === 'all' || s.pool === pool));
  const doing = (s) => sharePending(s.name, rowstate.pending);
  const failure = (s) => (doing(s) ? null : shareFailed(s.name, rowstate.failed));
  const sel = $derived(shares.find((s) => s.name === selName) ?? null);
  const measured = $derived(samba.find((s) => s.measured)?.measured ?? '');
  const snapraid = $derived(samba.some((s) => s.measured));
  const hasCache = $derived(samba.some((s) => s.cache === 'on' || s.cache === 'off'));

  const kept = $derived(rows(deleted).map((r) => ({ name: r[0], kind: r[1], size: Number(r[2]) || 0, disks: r[3] })));

  // an auto-selection when the old Snapshots address is opened
  let snapOpened = false;
  $effect(() => {
    if (route.query.view === 'snapshots' && !snapOpened && overview.loaded) {
      snapOpened = true;
      const z = shares.find((s) => isZfs(s));
      if (z) { selName = z.name; tab = 'snap'; }
    }
  });

  const editable = (s) => !!s && !s.volume && s.kind !== 'other';
  const isZfs = (s) => !!s && !s.volume && !!s.disks && s.disks !== '-' && !s.disks.startsWith('data-') && !s.measured;
  const dash = (v) => (v && v !== '-' ? v : '');
  const size = (n) => (!n ? '' : n >= 1e12 ? `${(n / 1e12).toFixed(2)} TB` : n >= 1e9 ? `${Math.round(n / 1e9)} GB` : bytes(n));
  const host = $derived(deck?.data?.host ?? 'homeserver');
  const mountedBy = (s) => (dash(s.mounted) ? s.mounted.split(',').map((x) => x.trim()).filter(Boolean).map((x) => ({ text: x, name: x.replace(/\s*\(.*$/, '') })) : []);
  const openInstance = (name) => { setSelection('instances', name); go(P.instances); };

  // drawer data (ACL and snapshots are per share; read only for the selected one)
  const acl = poll(() => (editable(sel) ? `/api/sys/shares/acl/${encodeURIComponent(sel.name)}` : ''), 30000, 'shares-overview');
  const vis = poll(() => (editable(sel) ? `/api/sys/shares/visible/${encodeURIComponent(sel.name)}` : ''), 30000, 'shares-overview');
  const hist = poll(() => (editable(sel) ? `/api/sys/shares/history/${encodeURIComponent(sel.name)}` : ''), 30000, 'shares-overview');
  const backups = poll(() => (editable(sel) && tab === 'hist' ? '/api/sys/backup/snapshots?tag=shares' : ''), 60000, 'backup-state');
  // sid, name, user|group, level
  const entries = $derived(rows(acl).map((r) => ({ sid: r[0], name: r[1], type: r[2], level: r[3] })));
  // name, created, auto|manual, used (any order: sorted oldest first)
  const snaps = $derived([...rows(hist)].map((r) => ({ name: r[0], created: r[1], how: r[2] })).sort((a, b) => (a.created < b.created ? -1 : a.created > b.created ? 1 : 0)));
  const auto = $derived(snaps.some((x) => x.how === 'auto'));
  const newest = $derived(snaps.length ? snaps[snaps.length - 1] : null);
  // backup restore points: id, time, tags
  const points = $derived(rows(backups).map((r) => ({ id: r[0], time: r[1] })).reverse().slice(0, 10));

  // `visible` | `hidden`: whether the share is listed when someone browses the server (hidden: only by typing its path)
  const visibility = $derived(String(rows(vis)[0]?.[0] ?? '') === 'hidden' ? 'hidden' : 'visible');
  const LEVELS = ['none', 'read', 'write', 'full'];
  const setLevel = (e, l) => l !== e.level && openPlan('shares', [sel.name, 'perm', '--set', `${e.sid}=${l}`], `${e.name}: ${l} on ${sel.name}`);
  const toggle = (what, to) => openPlan('shares', [sel.name, what, '--to', to], `${what === 'cache' ? 'Upload cache' : 'Automatic snapshots'} of ${sel.name} ${to}`);

  const VIEWS = $derived([{ value: 'shares', label: 'Shares' }, { value: 'kept', label: `Kept folders${deleted.loaded ? ` · ${kept.length}` : ''}` }]);
  const columns = [
    { key: 'name', label: 'Share' }, { key: 'kind', label: 'Kind', optional: true }, { key: 'pool', label: 'Pool', optional: true },
    { key: 'size', label: 'Size', sort: 'num', value: (s) => s.size }, { key: 'backup', label: 'Backup', optional: true },
    { key: 'cache', label: 'Cache', optional: true }, { key: 'disks', label: 'Where', optional: true }, { key: 'mounted', label: 'Mounted by', optional: true },
  ];
  const keptCols = [{ key: 'name', label: 'Kept folder' }, { key: 'kind', label: 'Kind' }, { key: 'size', label: 'Size', sort: 'num' }, { key: 'disks', label: 'Where' }, { key: 'actions', label: '', sort: false, align: 'right' }];
</script>

<PageHeader title="Shares" crumb="Storage" sub={measured ? `Sizes measured ${measured}.` : 'Network shares, who may use them and what has been kept of them.'}>
  {#snippet actions()}
    {#if hasCache}<Button need="admin" icon="arrow-line-down" busy={rowstate.pending('admin', ['cache-mover'])} busyLabel="Emptying…" disabled={locked} tooltip={'Move the uploaded files from the SSD cache to the disks now'} onclick={() => openPlan('admin', ['cache-mover'], 'Empty the upload cache')}>Empty cache</Button>{/if}
    <Button need="admin" variant="primary" tooltip={locked ? 'Storage is locked' : 'Create a share'} disabled={locked} onclick={() => openCreate(NewShare)}><i class="ph ph-plus"></i>New share</Button>
  {/snippet}
</PageHeader>

<Row gap="4" wrap style="margin-bottom:14px">
  <Segmented label="View" value={view} options={VIEWS} onchange={(v) => go(query({ view: v }))} />
  {#if view === 'shares'}
    <Segmented label="Pool" value={pool} options={POOLS.map((p) => ({ value: p.id, label: p.label }))} onchange={(v) => { selName = ''; go(query({ pool: v })); }} />
  {/if}
</Row>

{#if view === 'kept'}
  <PageState loading={!deleted.loaded} hasData={deleted.data != null} error={deleted.error?.message ?? ''} empty={deleted.loaded && !kept.length} emptyIcon="folder-dashed"
             emptyTitle="No kept folders" emptyText="When a share is deleted its folder stays as a renamed copy until someone removes it for good.">
    <Banner tone="info">Deleting a share keeps its files as <code>name.deleted-date</code>, never published again. Remove a kept folder for good only when you are sure; copies in old backup snapshots stay until they age out.</Banner>
    <Card style="padding:4px 8px;overflow-x:auto">
      <Table id="kept" columns={keptCols} rows={kept} key="name" compact empty="No kept folders.">
        {#snippet cell(k, col)}
          {#if col.key === 'name'}<span class="nm"><i class="ph ph-folder-dashed"></i><code>{k.name}</code></span>{#if !sharePending(k.name, rowstate.pending) && shareFailed(k.name, rowstate.failed)} <span use:tip={shareFailed(k.name, rowstate.failed).error.what}><Chip tone="bad">failed</Chip></span>{/if}
          {:else if col.key === 'kind'}<Chip>{k.kind}</Chip>
          {:else if col.key === 'size'}{size(k.size) || '–'}
          {:else if col.key === 'disks'}<Muted>{dash(k.disks) || '–'}</Muted>
          {:else}<span class="acts">
            <Button need="admin" size="sm" icon="arrow-counter-clockwise" busy={rowstate.pending('shares', [k.name, 'undelete'])} busyLabel="Restoring…" disabled={locked} tooltip={'Bring the folder back as a share; nothing is overwritten'} onclick={() => openPlan('shares', [k.name, 'undelete'], `Restore ${k.name.replace(/\.deleted-\d{8}$/, '')}`)}>Restore</Button>
            <Button need="admin" variant="danger" size="sm" icon="trash-simple" busy={rowstate.pending('shares', [k.name, 'purge'])} disabled={locked} tooltip={locked ? 'Storage is locked' : 'Delete this folder and all its files for good'} onclick={() => openPlan('shares', [k.name, 'purge'], `Remove ${k.name} for good`)}>Remove for good</Button>
          </span>{/if}
        {/snippet}
      </Table>
    </Card>
  </PageState>
{:else}
  <PageState loading={!overview.loaded} hasData={overview.data != null} error={overview.error?.message ?? ''} empty={overview.loaded && !shares.length} emptyIcon="folders"
             emptyTitle={pool === 'all' ? 'No shares yet' : `No shares on ${pool}`} emptyText={pool !== 'all' && pool === poolOfRole('apps') ? 'This pool holds the instances’ own volumes; network shares live on the data pool.' : 'A share is a folder that Windows and Linux computers on the network can open.'}>
    {#snippet emptyAction()}<Button need="admin" variant="primary" tooltip={locked ? 'Storage is locked' : 'Create a share'} disabled={locked} onclick={() => openCreate(NewShare)}><i class="ph ph-plus"></i>New share</Button>{/snippet}
    <Split open={!!sel}>
      {#snippet list()}
        <Card style="padding:4px 8px;overflow-x:auto">
          <Table id="shares" {columns} rows={shares} key="name" compact selected={sel?.name} onrow={(s) => { selName = s.name; tab = 'info'; }} empty="No shares.">
            {#snippet cell(s, col)}
              {#if col.key === 'name'}<span class="nm"><i class="ph {s.volume ? 'ph-cube' : s.kind === 'sensitive' ? 'ph-folder-lock' : 'ph-folder'}"></i>{s.name}</span>{#if doing(s)} <Muted><i class="ph ph-circle-notch spin"></i> {doing(s)}…</Muted>{:else if failure(s)} <Chip tone="bad">failed</Chip>{/if}
              {:else if col.key === 'kind'}<Muted>{s.kind}</Muted>
              {:else if col.key === 'pool'}<Chip>{s.pool}</Chip>
              {:else if col.key === 'size'}<span class="nw">{size(s.size) || '–'}</span>
              {:else if col.key === 'backup'}{#if s.volume || s.kind === 'other'}<Muted>–</Muted>{:else}<StatusDot state={s.backup === 'on' ? 'ok' : 'off'} label={s.backup === 'on' ? 'in backup' : 'not in backup'} />{/if}
              {:else if col.key === 'cache'}<Muted>{dash(s.cache) || '–'}</Muted>
              {:else if col.key === 'disks'}<Muted>{dash(s.disks) || '–'}</Muted>
              {:else}<Muted>{dash(s.mounted) || '–'}</Muted>{/if}
            {/snippet}
          </Table>
        </Card>
      {/snippet}
      {#snippet side()}
        {#if sel}
          <Drawer title={sel.name} chip={sel.volume ? 'volume' : sel.kind} bind:tab onclose={() => (selName = '')}
                  tabs={editable(sel) ? [{ id: 'info', label: 'Overview' }, { id: 'perm', label: 'Permissions' }, { id: 'snap', label: 'Snapshots' }, { id: 'hist', label: 'History' }] : []}>
            {#snippet children(t)}
              {#if failure(sel)}<ErrorNote error={failure(sel).error} ondismiss={() => rowstate.dismiss(failure(sel).id)} />{/if}
              {#if !editable(sel) || t === 'info'}
                <Kv items={[
                  { k: 'Pool', v: sel.pool }, { k: 'Size', v: size(sel.size) },
                  { k: 'Network path', v: sel.volume ? '' : `\\\\${host}\\${sel.name}` }, { k: 'Folder', v: sel.path }, { k: 'Where', v: dash(sel.disks) },
                  { k: 'Upload cache', v: dash(sel.cache) },
                  { k: 'Backup', v: sel.volume || sel.kind === 'other' ? '' : sel.backup === 'on' ? 'in the nightly backup' : 'not in the backup' },
                ]} />
                <div class="pad">
                  {#if mountedBy(sel).length}
                    <Row style="margin-bottom:8px"><b>Mounted by</b></Row>
                    <Row wrap gap="3" style="margin-bottom:8px">{#each mountedBy(sel) as m}<Button size="sm" tooltip={`Open the instance ${m.name}`} onclick={() => openInstance(m.name)}><i class="ph ph-cube"></i>{m.text}</Button>{/each}</Row>
                  {:else}<Muted as="p">No instance mounts this {sel.volume ? 'volume' : 'share'}.</Muted>{/if}
                  {#if !sel.volume && sel.kind !== 'other' && /^data-/.test(sel.disks)}<ShareParity share={sel.name} {locked} />{/if}
                  {#if sel.volume}<Muted as="p">An instance volume belongs to its instance: change it there.</Muted>{:else if sel.kind !== 'other'}
                    <Muted as="p">Whether it is in the backup is set on <button class="link-btn" onclick={() => go(P.backup)}>Backup</button>.</Muted>
                  {/if}
                </div>
              {:else if t === 'perm'}
                <div class="pad">
                  <Row align="baseline" gap="3" style="margin-bottom:8px"><b>Visibility</b><Muted>in the network list of the server</Muted></Row>
                  <div class="arow2">
                    <Muted>Hidden shares can still be opened by typing the path. Visible shares are listed only for people with at least read access below.</Muted>
                    <div class="lv" role="group" aria-label="Visibility of {sel.name}">
                      {#each ['hidden', 'visible'] as v}<button type="button" class="lvb" class:on={v === visibility} aria-pressed={v === visibility} disabled={locked || !vis.loaded} use:tip={v === visibility ? '' : `Make ${sel.name} ${v}`} onclick={() => v !== visibility && openPlan('shares', [sel.name, 'visibility', '--to', v], `${sel.name}: ${v}`)}>{v === 'hidden' ? 'Hidden' : 'Visible'}</button>{/each}
                    </div>
                  </div>
                  <Row align="baseline" gap="3" style="margin:16px 0 8px"><b>Permissions</b><Muted>apply at the next connection</Muted><span class="grow"></span>
                    <Button need="admin" size="sm" tooltip={locked ? 'Storage is locked' : 'Give a user or group access to this share'} disabled={locked} onclick={() => openCreate(AddAccess, { share: sel.name, taken: entries.map((e) => e.sid) })}><i class="ph ph-plus"></i>Add</Button></Row>
                  {#each entries as e (e.sid)}
                    <div class="arow2">
                      <span class="nm"><i class="ph {e.type === 'group' ? 'ph-users-three' : 'ph-user'}"></i>{e.name}</span>
                      <div class="lv" role="group" aria-label="Access of {e.name}">
                        {#each LEVELS as l}<button type="button" class="lvb" class:on={l === e.level} aria-pressed={l === e.level} disabled={locked} use:tip={l === e.level ? '' : `Set ${e.name} to ${l}`} onclick={() => setLevel(e, l)}>{l}</button>{/each}
                      </div>
                    </div>
                  {:else}
                    <Muted as="p">{acl.loaded ? 'No entries.' : 'Loading…'}</Muted>
                  {/each}
                </div>
              {:else if t === 'snap'}
                <div class="pad">
                  {#if !isZfs(sel)}
                    <Banner tone="info">Snapshots exist on ZFS only. {snapraid ? 'This server keeps its shares on SnapRAID, so the restore points come from the backup (History tab).' : 'This share is not on a ZFS dataset.'}</Banner>
                  {:else}
                    <Row align="baseline" gap="3" style="margin-bottom:8px"><b>Snapshots</b><Muted>{auto ? 'automatic: hourly, kept 24 h / 7 d / 4 w' : 'automatic snapshots are off'}</Muted></Row>
                    {#each [...snaps].reverse() as n (n.name)}
                      <div class="trow"><code class="grow">{n.name}</code><Muted>{n.created}</Muted><Chip>{n.how}</Chip></div>
                    {:else}<Muted as="p">{hist.loaded ? 'No snapshots yet.' : 'Loading…'}</Muted>{/each}
                    <Muted as="p">ZFS can only go back to the newest snapshot; newer ones are deleted by a roll-back.</Muted>
                  {/if}
                </div>
              {:else}
                <div class="pad">
                  <Row align="baseline" gap="3" style="margin-bottom:8px"><b>Restore points</b><Muted>from the backup, newest first</Muted></Row>
                  {#each points as p (p.id)}<div class="trow"><code>{p.id}</code><span class="grow"></span><Muted>{p.time}</Muted></div>
                  {:else}<Muted as="p">{backups.loaded ? 'The backup has no restore points for shares yet.' : 'Loading…'}</Muted>{/each}
                  <Muted as="p">A restore puts the files into the share <code>restored</code>; the original is not touched.</Muted>
                </div>
              {/if}
            {/snippet}
            {#snippet actions()}
              {#if !sel.volume}<Button size="sm" disabled={locked} tooltip={locked ? 'Storage is locked' : 'Look at the files of this share in the file manager'} onclick={() => go(filesLink({ left: `share:${sel.name}` }))}><i class="ph ph-folder-open"></i>Browse</Button>{/if}
              {#if editable(sel)}
                {#if tab === 'snap' && isZfs(sel)}
                  <Button need="admin" size="sm" icon="camera" busy={rowstate.pending('shares', [sel.name, 'snapshot'])} disabled={locked} tooltip={locked ? 'Storage is locked' : 'Take a snapshot of this share now'} onclick={() => openPlan('shares', [sel.name, 'snapshot'], `Snapshot ${sel.name}`)}>Snapshot now</Button>
                  <Button need="admin" size="sm" icon="clock-clockwise" busy={(rowstate.pending('shares', [sel.name, 'auto', '--to', 'off']) || rowstate.pending('shares', [sel.name, 'auto', '--to', 'on']))} disabled={locked || !hist.loaded || hist.error} tooltip={locked ? 'Storage is locked' : !hist.loaded || hist.error ? 'The snapshot list is not available' : auto ? 'Stop the nightly snapshots' : 'Take a snapshot every night'} onclick={() => toggle('auto', auto ? 'off' : 'on')}>Automatic {auto ? 'off' : 'on'}</Button>
                  <Button need="admin" size="sm" icon="arrow-u-up-left" busy={rowstate.pending('shares', [sel.name, 'rollback', '--snapshot', newest?.name])} disabled={locked || !newest} tooltip={newest ? `Roll back to ${newest.name}` : 'No snapshot to roll back to'} onclick={() => openPlan('shares', [sel.name, 'rollback', '--snapshot', newest.name], `Roll back ${sel.name}`)}>Roll back</Button>
                {:else if tab === 'hist'}
                  <Button need="admin" size="sm" tooltip={locked ? 'Storage is locked' : 'Bring files back from the backup'} disabled={locked} onclick={() => openCreate(RestoreShare, { share: sel.name })}><i class="ph ph-arrow-counter-clockwise"></i>Restore from backup…</Button>
                {:else}
                  {#if sel.kind === 'shares' && (sel.cache === 'on' || sel.cache === 'off')}<Button need="admin" size="sm" icon="lightning" busy={(rowstate.pending('shares', [sel.name, 'cache', '--to', 'off']) || rowstate.pending('shares', [sel.name, 'cache', '--to', 'on']))} disabled={locked} tooltip={locked ? 'Storage is locked' : sel.cache === 'on' ? 'Upload straight to the disks, not the SSD cache' : 'Upload to the SSD cache first, move to the disks later'} onclick={() => toggle('cache', sel.cache === 'on' ? 'off' : 'on')}>Cache {sel.cache === 'on' ? 'off' : 'on'}</Button>{/if}
                  <Button need="admin" size="sm" tooltip={locked ? 'Storage is locked' : 'Change the name of this share'} disabled={locked} onclick={() => openCreate(RenameShare, { share: sel.name })}><i class="ph ph-pencil-simple"></i>Rename…</Button>
                  <Button need="admin" size="sm" icon="wrench" busy={rowstate.pending('shares', [sel.name, 'repair'])} busyLabel="Repairing…" disabled={locked} tooltip={'Hand the files of this share to adminuser again'} onclick={() => openPlan('shares', [sel.name, 'repair'], `Repair ${sel.name}`)}>Repair</Button>
                  <Button need="admin" variant="danger" size="sm" tooltip={locked ? 'Storage is locked' : 'Remove this share (the plan shows what happens to its files)'} disabled={locked} onclick={() => openCreate(DeleteShare, { share: sel.name })}><i class="ph ph-trash-simple"></i>Delete…</Button>
                {/if}
              {/if}
            {/snippet}
          </Drawer>
        {/if}
      {/snippet}
    </Split>
  </PageState>
{/if}

<style>
  .pad { padding: 12px 16px; }
  .nm { display: inline-flex; align-items: center; gap: 8px; }
  .nm i { color: var(--fg-3); }
  .acts { display: inline-flex; gap: 6px; flex-wrap: wrap; }
  .nw { white-space: nowrap; }
  code { font-size: 12px; }
  .trow { display: flex; align-items: center; gap: 10px; padding: 7px 0; border-bottom: 1px solid var(--line); }
  .arow2 { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 7px 0; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
  .lv { display: inline-flex; border: 1px solid var(--line-2); }
  .lvb { all: unset; box-sizing: border-box; cursor: pointer; padding: 4px 9px; font-size: 12px; color: var(--fg-2); }
  .lvb + .lvb { border-left: 1px solid var(--line-2); }
  .lvb:hover:not(:disabled) { background: var(--panel-2); }
  .lvb.on { background: var(--panel-3); color: var(--fg); font-weight: 600; }
  .lvb:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
  .lvb:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
