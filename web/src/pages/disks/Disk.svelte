<script>
  // Storage > Disks > one disk: /storage/disks/<name>[/<tab>] (D6). The Object template (shell/ObjectPage.svelte) with the tabs Overview, SMART, Tests and Files (D3 a):
  //   Overview  the facts of the disk, what it is doing now, its pool and the pages it belongs to
  //   SMART     the counters and the history of pending sectors and temperature (read from the state database; the page reads nothing it does not show)
  //   Tests     the self-tests on record and the one that is running
  //   Files     a data disk of a SnapRAID pool can be browsed and its files moved from here; for every other disk this says where its files are
  // Actions (D4): one primary and one secondary in the header, the rest in the More menu, Format only in the danger section. A viewer sees all of it read-only.
  import { onMount } from 'svelte';
  import { P, poolPath, diskPath } from '../../paths.js';
  import { route, go } from '../../route.svelte.js';
  import { objectOf, objects } from '../../objects.js';
  import { pools, loadPools } from '../../pools.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { filesLink } from '../../files/links.js';
  import { sleepText } from '../../disk-sleep.js';
  import ObjectPage from '../../shell/ObjectPage.svelte';
  import { Banner, Button, Card, Kv, Muted, Row, StatusDot } from '../../ui/index.js';
  import ErrorNote from '../../ui/ErrorNote.svelte';
  import AddDisks from '../../forms/storage/AddDisks.svelte';
  import WipeDisk from '../../forms/storage/WipeDisk.svelte';
  import OtherDisk from '../../forms/storage/OtherDisk.svelte';
  import DetachDisk from '../../forms/storage/DetachDisk.svelte';
  import RecoverDisk from '../../forms/storage/RecoverDisk.svelte';
  import { diskPool, sizeTxt, hoursTxt, dateOf } from '../storage/pool.js';
  import { diskModel } from './model.svelte.js';

  let { deck } = $props();

  const at = $derived(objectOf(route.path));
  const name = $derived(at?.kind === 'disk' ? at.id : '');
  const m = diskModel({ sel: () => name, detail: true });
  onMount(() => { loadPools(); });

  const locked = $derived(!!deck?.data?.locked);
  const lockTip = (t) => (locked ? 'The storage is locked' : t);
  const d = $derived(m.disk);
  const member = $derived(d ? m.memberOf(d) : '');
  const snapData = $derived(!!d && m.snapRole(d) && /data/.test(d.role) && !!member);
  const num = (v) => (v && v !== '-' ? v : '–');
  const fsText = (x) => (x.fs && x.fs !== '-' ? x.fs : '–');
  const running = $derived(m.running);

  const runTest = (kind) => openPlan('disk', [d.name, 'test', kind], `${kind === 'long' ? 'Long' : 'Short'} test of ${d.name}`);
  const addToPool = () => openCreate(AddDisks, { pool: pools.rows.some((p) => p.name === m.snapName) ? m.snapName : (pools.rows[0]?.name ?? ''), variant: 'empty', snap: m.snapPool });

  // one primary and at most one secondary (D4); the rest in the menu; Format in the danger section only
  const loose = $derived(!!d && m.isLoose(d));
  const menu = $derived.by(() => {
    if (!d) return [];
    const out = [];
    if (loose) {
      out.push({ label: 'Long test', icon: 'pulse', need: 'admin', disabled: !!running, reason: running ? 'A test is running in this disk' : '', onclick: () => runTest('long') });
      out.push({ label: 'Mount read-only…', icon: 'usb', need: 'admin', disabled: locked, reason: lockTip(''), onclick: () => openCreate(OtherDisk, {}) });
    }
    if (snapData) {
      out.push({ label: m.markOf[member] === 'detached' ? 'Attach…' : 'Detach…', icon: 'plugs', need: 'admin', disabled: locked, reason: lockTip(''), onclick: () => openCreate(DetachDisk, { pool: m.snapName, member }) });
      out.push({ label: 'Browse files', icon: 'folder-open', disabled: locked, reason: lockTip(''), onclick: () => go(filesLink({ left: `disk:${member}`, right: m.otherDisk(member) })) });
      out.push({ label: 'Move files…', icon: 'arrows-left-right', disabled: locked, reason: lockTip(''), onclick: () => go(filesLink({ left: `disk:${member}`, path: '/shares', right: m.otherDisk(member), rpath: '/shares' })) });
      out.push({ label: 'Recover…', icon: 'first-aid-kit', need: 'admin', disabled: locked, reason: lockTip(''), onclick: () => openCreate(RecoverDisk, { pool: m.snapName, member, members: m.dataMembers(m.snapName) }) });
    }
    return out;
  });
  const danger = $derived(loose ? [{
    label: 'Format…', text: 'Erases this disk so it can be added to a pool. Everything on it is lost; the form asks for the disk’s name.', need: 'admin', disabled: locked, reason: lockTip(''),
    onclick: () => openCreate(WipeDisk, { disk: d.name, model: m.modelOf(d), size: d.size }),
  }] : []);
  const links = $derived.by(() => {
    if (!d) return [];
    const p = diskPool(d.role);
    return [
      ...(p ? [{ kind: 'Pool', name: p === 'bulk' && m.snapName ? m.snapName : p, href: poolPath(p === 'bulk' && m.snapName ? m.snapName : p), note: m.roleText(d) }] : []),
      { kind: 'Pages', name: 'Health', href: P.health }, { kind: 'Pages', name: 'Encryption', href: P.encryption },
    ];
  });
  const jobs = $derived((r) => !!d && m.namesOf(d).some((n) => n && (r.description ?? '').includes(n)));
  const tabs = objects.disk.tabs;
