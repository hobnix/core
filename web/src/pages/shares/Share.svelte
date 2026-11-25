<script>
  // Storage > Shares > one share: /storage/shares/<name>[/<tab>] (D6). The Object template (shell/ObjectPage.svelte) with the tabs Overview, Access and Snapshots (D3 a):
  //   Overview   the facts of the share, what it is doing now, who mounts it, the parity of a SnapRAID share
  //   Access     visibility in the network list and the permission entries (changes open a plan)
  //   Snapshots  the ZFS snapshots and the restore points of the nightly backup
  // Actions (D4): primary "Browse files"; ONE secondary that follows the tab (Overview: Rename, Access: Add access, Snapshots: Snapshot now or Restore from backup);
  // everything else in the More menu; Roll back and Delete only in the danger section. A viewer sees all of it read-only. An instance volume has only Overview
  // (it belongs to its instance).
  import { P, poolPath } from '../../paths.js';
  import { route, go } from '../../route.svelte.js';
  import { objectOf, objects } from '../../objects.js';
  import { loadPools } from '../../pools.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { filesLink } from '../../files/links.js';
  import { onMount } from 'svelte';
  import ObjectPage from '../../shell/ObjectPage.svelte';
  import { Banner, Button, Card, Kv, Muted, Row } from '../../ui/index.js';
  import ErrorNote from '../../ui/ErrorNote.svelte';
  import RenameShare from '../../forms/shares/RenameShare.svelte';
  import DeleteShare from '../../forms/shares/DeleteShare.svelte';
  import RestoreShare from '../../forms/shares/RestoreShare.svelte';
  import AddAccess from '../../forms/shares/AddAccess.svelte';
  import ShareParity from '../storage/ShareParity.svelte';
  import AccessTab from './AccessTab.svelte';
  import SnapshotsTab from './SnapshotsTab.svelte';
  import { sharePath } from './path.js';
  import { shareModel, dash, sizeText, mountedBy, editable } from './model.svelte.js';

  let { deck } = $props();

  const at = $derived(objectOf(route.path));
  const name = $derived(at?.kind === 'share' ? at.id : '');
  const tabId = $derived(at?.tab ?? '');
  const m = shareModel({ sel: () => name, detail: true, tab: () => tabId });
  onMount(() => { loadPools(); });

  const locked = $derived(!!deck?.data?.locked);
  const lockTip = (t) => (locked ? 'Storage is locked' : t);
  const s = $derived(m.share);
  const can = $derived(editable(s));
  const host = $derived(deck?.data?.host ?? 'homeserver');
  const doing = $derived(m.doing(s));
  const failure = $derived(m.failure(s));
  // the tab the page shows (an unknown or a tab the share has none of is Overview)
  const tab = $derived(can && ['access', 'snapshots'].includes(tabId) ? tabId : 'overview');
  const cacheOn = $derived(s?.cache === 'on');
  const hasCache = $derived(!!s && s.kind === 'shares' && (s.cache === 'on' || s.cache === 'off'));

  const toggle = (what, to) => openPlan('shares', [name, what, '--to', to], `${what === 'cache' ? 'Upload cache' : 'Automatic snapshots'} of ${name} ${to}`);
  const act = {
    rename: { label: 'Rename…', icon: 'pencil-simple', need: 'admin', disabled: locked, reason: lockTip('Change the name of this share'), onclick: () => openCreate(RenameShare, { share: name }) },
    access: { label: 'Add access…', icon: 'plus', need: 'admin', disabled: locked, reason: lockTip('Give a user or group access to this share'), onclick: () => openCreate(AddAccess, { share: name, taken: m.entries.map((e) => e.sid) }) },
    snapshot: { label: 'Snapshot now', icon: 'camera', need: 'admin', disabled: locked, reason: lockTip('Take a snapshot of this share now'), onclick: () => openPlan('shares', [name, 'snapshot'], `Snapshot ${name}`) },
    restore: { label: 'Restore from backup…', icon: 'arrow-counter-clockwise', need: 'admin', disabled: locked, reason: lockTip('Bring files back from the backup'), onclick: () => openCreate(RestoreShare, { share: name }) },
    auto: { label: `Automatic snapshots ${m.auto ? 'off' : 'on'}`, icon: 'clock-clockwise', need: 'admin', disabled: locked || !m.hist.loaded || !!m.hist.error, reason: lockTip('The snapshot list is not available'), onclick: () => toggle('auto', m.auto ? 'off' : 'on') },
    cache: { label: `Upload cache ${cacheOn ? 'off' : 'on'}`, icon: 'lightning', need: 'admin', disabled: locked, reason: lockTip(cacheOn ? 'Upload straight to the disks, not the SSD cache' : 'Upload to the SSD cache first, move to the disks later'), onclick: () => toggle('cache', cacheOn ? 'off' : 'on') },
    repair: { label: 'Repair', icon: 'wrench', need: 'admin', disabled: locked, reason: lockTip('Hand the files of this share to adminuser again'), onclick: () => openPlan('shares', [name, 'repair'], `Repair ${name}`) },
  };
  // the one secondary action of the header follows the tab
  const second = $derived(!can ? '' : tab === 'access' ? 'access' : tab === 'snapshots' ? (m.zfs ? 'snapshot' : 'restore') : 'rename');
  const menu = $derived.by(() => {
    if (!can) return [];
    const out = ['rename', 'access', ...(m.zfs ? ['snapshot', 'auto'] : []), 'restore', ...(hasCache ? ['cache'] : []), 'repair'].filter((k) => k !== second).map((k) => act[k]);
    return out;
  });
  const danger = $derived.by(() => {
    if (!can) return [];
    const out = [];
    if (m.zfs && m.newest) out.push({ label: 'Roll back…', text: `Puts the share back to the snapshot ${m.newest.name}. Everything changed since then is lost, and newer snapshots are deleted.`, need: 'admin', disabled: locked, reason: lockTip(''), onclick: () => openPlan('shares', [name, 'rollback', '--snapshot', m.newest.name], `Roll back ${name}`) });
    out.push({ label: 'Delete…', text: 'Removes the share. Its files stay as a renamed folder under Kept folders until someone removes them for good; the form asks for the share’s name.', need: 'admin', disabled: locked, reason: lockTip(''), onclick: () => openCreate(DeleteShare, { share: name }) });
    return out;
  });
  const links = $derived.by(() => {
    if (!s) return [];
    return [
      { kind: 'Pool', name: s.pool, href: poolPath(s.pool), note: dash(s.disks) },
      ...mountedBy(s).map((x) => ({ kind: 'Instance', name: x.text, href: `${P.instances}`, note: 'opens the instance list' })),
      ...(s.volume ? [] : [{ kind: 'Pages', name: 'Files', href: filesLink({ left: `share:${s.name}` }) }, ...(s.kind === 'other' ? [] : [{ kind: 'Pages', name: 'Backup', href: P.backup, note: s.backup === 'on' ? 'in the nightly backup' : 'not in the backup' }])]),
    ];
  });
  const re = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const jobs = $derived((r) => !!name && new RegExp(`(^|[^\\w-])${re(name)}($|[^\\w-])`).test(r.description ?? ''));
  const tabs = $derived(can ? objects.share.tabs : objects.share.tabs.slice(0, 1));
