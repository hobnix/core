<script>
  import { P } from '../paths.js';
  import { tip } from '../ui/tooltip.svelte.js';
  // Instances: containers and VMs in one list. No quick look (owner decision 2026-11-23, as on Disks): the name and the "Open instance" button at the end of a row go to the page
  // of the instance (pages/instances/Instance.svelte) with its tabs Overview, Config, Network and Console; start/stop and restart are on the row. Every action opens a plan. Snapshots of an instance live on its page (Config tab);
  // the "in the backup" switch lives on Backup, this page only shows the badge.
  import { poll, rows, refresh } from '../data.svelte.js';
  import { takeSelection } from '../select.svelte.js';
  import { openPlan, openCreate } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import { route, go, url } from '../route.svelte.js';
  import CreateInstance from '../forms/instances/CreateInstance.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import { Icon, Chip, StatusDot, Card, Row, Stack, Muted } from '../ui/index.js';
  import { sizeToBytes } from '../format.js';
  import { ctIcon, isVm, isRunning, link, servicesOf } from './instances/ct.js';
  import { childrenOf } from './docker/apps.js';
  import { instanceModel, kindOf, word, dot, boots, spaced, dash } from './instances/model.svelte.js';
  import { instancePath } from './instances/path.js';

  const m = instanceModel();
  const dl = poll('/api/sys/docker/list', 30000);

  let open = $state((() => {
    try { const s = sessionStorage.getItem('instances:docker-apps'); return new Set(s ? JSON.parse(s) : []); } catch { return new Set(); }
  })());
  $effect(() => { try { sessionStorage.setItem('instances:docker-apps', JSON.stringify([...open])); } catch {} });
  // another page (Apps, Services, Network, Docker) names an instance to look at: its page opens
  $effect(() => { const n = takeSelection('instances'); if (n) go(instancePath(n)); });
  // /instances?view=snapshots (the old Snapshots page) opens the Config tab (snapshots) of the first instance
  let snapOpened = false;
  $effect(() => {
    if (route.query.view === 'snapshots' && !snapOpened && m.ctl.loaded && m.all.length) { snapOpened = true; go(instancePath(m.all[0].name, 'config')); }
  });

  const cts = $derived(m.all);
  const running = $derived(cts.filter(isRunning).length);
  const kids = $derived(childrenOf(rows(dl)));
  const services = $derived(m.services);

  const doing = m.doing;
  const failure = m.failure;
  const plan = (e, c, action) => {
    e.stopPropagation();
    // a stop can also keep the instance off at boot (`--autostart off` unsets boot.autostart)
    openPlan('ct', [c.name, action], `${action} ${c.name}`, action === 'stop' ? { option: { label: 'also keep it off at boot', args: ['--autostart', 'off'] } } : {});
  };
  const eligible = (c) => c.owner === 'docker' && (kids.get(c.name)?.length || 0) > 0;
  const toggleApps = (e, name) => {
    e.stopPropagation();
    const next = new Set(open);
    if (next.has(name)) next.delete(name); else next.add(name);
    open = next;
  };
  const pageLink = (e, name) => { e.stopPropagation(); if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(instancePath(name)); } };

  const columns = [
    { key: 'name', label: 'Name' }, { key: 'owner', label: 'Lock', width: '64px', value: (c) => c.owner }, { key: 'type', label: 'Type', value: kindOf, optional: true }, { key: 'state', label: 'State', value: (c) => word(c.state) },
    { key: 'address', label: 'Address' }, { key: 'boot', label: 'Starts at boot', optional: true, value: (c) => (boots(c) ? 'yes' : 'no') }, { key: 'ram', label: 'RAM', sort: 'num', optional: true, value: (c) => sizeToBytes(c.ram) },
    { key: 'cpu', label: 'CPU', sort: 'num', optional: true, value: (c) => Number(c.cpu) },
    { key: 'lastSnap', label: 'Last snapshot', optional: true }, { key: 'route', label: 'Route', optional: true, value: (c) => servicesOf(c, services).length },
    { key: 'act', label: '', sort: false, align: 'right', width: '1%' },
  ];
</script>