</script>

<ObjectPage crumb="Storage > Disks" title={name} chip={d ? m.poolText(d) : ''} state={d ? m.stateOf(d) : ''} stateLabel={d ? m.wordOf(d) : ''}
            {tabs} tab={at?.tab ?? ''} onpick={(id) => go(diskPath(name, id))} {menu} {danger} {links} {jobs} need="admin"
            loading={!m.mon.loaded} notFound={m.mon.loaded && !d} notFoundTitle="No such disk" backTo={P.disks} backLabel="All disks"
            notFoundText={`No disk called “${name}” is connected. It may have been removed or renamed; the list shows every disk the server has seen, also the missing ones.`}>
  {#snippet primary()}
    {#if d}
      {#if loose}
        <Button need="admin" variant="primary" disabled={locked} tooltip={lockTip('Pick this disk and see the plan')} onclick={addToPool}><i class="ph ph-plus"></i>Add to a pool…</Button>
        <Button need="admin" icon="pulse" busy={rowstate.pending('disk', [d.name, 'test', 'short'])} disabled={!!running} tooltip={running ? 'A test is running in this disk' : 'About two minutes; shows the plan first'} onclick={() => runTest('short')}>Short test</Button>
      {:else}
        <Button need="admin" variant="primary" icon="pulse" busy={rowstate.pending('disk', [d.name, 'test', 'short'])} disabled={!!running} tooltip={running ? 'A test is running in this disk' : 'About two minutes; shows the plan first'} onclick={() => runTest('short')}>Short test</Button>
        <Button need="admin" icon="pulse" busy={rowstate.pending('disk', [d.name, 'test', 'long'])} disabled={!!running} tooltip={running ? 'A test is running in this disk' : 'Reads the whole surface (hours); shows the plan first'} onclick={() => runTest('long')}>Long test</Button>
      {/if}
    {/if}
  {/snippet}
  {#snippet banners()}
    {#if d}
      {#if m.doingOf(d)}<Banner tone="info">{m.doingOf(d)}… a job is running on this disk; this page follows it.</Banner>
      {:else if m.failureOfDisk(d)}<ErrorNote error={m.failureOfDisk(d).error} ondismiss={() => rowstate.dismiss(m.failureOfDisk(d).id)} />{/if}
      {#if m.markOf[member]}<Banner tone="info">{m.markOf[member] === 'detached' ? `This disk is out of /${m.snapName} on purpose (detached). Attach it again when you are done.` : `Recovery is running or waiting for its finish; the disk is out of /${m.snapName} until then.`}</Banner>{/if}
      {#if locked}<Banner tone="warn">Storage is locked: the pool of this disk may be missing from the facts below until it is unlocked.</Banner>{/if}
    {/if}
  {/snippet}
  {#snippet children(t)}
    {#if d}
      {#if t === 'overview'}
        <Card title="Overview">
          <Kv items={[
            { k: 'Model', v: m.modelOf(d) }, { k: 'Serial', v: m.serialOf(d) }, { k: 'Size', v: sizeTxt(d.size) }, { k: 'Type', v: d.kind }, { k: 'Format', v: fsText(d) },
            { k: 'Pool', v: m.poolText(d) }, { k: 'Role', v: diskPool(d.role) ? m.roleText(d) : d.role },
            { k: 'Temperature', v: d.temp && d.temp !== '-' ? `${d.temp} °C` : '' }, { k: 'Power-on', v: hoursTxt(d.hours) },
            { k: 'Sleep', v: sleepText(d.sleep) ? `${sleepText(d.sleep)}${m.pw.disks[d.name]?.wakes ? `, woke ${m.pw.disks[d.name].wakes}x today` : ''}` : '' },
            { k: 'Free space', v: d.free && d.free !== '-' ? sizeTxt(Number(d.free)) : '' }, { k: 'First seen', v: m.rec?.first ? dateOf(m.rec.first) : '' },
          ]} />
          {#if m.verdicts[d.name]?.reason && m.verdicts[d.name].reason !== '-'}<p style="margin:12px 0 0">{m.verdicts[d.name].reason}</p>{/if}
        </Card>
      {:else if t === 'smart'}
        <Card title="SMART">
          <Kv items={[{ k: 'Pending sectors', v: num(d.pending) }, { k: 'Reallocated', v: num(d.realloc) }, { k: 'CRC errors', v: num(d.crc) }, { k: 'Verdict', v: m.verdictOf(d) }]} />
          <div style="margin-top:12px">
            {#if m.readings.length > 1}
              <Row gap="2" align="baseline" style="margin-bottom:6px"><b>Pending sectors</b><Muted>{m.spanTxt}</Muted></Row>
              <svg viewBox="0 0 400 60" preserveAspectRatio="none" role="img" aria-label="Pending sectors over time" style="width:100%;display:block;height:56px"><polygon points="0,60 {m.linePts} 400,60" fill="color-mix(in oklch, var(--accent) 22%, transparent)"></polygon><polyline points={m.linePts} fill="none" stroke="var(--accent)" stroke-width="1.5" vector-effect="non-scaling-stroke"></polyline></svg>
              <Row gap="2" align="baseline" style="margin:14px 0 6px"><b>Temperature</b><Muted>{m.spanTxt}{m.temps.length ? ` · now ${m.temps[m.temps.length - 1]} °C` : ''}</Muted></Row>
              <svg viewBox="0 0 400 40" preserveAspectRatio="none" role="img" aria-label="Temperature over time" style="width:100%;display:block;height:36px"><polyline points={m.tempPts} fill="none" stroke="var(--fg-3)" stroke-width="1.3" vector-effect="non-scaling-stroke"></polyline></svg>
            {:else}
              <Row gap="2" align="baseline" style="margin-bottom:6px"><b>History</b></Row>
              <Muted as="p">{!m.serial ? 'This disk is not in the inventory yet.' : m.hist.loaded ? 'Not enough readings yet.' : 'Loading…'}</Muted>
            {/if}
          </div>
        </Card>
      {:else if t === 'tests'}
        <Card title="Self-tests">
          <Row gap="2" align="baseline" style="margin-bottom:6px"><b>Newest first</b></Row>
          {#if running}<Row gap="3" style="padding:7px 0;border-bottom:1px solid var(--line)"><span style="width:50px;color:var(--fg-3);font:12px var(--mono)">now</span><span style="flex:1">{running.replace(/^A test is running:\s*/i, '')}</span><StatusDot state="info" label="running" /></Row>{/if}
          {#each m.tests as x}
            <Row gap="3" style="padding:7px 0;border-bottom:1px solid var(--line)"><span style="width:50px;color:var(--fg-3);font:12px var(--mono)">{x.kind}</span><span style="flex:1">{x.when}</span><StatusDot state={/^Completed without error/i.test(x.result) ? 'ok' : 'warn'} label={x.result} /></Row>
          {:else}
            {#if !running}<Muted as="p">{m.results.loaded ? 'No self-tests on record.' : 'Loading…'}</Muted>{/if}
          {/each}
        </Card>
      {:else}
        <Card title="Files">
          {#if snapData}
            <Muted as="p">This is a data disk of the pool {m.snapName}: its files can be looked at on their own, and moved to another data disk, in the file manager.</Muted>
            <Row gap="2" wrap style="margin-top:10px">
              <Button disabled={locked} tooltip={lockTip('Look at the files of this disk, next to another disk')} onclick={() => go(filesLink({ left: `disk:${member}`, right: m.otherDisk(member) }))}><i class="ph ph-folder-open"></i>Browse files</Button>
              <Button disabled={locked} tooltip={lockTip('Move files to another data disk in the file manager; their path stays')} onclick={() => go(filesLink({ left: `disk:${member}`, path: '/shares', right: m.otherDisk(member), rpath: '/shares' }))}><i class="ph ph-arrows-left-right"></i>Move files…</Button>
            </Row>
          {:else if loose}
            <Muted as="p">This disk is not part of a pool, so it holds no shared files. Mount it read-only from the menu to look at it or copy from it.</Muted>
          {:else}
            <Muted as="p">The files on this disk belong to its pool and are reached through the shares, not disk by disk.</Muted>
            <Row gap="2" wrap style="margin-top:10px"><Button tooltip={'Open the file manager'} onclick={() => go(P.files)}><i class="ph ph-folder-open"></i>File manager</Button></Row>
          {/if}
        </Card>
      {/if}
    {/if}
  {/snippet}
</ObjectPage>