</script>

<ObjectPage title={name} chip={s ? (s.volume ? 'volume' : s.kind) : ''} state={s ? (failure ? 'bad' : doing ? 'info' : '') : ''} stateLabel={failure ? 'failed' : doing ? `${doing.toLowerCase()}…` : ''}
            {tabs} {tab} onpick={(id) => go(sharePath(name, id))} {menu} {danger} {links} {jobs} need="admin"
            loading={!m.overview.loaded} notFound={m.overview.loaded && !s} notFoundTitle="No such share" backTo={P.shares} backLabel="All shares"
            notFoundText={`No share called “${name}” exists. It may have been deleted or renamed; a deleted share’s folder is under Kept folders in the list.`}>
  {#snippet primary()}
    {#if s}
      {#if !s.volume}<Button need="admin" variant="primary" icon="folder-open" disabled={locked} tooltip={lockTip('Look at the files of this share in the file manager')} onclick={() => go(filesLink({ left: `share:${s.name}` }))}>Browse files</Button>{/if}
      {#if second}<Button need="admin" icon={act[second].icon} disabled={act[second].disabled} tooltip={act[second].disabled ? act[second].reason : ''} onclick={act[second].onclick}>{act[second].label}</Button>{/if}
    {/if}
  {/snippet}
  {#snippet banners()}
    {#if s}
      {#if doing}<Banner tone="info">{doing}… a job is running on this share; this page follows it.</Banner>
      {:else if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
      {#if locked}<Banner tone="warn">Storage is locked: the share may be missing from the facts below until it is unlocked.</Banner>{/if}
    {/if}
  {/snippet}
  {#snippet children(t)}
    {#if s}
      {#if t === 'access'}
        <AccessTab {m} {name} {locked} />
      {:else if t === 'snapshots'}
        <SnapshotsTab {m} />
      {:else}
        <Card title="Overview">
          <Kv items={[
            { k: 'Pool', v: s.pool }, { k: 'Size', v: sizeText(s.size) },
            { k: 'Network path', v: s.volume ? '' : `\\\\${host}\\${s.name}` }, { k: 'Folder', v: s.path }, { k: 'Where', v: dash(s.disks) },
            { k: 'Upload cache', v: dash(s.cache) },
            { k: 'Backup', v: s.volume || s.kind === 'other' ? '' : s.backup === 'on' ? 'in the nightly backup' : 'not in the backup' },
            { k: 'Sizes measured', v: m.measured },
          ]} />
          {#if s.volume}<Muted as="p">An instance volume belongs to its instance: change it there.</Muted>
          {:else if s.kind !== 'other'}<Muted as="p">Whether it is in the backup is set on <Button variant="ghost" size="sm" tooltip={'Open the Backup page'} onclick={() => go(P.backup)}>Backup</Button>.</Muted>{/if}
        </Card>
        <Card title="Mounted by">
          {#if mountedBy(s).length}
            <Row wrap gap="3">{#each mountedBy(s) as x}<Button size="sm" icon="cube" tooltip={`Open the instance list (${x.name})`} onclick={() => go(P.instances)}>{x.text}</Button>{/each}</Row>
          {:else}<Muted as="p">No instance mounts this {s.volume ? 'volume' : 'share'}.</Muted>{/if}
        </Card>
        {#if !s.volume && s.kind !== 'other' && /^data-/.test(s.disks)}<Card title="Parity"><ShareParity share={s.name} {locked} /></Card>{/if}
      {/if}
    {/if}
  {/snippet}
</ObjectPage>
