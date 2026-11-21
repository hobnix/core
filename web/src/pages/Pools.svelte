<script>
  import { P, poolPath } from '../paths.js';
  import { onMount } from 'svelte';
  import { tip } from '../ui/tooltip.svelte.js';
  // Storage > Pools: the list (/storage/pools) and the detail of one pool (/storage/pools/<name>) in one page. Membership changes (add, adopt,
  // replace, remove, close, open, convert) and scrub / sync live here; everything about a single disk lives on Disks (a link, not a copy).
  import UsageBar from '../shell/UsageBar.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { StatusDot, Chip, Kv, Banner, Card, Row, Stack, Muted } from '../ui/index.js';
  import { poll, rows } from '../data.svelte.js';
  import { route, go } from '../route.svelte.js';
  import { filesLink } from '../files/links.js';
  import { setSelection } from '../select.svelte.js';
  import { openPlan, openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { poolPending, syncPending, failedOf } from './storage/pending.js';
  import Button from '../ui/Button.svelte';
  import AddDisks from '../forms/storage/AddDisks.svelte';
  import MigrateUnraid from '../forms/storage/MigrateUnraid.svelte';
  import ReplaceMember from '../forms/storage/ReplaceMember.svelte';
  import RemoveMember from '../forms/storage/RemoveMember.svelte';
  import ConvertPool from '../forms/storage/ConvertPool.svelte';
  import CloseDisk from '../forms/storage/CloseDisk.svelte';
  import SyncRefused from './storage/SyncRefused.svelte';
  import { parseInfo, percentOf, diskPool, serialIn, sizeTxt, parseSize, poolTopic } from './storage/pool.js';
  import { pools, loadPools, poolOfRole, poolRow } from '../pools.svelte.js';
  import { live } from '../live.svelte.js';

  let { deck } = $props();

  onMount(() => { loadPools(true); });
  // a pool job (create, add, replace, remove, take over Unraid) that ends changes the pool list: read it again then, from the job, not from a timer
  const anyPoolJob = $derived(rowstate.active('pool', []).length > 0 || rowstate.active('migrate', []).length > 0);
  let wasBusy = false;
  $effect(() => { const b = anyPoolJob; if (wasBusy && !b) loadPools(true); wasBusy = b; });
  // what a pool is doing now (any job that names it, also one started in a terminal; a SnapRAID sync names no pool) and the newest failure of its jobs
  const doingOf = (name, isSnapPool) => poolPending(name, rowstate.active) || (isSnapPool ? syncPending(rowstate.active) : '');
  const failureOf = (name) => failedOf('pool', [name], rowstate.failedLead) ?? rowstate.failed('system', ['scrub', '--pool', name]) ?? rowstate.failed('system', ['sync']);
  const pool = $derived(route.path.startsWith('/storage/pools/') ? route.path.slice('/storage/pools/'.length) : '');
  const row = $derived(poolRow(pool));
  const role = $derived(row?.role ?? '');
  const unknownPool = $derived(!!pool && pools.loaded && !pools.legacy && !row);
  const locked = $derived(!!deck?.data?.locked);

  // ── shared by list and detail
  const disks = poll('/api/sys/monitor/disks', 30000, 'monitor-disks');
  // monitor disks: name, bytes, SSD/HDD, role, temp, health, hours, reallocated, pending, crc, model+serial, free
  const monitor = $derived(rows(disks).map((r) => ({ name: r[0], role: r[3], model: r[10], free: r[11] })));
  const freeDisks = $derived(monitor.filter((d) => d.role === 'free' || d.role === 'mounted'));

  // the facts of the one SnapRAID pool (D6) come from its `pool info`; a ZFS pool says its layout and state in the list row
  const snapName = $derived(pools.rows.find((p) => p.kind !== 'zfs')?.name ?? '');
  const snapInfo = poll(() => (snapName ? `/api/sys/pool/info?pool=${snapName}` : ''), 15000, () => poolTopic('info', snapName, live.topics));
  const snapFacts = $derived(parseInfo(rows(snapInfo)).facts);
  const isSnap = (f) => /SnapRAID/i.test(f.layout ?? '');
  const layoutOf = (f) => (isSnap(f) ? 'SnapRAID' : /ZFS/i.test(f.layout ?? '') ? 'ZFS mirror' : (f.layout ?? ''));
  const dotOf = (state) => {
    const t = (state ?? '').toLowerCase();
    return /degraded|fault|unavail|no parity/.test(t) ? 'bad' : /online|protected/.test(t) ? 'ok' : /not/.test(t) ? 'warn' : 'off';
  };

  // ── the list
  const list = $derived(pools.rows.map((r) => {
    const isSnapRow = r.name === snapName, f = isSnapRow ? snapFacts : {}, dp = deck?.data?.pools?.[r.name];
    const failed = isSnapRow && snapInfo.loaded && !rows(snapInfo).length;
    const created = r.state !== 'missing' && !(isSnapRow && /not created/i.test(f.state ?? ''));
    return {
      name: r.name, role: r.role, loaded: pools.loaded && (!isSnapRow || snapInfo.loaded), failed, created,
      layout: r.kind === 'snapraid' ? 'SnapRAID' : r.kind === 'zfs' ? 'ZFS' : layoutOf(f),
      doing: doingOf(r.name, r.kind !== 'zfs'),
      state: r.state !== '-' ? r.state.toLowerCase() : (f.state ?? '').toLowerCase(), sync: f['last sync'] ?? '',
      size: dp?.size ?? 0, used: dp?.used ?? null, count: monitor.filter((d) => diskPool(d.role) === r.name).length,
    };
  }));
  const shown = $derived(list.filter((p) => p.created || p.failed || !p.loaded));
  const notYet = $derived(list.filter((p) => p.loaded && !p.failed && !p.created));
  const columns = [
    { key: 'name', label: 'Pool' }, { key: 'layout', label: 'Layout', optional: true }, { key: 'usage', label: 'Usage', sort: 'num', value: (p) => p.used ?? -1 },
    { key: 'state', label: 'State' }, { key: 'count', label: 'Disks', sort: 'num', optional: true }, { key: 'sync', label: 'Last sync', optional: true },
  ];

  // ── the detail
  const info = poll(() => (pool && !unknownPool ? `/api/sys/pool/info?pool=${pool}` : ''), 15000, () => poolTopic('info', pool, live.topics));
  const memb = poll(() => (pool && !unknownPool ? `/api/sys/pool/members?pool=${pool}` : ''), 15000, () => poolTopic('members', pool, live.topics));
  const shares = poll(() => (role === 'data' ? '/api/sys/shares/overview' : ''), 30000, 'shares-overview');
  const cts = poll(() => (role === 'apps' ? '/api/sys/ct/list' : ''), 30000);

  // what the pool is doing (`hs sys pool state`): lock <free|busy|pool-change|unknown> text / paused <yes|no> text / scrub <pool> <running|ok|errors|never|unknown> text / sync bulk <running|ok|never|unknown> text.
  // `pool info` has no scrub field on either layout (SnapRAID: "last sync" only), so the scrub and sync lines come from here.
  const st = poll(() => (pool && !unknownPool ? `/api/sys/pool/state?pool=${pool}` : ''), 10000, () => poolTopic('state', pool, live.topics));
  const stRows = $derived(rows(st));
  const lockRow = $derived(stRows.find((r) => r[0] === 'lock'));
  const lockState = $derived(lockRow?.[1] ?? '');
  const paused = $derived(stRows.find((r) => r[0] === 'paused')?.[1] === 'yes');
  const scrubRow = $derived(stRows.find((r) => r[0] === 'scrub' && r[1] === pool));
  const syncRow = $derived(stRows.find((r) => r[0] === 'sync' && r[1] === pool));
  const running = $derived(scrubRow?.[2] === 'running' || syncRow?.[2] === 'running');
  const lockTxt = { free: 'free', busy: 'in use', 'pool-change': 'held by a pool change', unknown: 'unknown' };

  const f = $derived(parseInfo(rows(info)).facts);
  const snap = $derived(isSnap(f));
  const layout = $derived(layoutOf(f));
  const notCreated = $derived(info.loaded && /not created/i.test(f.state ?? ''));
  const failed = $derived(info.loaded && !rows(info).length);
  const dp = $derived(deck?.data?.pools?.[pool]);
  const stateTxt = $derived((f.state ?? '').toLowerCase());
  const pctUsed = $derived(percentOf(f.used) ?? (dp?.size ? Math.round((dp.used / dp.size) * 100) : null));

  // pool members: name, bytes, state, group (mirror | data | parity), filesystem, encryption, closed (SnapRAID: no new files)
  const members = $derived(rows(memb).map((r) => {
    const mon = monitor.find((m) => (snap ? m.role === `bulk ${r[0]}` : diskPool(m.role) === pool && serialIn(m.model, r[0])));
    return { name: r[0], dev: mon?.name ?? r[0], size: Number(r[1]), free: mon?.free, state: r[2], group: r[3], fs: r[4], enc: r[5], closed: r[6] === 'closed' };
  }));
  const memberDot = (m) => (m.state === 'ONLINE' ? 'ok' : /DEGRADED|FAULT|UNAVAIL|REMOVED/i.test(m.state) ? 'bad' : 'warn');
  const convertible = $derived(snap ? members.filter((m) => m.group === 'data' && m.state === 'ONLINE').map((m) => m.name) : []);
  const luks = $derived(members.some((m) => m.enc === 'luks'));

  const doing = $derived(pool ? doingOf(pool, snap) : '');
  const failure = $derived(doing || !pool ? null : failureOf(pool));
  const unavailable = $derived(locked || failed || !layout);
  const why = (t) => (locked ? 'The storage is locked: the pools are down' : unavailable ? 'The pool is not available' : t);
  const runTitle = $derived(why(snap ? 'Update the parity now (shows the plan first)' : `Scrub ${pool} now (shows the plan first)`));

  // shares overview: name, kind, path, cache, size_bytes, ...
  const shareRows = $derived(rows(shares).filter((r) => r[1] !== 'other'));
  const shareBytes = $derived(shareRows.reduce((a, r) => a + (Number(r[4]) || 0), 0));
  // ct list: name, type, state, address, ram, cpu, autostart, mac pinned, docker, disk, ...
  const volumes = $derived(rows(cts).filter((r) => r[9] && r[9] !== '-'));
  const volBytes = $derived(volumes.reduce((a, r) => a + parseSize(r[9]), 0));

  const facts = $derived.by(() => {
    const out = [];
    if (layout) out.push({ k: 'Layout', v: layout });
    const enc = members.find((m) => m.enc && m.enc !== '-');
    if (enc) out.push({ k: 'Encryption', v: `${enc.enc === 'luks' ? 'LUKS per disk' : enc.enc}${locked ? '' : ' · open'}` });
    if (syncRow) out.push({ k: 'Parity sync', v: syncRow[2] === 'running' ? 'running now' : syncRow[3] });
    else if (f['last sync']) out.push({ k: 'Last parity sync', v: f['last sync'] });
    if (scrubRow) out.push({ k: 'Scrub', v: scrubRow[2] === 'running' ? `running, since ${scrubRow[3]}` : scrubRow[2] === 'unknown' ? '–' : scrubRow[3] });
    if (lockRow && lockState !== 'unknown') out.push({ k: 'Bulk lock', v: lockTxt[lockState] ?? lockState });
    if (f['upload cache']) out.push({ k: 'Upload cache', v: f['upload cache'].replace(/\s*\(.*/, '') });
    if (snap) out.push({ k: 'Merged by mergerfs', v: `/mnt/${pool}/pool, shared as /${pool}` });
    if (pool === poolOfRole('apps')) out.push({ k: 'Incus storage pool', v: '"default"' });
    return out;
  });

  const fsText = (m) => (m.fs && m.fs !== '-' ? m.fs : '–');
  const memberCols = [
    { key: 'dev', label: 'Disk' }, { key: 'role', label: 'Role', value: (m) => (snap ? m.name : m.group) }, { key: 'state', label: 'State' },
    { key: 'size', label: 'Size', sort: 'num', value: (m) => m.size, optional: true }, { key: 'fs', label: 'Format', value: (m) => fsText(m), optional: true }, { key: 'actions', label: '', sort: false, align: 'right' },
  ];
  const openDisk = (m) => { setSelection('disks', m.dev); go(`${P.disks}?pool=${pool}`); };
  const addPool = (variant) => openCreate(AddDisks, { pool, variant, snap: notCreated ? undefined : snap });
</script>

{#if !pool}
  <PageHeader title="Pools" crumb="Storage" sub="How the disks are grouped, how full they are and whether the redundancy holds.">
    {#snippet actions()}
      {#if freeDisks.length}<Button tooltip={'Show the disks that belong to no pool'} onclick={() => go(P.disks + '?pool=none')}><i class="ph ph-hard-drive"></i>{freeDisks.length} free disk{freeDisks.length === 1 ? '' : 's'}</Button>{/if}
    {/snippet}
  </PageHeader>
  <PageState loading={!pools.loaded} hasData={pools.loaded} empty={!shown.length} emptyIcon="cylinder" emptyTitle="No pool yet"
             emptyText="A pool groups disks into one place for the shares. Pick free disks to create the first one.">
    <Card><div style="overflow-x:auto">
      <Table id="pools" {columns} rows={shown} key="name" onrow={(p) => go(poolPath(p.name))} empty="No pools.">
        {#snippet cell(p, col)}
          {#if col.key === 'name'}<Row gap="2" style="font-weight:500"><i class="ph {p.role === 'apps' ? 'ph-lightning' : 'ph-cylinder'}"></i>{p.name}</Row>
          {:else if col.key === 'layout'}{#if p.layout}<Chip>{p.layout}</Chip>{:else}–{/if}
          {:else if col.key === 'usage'}{#if p.size}<UsageBar used={p.used} size={p.size} />{:else}<Muted>{p.loaded ? 'not mounted' : '…'}</Muted>{/if}
          {:else if col.key === 'state'}{#if p.doing}<StatusDot state="info" label="{p.doing.toLowerCase()}…" />{:else}<StatusDot state={p.failed ? 'bad' : dotOf(p.state)} label={p.failed ? 'cannot be read' : p.state || (p.loaded ? 'unknown' : 'reading')} />{/if}
          {:else if col.key === 'count'}{p.count || '–'}
          {:else}<Muted>{p.sync || '–'}</Muted>{/if}
        {/snippet}
      </Table>
    </div></Card>
    {#if notYet.length}
      <Muted as="p">Not found (not created yet or not imported): {notYet.map((p) => p.name).join(', ')}. Open the pool's page to create it from free disks.</Muted>
    {/if}
  </PageState>
{:else}
  <PageHeader title={pool} crumb="Storage › Pools" sub={layout ? `${layout}${members.length ? ` · ${members.length} disk${members.length === 1 ? '' : 's'}` : ''}${luks ? ' · LUKS' : ''}` : ''}>
    {#snippet actions()}
      <Button tooltip={'Back to the list of pools'} onclick={() => go(P.pools)}><i class="ph ph-caret-left"></i>All pools</Button>
      <Button need="admin" disabled={locked || failed} tooltip={locked ? 'The storage is locked: the pools are down' : 'Pick free disks and see the plan'} onclick={() => addPool('empty')}><i class="ph ph-plus"></i>{notCreated ? 'Create pool' : snap ? 'Add disks' : 'Add mirror pair'}</Button>
      {#if snap}<Button need="admin" disabled={why('') !== ''} tooltip={why('Bring a disk that already holds files into the pool')} onclick={() => addPool('adopt')}><i class="ph ph-hand-arrow-down"></i>Adopt disks</Button>{/if}
      {#if snap}<Button need="admin" disabled={why('') !== ''} tooltip={why('Take over the disks of an Unraid server: merged shares, the old parity disk becomes parity')} onclick={() => openCreate(MigrateUnraid, { pool })}><i class="ph ph-arrow-bend-down-right"></i>Take over Unraid</Button>{/if}
      <Button need="admin" variant="primary" icon={snap ? 'arrows-clockwise' : 'broom'} disabled={unavailable || notCreated} busy={snap ? rowstate.pending('system', ['sync']) : rowstate.pending('system', ['scrub', '--pool', pool])} tooltip={runTitle}
        onclick={() => (snap ? openPlan('system', ['sync'], 'Sync parity') : openPlan('system', ['scrub', '--pool', pool], `Scrub ${pool}`))}>{snap ? 'Sync parity now' : 'Scrub now'}</Button>
    {/snippet}
  </PageHeader>

  <PageState loading={!info.loaded && !unknownPool} hasData={info.loaded} error={unknownPool ? `There is no pool ${pool} on this server.` : failed ? 'the pool could not be read' : ''}>
    {#if notCreated}
      <Banner tone="info">The pool {pool} has not been created yet. {#if freeDisks.length}{freeDisks.length} free disk{freeDisks.length === 1 ? ' is' : 's are'} available.{:else}There is no free disk to build it from.{/if}
        {#snippet action()}<Button need="admin" size="sm" tooltip={locked ? 'Storage is locked' : 'Pick free disks and make a new pool'} disabled={locked} onclick={() => addPool('empty')}>Create pool</Button>{/snippet}
      </Banner>
    {:else}
     <Stack gap="4">
      {#if doing}<Banner tone="info">{doing}… a job is running on {pool}; this page follows it.</Banner>{/if}
      {#if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
      {#if paused}<Banner tone="warn">The health check paused the parity sync, scrub and upload cache mover because of a failing disk or pool. Lift it under Health (<code>hs health resume</code>).</Banner>{/if}
      {#if snap}<SyncRefused {locked} />{/if}
      {#if lockState === 'pool-change'}<Banner tone="info">A pool change is running and owns the bulk lock: syncs, scrubs and share renames wait or are skipped until it is done.</Banner>
      {:else if lockState === 'busy'}<Banner tone="info">{running ? 'A sync or scrub is running.' : 'Something holds the bulk lock (a parity sync, scrub, upload cache mover, share rename or disk move).'} Changes that need the lock wait until it is free.</Banner>{/if}
      <Card pad="lg">
        {#if dp?.size}
          <Row gap="3"><StatusDot state={dotOf(stateTxt)} label={stateTxt || 'unknown'} /><Muted>{pctUsed != null ? `${pctUsed} % used` : ''}</Muted></Row>
          <UsageBar block used={dp.used} size={dp.size} />
        {:else}
          <Muted as="p">{info.loaded ? 'No capacity available (the pool is not mounted).' : 'Loading…'}</Muted>
        {/if}
        {#if facts.length}<Kv items={facts} cols={3} />{/if}
      </Card>

      <Card title="Members">
        {#snippet actions()}
          <Muted>{members.some((m) => m.state !== 'ONLINE') ? 'check the state column' : members.length ? (snap ? 'all present' : 'all ONLINE') : ''}</Muted>
          <Button variant="ghost" size="sm" tooltip={'Show the disks of this pool'} onclick={() => go(`${P.disks}?pool=${pool}`)}>Disks of this pool<i class="ph ph-caret-right"></i></Button>
        {/snippet}
        <div style="overflow-x:auto">
          <Table id="pool-members" columns={memberCols} rows={members} key="name" compact loading={!memb.loaded} empty="No members.">
            {#snippet cell(m, col)}
              {#if col.key === 'dev'}<button class="link-btn" use:tip={'Open this disk'} onclick={() => openDisk(m)}><code>{m.dev}</code></button>
              {:else if col.key === 'role'}<Chip>{snap ? m.name : m.group}</Chip>{#if m.closed} <Chip>closed</Chip>{/if}
              {:else if col.key === 'state'}<StatusDot state={memberDot(m)} label={(m.state ?? '').toLowerCase()} />
              {:else if col.key === 'size'}<span style="white-space:nowrap"><UsageBar free={m.free} size={m.size} width={96} /></span>
              {:else if col.key === 'fs'}<Muted style="white-space:nowrap">{fsText(m)}</Muted>
              {:else}
                <Row gap="1" justify="end">
                  {#if snap ? /^data-\d+$/.test(m.name) : true}<Button variant="ghost" class="btn-icon" style="width:28px;min-height:28px" tooltip={snap ? 'Browse the files of this disk' : 'Browse the files of this pool'} aria-label="Browse" disabled={locked} onclick={() => go(filesLink({ left: snap ? `disk:${m.name}` : `pool:${pool}` }))}><i class="ph ph-folder-open"></i></Button>{/if}
                  <Button need="admin" variant="ghost" class="btn-icon" style="width:28px;min-height:28px" tooltip={'Replace this disk'} aria-label="Replace" disabled={locked} onclick={() => openCreate(ReplaceMember, { pool, member: m.name, snap })}><i class="ph ph-swap"></i></Button>
                  {#if snap}<Button need="admin" variant="ghost" class="btn-icon" style="width:28px;min-height:28px" tooltip={convertible.includes(m.name) ? 'Change filesystem or LUKS; its files are moved away first' : 'Only an online data disk can be converted'} aria-label="Convert" disabled={locked || !convertible.includes(m.name)} onclick={() => openCreate(ConvertPool, { pool, member: m.name, members: convertible })}><i class="ph ph-arrows-clockwise"></i></Button>{/if}
                  {#if snap && m.group === 'data'}<Button need="admin" variant="ghost" class="btn-icon" style="width:28px;min-height:28px" tooltip={m.closed ? 'Closed: no new files. Open it again or move its files away' : 'Stop putting new files on this disk (optionally move its files away)'} aria-label={m.closed ? 'Open' : 'Close'} disabled={locked || m.state !== 'ONLINE'} onclick={() => openCreate(CloseDisk, { pool, member: m.name, closed: m.closed })}><i class="ph ph-{m.closed ? 'lock-key-open' : 'prohibit'}"></i></Button>{/if}
                  <Button need="admin" variant="ghost" class="btn-icon" style="width:28px;min-height:28px" tooltip={snap ? 'Remove this disk' : 'Detach this disk'} aria-label={snap ? 'Remove' : 'Detach'} disabled={locked} onclick={() => openCreate(RemoveMember, { pool, member: m.name, snap })}><i class="ph ph-link-break"></i></Button>
                </Row>
              {/if}
            {/snippet}
          </Table>
        </div>
      </Card>

      <Card title={role === 'data' ? 'Shares' : 'Instance volumes'}>
        {#snippet actions()}
          {#if role === 'data'}
            <Muted>{shares.loaded ? `${shareRows.length} share${shareRows.length === 1 ? '' : 's'}${shareBytes ? ` · ${sizeTxt(shareBytes)}` : ''}` : 'Loading…'}</Muted>
            <Button variant="ghost" size="sm" tooltip={'Show the shares in this pool'} onclick={() => go(`${P.shares}?pool=${pool}`)}>Shares<i class="ph ph-caret-right"></i></Button>
          {:else}
            <Muted>{cts.loaded ? `${volumes.length} volume${volumes.length === 1 ? '' : 's'}${volBytes ? ` · ${sizeTxt(volBytes)}` : ''} · Incus pool "default"` : 'Loading…'}</Muted>
            <Button variant="ghost" size="sm" tooltip={'Show the shares in this pool'} onclick={() => go(`${P.shares}?pool=${pool}`)}>Shares<i class="ph ph-caret-right"></i></Button>
            <Button variant="ghost" size="sm" tooltip={'Show the instances'} onclick={() => go(P.instances)}>Instances<i class="ph ph-caret-right"></i></Button>
          {/if}
        {/snippet}
      </Card>
     </Stack>
    {/if}
  </PageState>
{/if}