<PageHeader title="Instances" sub={cts.length ? `${running} of ${cts.length} running` : 'Containers and virtual machines.'}>
  {#snippet actions()}
    <Button need="app-manager" icon="arrows-clockwise" disabled={!running} busy={rowstate.pending('ct', ['all', 'update-all'])} busyLabel="Updating…" tooltip={'Snapshot, then update every running container'} onclick={() => openPlan('ct', ['all', 'update-all'], 'Update all')}>Update all</Button>
    <Button need="app-manager" variant="primary" icon="plus" tooltip={'Create a new instance (a container or VM)'} onclick={() => openCreate(CreateInstance)}>Create</Button>
  {/snippet}
</PageHeader>

<PageState loading={!m.ctl.loaded} error={m.ctl.error?.message} hasData={m.ctl.data != null} empty={m.ctl.loaded && !cts.length && !m.ctl.error}
           emptyIcon="cube" emptyTitle="No instances yet" emptyText="An instance is a container or a virtual machine. Create the first one, or set an app up from Apps."
           retry={() => refresh(['/api/sys/ct/list'])}>
  {#snippet emptyAction()}<Button need="app-manager" variant="primary" icon="plus" tooltip={'Create a new instance (a container or VM)'} onclick={() => openCreate(CreateInstance)}>Create</Button>{/snippet}
  <div style="position:relative">
    <Card style="padding:4px 8px;overflow-x:auto">
      <Table id="instances" {columns} rows={cts} key="name" compact loading={!m.ctl.loaded} empty="No instances."
             below={subRow} hasBelow={(c) => open.has(c.name) && eligible(c)}>
        {#snippet cell(c, col)}
          {#if col.key === 'name'}
            <Row gap="2" style="display:inline-flex"><Icon name={ctIcon(c)} /><a href={url(instancePath(c.name))} onclick={(e) => pageLink(e, c.name)}>{c.name}</a></Row>
            {#if eligible(c)} <Chip>{kids.get(c.name).length} apps</Chip>{/if}
            {#if eligible(c)}<Button variant="ghost" class="btn-icon" icon={open.has(c.name) ? 'caret-down' : 'caret-right'} label="{open.has(c.name) ? 'Collapse' : 'Expand'} apps of {c.name}" onclick={(e) => toggleApps(e, c.name)} />{/if}
          {:else if col.key === 'owner'}{#if c.owner}<span role="img" aria-label="Locked by {c.owner}" use:tip={`Locked by ${c.owner}: only hs ${c.owner} disable removes it`}><Icon name="lock" /></span>{/if}
          {:else if col.key === 'type'}<Muted>{kindOf(c)}</Muted>
          {:else if col.key === 'state'}{#if doing(c)}<Muted><Icon name="circle-notch" spin /> {doing(c)}…</Muted>{:else}<StatusDot state={dot(c.state)} label={word(c.state)} />{/if}{#if failure(c)} <span use:tip={failure(c).error.what}><Chip tone="bad">failed</Chip></span>{/if}
          {:else if col.key === 'address'}<code>{c.address}</code>
          {:else if col.key === 'boot'}<Muted>{boots(c) ? 'yes' : 'no'}</Muted>
          {:else if col.key === 'ram'}{spaced(c.ram)}
          {:else if col.key === 'cpu'}{c.cpu}
          {:else if col.key === 'lastSnap'}<Muted>{dash(c.lastSnap) || '–'}</Muted>
          {:else if col.key === 'route'}
            {@const s = servicesOf(c, services)}
            {#if s.length}<a {...link(P.services)}>{s[0].names && s[0].names !== '-' ? s[0].names.split(',')[0] : s[0].name}{s.length > 1 ? ` +${s.length - 1}` : ''}</a>{:else}<Muted>–</Muted>{/if}
          {:else}
            <Row gap="1" justify="end">
              <Button variant="ghost" class="btn-icon" icon="arrow-square-out" label="Open instance" tooltip={'Open instance'} onclick={() => go(instancePath(c.name))} />
              <Button need="app-manager" variant="ghost" class="btn-icon" icon={isRunning(c) ? 'stop' : 'play'} busy={m.busyOf(c, ['stop'], ['stop', '--autostart', 'off'], ['start'])} tooltip={isRunning(c) ? 'Stop' : 'Start'} label="{isRunning(c) ? 'Stop' : 'Start'} {c.name}" onclick={(e) => plan(e, c, isRunning(c) ? 'stop' : 'start')} />
              <Button need="app-manager" variant="ghost" class="btn-icon" icon="arrow-clockwise" busy={m.busyOf(c, ['restart'])} tooltip={'Restart'} label="Restart {c.name}" onclick={(e) => plan(e, c, 'restart')} />
            </Row>
          {/if}
        {/snippet}
        {#snippet subRow(c)}
          <Stack gap="2" style="padding:8px 12px">
            {#each kids.get(c.name) as r (r[0])}
              <Row gap="4" align="center">
                <Row gap="2" style="margin-left:16px;min-width:140px"><Icon name="corners-out" />{r[0]}</Row>
                <StatusDot state={dot(r[3])} label={r[3]} bare />
                <Muted style="min-width:80px">{r[4]}</Muted>
                <a {...link(P.docker, 'docker', r[0])}>open in Docker</a>
              </Row>
            {/each}
          </Stack>
        {/snippet}
      </Table>
    </Card>
  </div>
</PageState>
