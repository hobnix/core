<script>
  // Shares > Remote view: the shares of other servers this one uses (mounted read only) and the shares it gives to other servers.
  // Two tables from `hs sys remote list` (kind offer|mount; the rows come from the page, which also shows their count). The buttons that add
  // a row (Add remote share, Give access) are in the page header; the actions of a row are here. Remote shares are never in the pool, the
  // parity or the backup (docs/PLAN-remote-shares.md D1).
  import Table from '../../shell/Table.svelte';
  import { StatusDot, Card, Stack, Muted, Banner } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { openPlan, openCreate, jobRunning } from '../../ui.svelte.js';
  import { ctOf } from '../instances/ct.js';
  import RemoteAttach from '../../forms/ops/RemoteAttach.svelte';
  import RemoteAdd from '../../forms/ops/RemoteAdd.svelte';
  import RemoteGive from '../../forms/ops/RemoteGive.svelte';

  let { remote, items, onoffered } = $props();
  const list = poll('/api/sys/ct/list', 15000);
  const cts = $derived(rows(list).map(ctOf));
  const used = $derived(items.filter((r) => r.kind === 'mount'));
  const given = $derived(items.filter((r) => r.kind === 'offer'));
  const dot = (s) => (s === 'mounted' || s === 'given' || s === 'attached' ? 'ok' : 'warn');
  const cols = [{ key: 'peer', label: 'Server' }, { key: 'share', label: 'Share' }, { key: 'state', label: 'State' }, { key: 'actions', label: '', sort: false, align: 'right' }];
  const empty = (txt) => (remote.error ? 'Remote shares could not be read.' : txt);
</script>

<Banner tone="info">A remote share is a share of another server. It is not in this server’s pool, parity or backup.</Banner>

<Stack gap="3">
  <Card style="padding:12px 14px;gap:8px">
    <b>Shares I use from other servers</b>
    <Table id="remote-used" columns={cols} rows={used} compact loading={!remote.loaded} empty={empty('No shares from other servers in use.')}>
      {#snippet cell(r, col)}
        {#if col.key === 'peer'}{r.peer}
        {:else if col.key === 'share'}<Muted>{r.share}</Muted>
        {:else if col.key === 'state'}<StatusDot state={dot(r.state)} label={r.state} />
        {:else}<span style="white-space:nowrap">
          <Button need="admin" variant="ghost" size="sm" tooltip={`Give an instance the shares of ${r.peer}, or take them away`} onclick={() => openCreate(RemoteAttach, { peer: r.peer, instances: cts.map((c) => c.name) })}>Instance…</Button>
          <Button need="admin" variant="ghost" size="sm" tooltip={`Type a new code from ${r.peer}: a new password, the same row`} onclick={() => openCreate(RemoteAdd, { reconnect: r.peer })}>Reconnect…</Button>
          <Button need="admin" variant="ghost" size="sm" busy={jobRunning('peers', ['remove', r.peer, r.share])} tooltip={`Stop using ${r.share} of ${r.peer}`} onclick={() => openPlan('peers', ['remove', r.peer, r.share], 'Stop using ' + r.peer + ' / ' + r.share)}>Stop using…</Button>
        </span>{/if}
      {/snippet}
    </Table>
  </Card>
  <Card style="padding:12px 14px;gap:8px">
    <b>Shares I give to other servers</b>
    <Table id="remote-given" columns={cols} rows={given} compact loading={!remote.loaded} empty={empty('No shares given to other servers.')}>
      {#snippet cell(r, col)}
        {#if col.key === 'peer'}{r.peer}
        {:else if col.key === 'share'}<Muted>{r.share}</Muted>
        {:else if col.key === 'state'}<StatusDot state={dot(r.state)} label={r.state} />
        {:else}<span style="white-space:nowrap">
          <Button need="admin" variant="ghost" size="sm" tooltip={`Make a new code for ${r.peer}; the old password stops working`} onclick={() => openCreate(RemoteGive, { peer: r.peer, share: r.share, ondone: onoffered })}>New code…</Button>
          <Button need="admin" variant="ghost" size="sm" busy={jobRunning('peers', ['revoke', r.peer, r.share])} tooltip={`Take the access to ${r.share} away from ${r.peer}`} onclick={() => openPlan('peers', ['revoke', r.peer, r.share], 'Take back the access of ' + r.peer)}>Take back…</Button>
        </span>{/if}
      {/snippet}
    </Table>
  </Card>
</Stack>
