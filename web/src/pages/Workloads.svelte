<script>
  import { P, capabilityPath, dockerAppPagePath } from '../paths.js';
  import { tip } from '../ui/tooltip.svelte.js';
  // Apps & VMs: the one list of containers, VMs and Docker apps (docs/PLAN-workloads.md 3; the rows and filters are pages/workloads.js). The Docker apps sit under the
  // container they run in, open at first. No quick look: the name and the button at the end of a row go to the page of the object (pages/instances/Instance.svelte,
  // pages/docker/DockerApp.svelte). A row shows at most three buttons, a Docker app keeps its other actions in a menu. Every action opens a plan. The filters
  // (provider, type, search) are in the address. Snapshots of an instance live on its page (Config tab); the "in the backup" switch lives on Backup.
  import { poll, rows, refresh } from '../data.svelte.js';
  import { takeSelection, setSelection } from '../select.svelte.js';
  import { openPlan, openCreate, ui } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import { route, go, url, setQuery } from '../route.svelte.js';
  import CreateInstance from '../forms/instances/CreateInstance.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { menuFor } from '../shell/objectpage.js';
  import { Banner, Button, Card, Chip, Icon, Menu, Muted, Row, Segmented, StatusDot, TextInput } from '../ui/index.js';
  import { sizeToBytes } from '../format.js';
  import { ctIcon, isRunning, link, servicesOf } from './instances/ct.js';
  import { appOf, filesChip, applyOf, isActionable, headerActions } from './docker/apps.js';
  import { problems } from './docker/health.js';
  import { instanceModel, word, dot, boots, spaced, dash } from './instances/model.svelte.js';
  import { instancePath } from './instances/path.js';
  import { dockerPending, dockerFailed } from './instances/pending.js';
  import { PROVIDERS, TYPES, buildRows, filtersOf, isFiltered, filterRows, isOpen, shownKids, appsHidden } from './workloads.js';

  // an older server does not say which capabilities are on: then the Docker parts show
  const dockerOn = $derived(!Array.isArray(ui.features.capabilities) || ui.features.capabilities.includes('docker'));
  const m = instanceModel();
  const appsPoll = poll(() => (dockerOn ? '/api/sys/docker/apps' : ''), 30000);
  const statusPoll = poll(() => (dockerOn ? '/api/sys/docker/status' : ''), 15000);
  const healthPoll = poll(() => (dockerOn ? '/api/sys/docker/health' : ''), 30000);

  const cts = $derived(m.all);
  const apps = $derived(dockerOn ? rows(appsPoll).map(appOf).filter(Boolean) : []);
  const status = $derived(Object.fromEntries(rows(statusPoll).map((r) => [r[0], r[1]])));
  const off = $derived(dockerOn && !!status.state && status.state !== 'on');
  // Docker is on, but something it needs is missing (the share apps, its mount): said once at the top, with the command that fixes it
  const broken = $derived(dockerOn && status.state === 'on' ? problems(rows(healthPoll)) : []);
  // an old Docker link asks for the Docker apps while the capability is off
  const askedOff = $derived(off || (!dockerOn && route.query.provider === 'docker'));
  const services = $derived(m.services);
  const all = $derived(buildRows({ cts, apps, recipes: m.recipes }));
  const filters = $derived(filtersOf(route.query, { docker: dockerOn }));
  const shown = $derived(filterRows(all, filters));
  const loaded = $derived(m.ctl.loaded && (!dockerOn || appsPoll.loaded));
  const setFilter = (patch) => setQuery(patch, { replace: true });

  const running = $derived(cts.filter(isRunning).length);
  const appsRunning = $derived(apps.filter((a) => a.state === 'running').length);
  const updatingAll = $derived(rowstate.pending('ct', ['all', 'update-all']));
  const sub = $derived.by(() => {
    const parts = [];
    if (cts.length) parts.push(`${running} of ${cts.length} instances running`);
    if (apps.length) parts.push(`${appsRunning} of ${apps.length} Docker apps running`);
    if (updatingAll) parts.push('updating all containers…');
    return parts.join(' · ') || 'Containers, virtual machines and Docker apps.';
  });

  // which rows with apps under them are shut, for the browser session
  let closed = $state((() => {
    try { return new Set(JSON.parse(sessionStorage.getItem('apps:closed') ?? '[]')); } catch { return new Set(); }
  })());
  $effect(() => { try { sessionStorage.setItem('apps:closed', JSON.stringify([...closed])); } catch { /* private mode: no memory */ } });
  const toggle = (name) => {
    const next = new Set(closed);
    if (next.has(name)) next.delete(name); else next.add(name);
    closed = next;
  };

  // another page (the catalog, Services, Network, Backup, Search) names an instance or a Docker app to look at: its page opens
  $effect(() => { const n = takeSelection('instances'); if (n) go(instancePath(n)); });
  $effect(() => { const n = takeSelection('docker'); if (n) go(dockerAppPagePath(n)); });
  // /apps?view=snapshots (the old Snapshots page) opens the Config tab (snapshots) of the first instance
  let snapOpened = false;
  $effect(() => {
    if (route.query.view === 'snapshots' && !snapOpened && m.ctl.loaded && cts.length) { snapOpened = true; setQuery({ view: null }, { replace: true }); go(instancePath(cts[0].name, 'config')); }
  });

  const pathOf = (r) => (r.kind === 'docker' ? dockerAppPagePath(r.name) : instancePath(r.name));
  const pageLink = (e, r) => { if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(pathOf(r)); } };
  // a stop can also keep the instance off at boot (`--autostart off` unsets boot.autostart)
  const plan = (c, action) => openPlan('ct', [c.name, action], `${action} ${c.name}`, action === 'stop' ? { option: { label: 'also keep it off at boot', args: ['--autostart', 'off'] } } : {});

  const doing = (r) => (r.kind === 'docker' ? dockerPending(r.name, rowstate.pending) : m.doing(r.ct));
  const failure = (r) => (r.kind === 'instance' ? m.failure(r.ct) : doing(r) ? null : dockerFailed(r.name, rowstate.failed));

  const appDot = (s) => (s === 'running' ? 'ok' : s === 'partial' ? 'warn' : 'off');
  const portHref = (a, port) => (a.address && a.address !== '-' ? `http://${a.address}:${port}` : null);
  // the actions of a Docker app as the app page has them (apps.js headerActions: the first is the one shown on the row)
  const dockerActs = (a) => {
    const run = (action, title = `${action} ${a.name}`) => openPlan('docker-app', [a.name, action], title);
    return {
      apply: { label: 'Apply', icon: 'check-circle', busyLabel: 'Applying…', busy: rowstate.pending('docker-app', [a.name, 'recreate']), disabled: !applyOf(a).ok, reason: applyOf(a).ok ? 'Apply: docker compose up -d from the files on disk (no pull, no build)' : applyOf(a).reason, onclick: () => run('recreate', `apply ${a.name}`) },
      start: { label: 'Start', icon: 'play', busyLabel: 'Starting…', busy: rowstate.pending('docker-app', [a.name, 'start']), reason: 'Start', onclick: () => run('start') },
      stop: { label: 'Stop', icon: 'stop', busyLabel: 'Stopping…', busy: rowstate.pending('docker-app', [a.name, 'stop']), reason: 'Stop', onclick: () => run('stop') },
      restart: { label: 'Restart', icon: 'arrow-clockwise', busyLabel: 'Restarting…', busy: rowstate.pending('docker-app', [a.name, 'restart']), reason: 'Restart', onclick: () => run('restart') },
      pull: { label: 'Pull', icon: 'download-simple', busyLabel: 'Pulling…', busy: rowstate.pending('docker-app', [a.name, 'pull']), reason: 'Pull images and recreate', onclick: () => run('pull') },
      rebuild: { label: 'Rebuild', icon: 'arrows-clockwise', busyLabel: 'Rebuilding…', busy: rowstate.pending('docker-app', [a.name, 'rebuild']), reason: 'Rebuild', onclick: () => run('rebuild') },
      delete: { label: 'Delete…', icon: 'trash', busyLabel: 'Deleting…', busy: rowstate.pending('docker-app', [a.name, 'delete']), reason: 'Remove the containers; the folder in /opt/apps stays', onclick: () => run('delete') },
      deleteData: { label: 'Delete with data…', icon: 'trash', busyLabel: 'Deleting…', busy: rowstate.pending('docker-app', [a.name, 'delete', '--delete-data']), reason: 'Also delete the config and data (/opt/apps)', onclick: () => openPlan('docker-app', [a.name, 'delete', '--delete-data'], `delete ${a.name} and its data`) },
    };
  };
  const rowMenu = (acts, keys, a) => {
    const item = (k, extra = {}) => ({ label: acts[k].label, icon: acts[k].icon, need: 'app-manager', disabled: acts[k].disabled || acts[k].busy, reason: acts[k].busy ? acts[k].busyLabel : acts[k].reason, onclick: acts[k].onclick, ...extra });
    // destructive ones come last (D4); only a web-managed app can be deleted
    return menuFor([...keys.map((k) => item(k)), ...(a.managed === 'web' ? [{ sep: true }, item('delete', { danger: true }), item('deleteData', { danger: true })] : [])], ui.role);
  };

  const headMenu = $derived(menuFor([
    ...(dockerOn ? [{ label: 'Guided Docker app', icon: 'magic-wand', disabled: off, reason: 'Docker is off', onclick: () => go(P.dockerWizard) }] : []),
    { label: 'Update all', icon: 'arrows-clockwise', need: 'app-manager', disabled: !running || updatingAll, reason: updatingAll ? 'Updating…' : 'No instance is running', onclick: () => openPlan('ct', ['all', 'update-all'], 'Update all') },
  ], ui.role));

  const routesOf = (r) => (r.kind === 'instance' ? servicesOf(r.ct, services) : []);
  const columns = [
    { key: 'name', label: 'Name' },
    { key: 'provider', label: 'Provider', optional: true, value: (r) => PROVIDERS[r.provider] },
    { key: 'type', label: 'Type', optional: true, value: (r) => TYPES[r.type] },
    { key: 'state', label: 'State', value: (r) => word(r.kind === 'docker' ? r.app.state : r.ct.state) },
    { key: 'app', label: 'App', optional: true, value: (r) => r.apps.join(', ') },
    { key: 'address', label: 'Address' },
    { key: 'boot', label: 'Starts at boot', optional: true, value: (r) => (r.ct ? (boots(r.ct) ? 'yes' : 'no') : '') },
    { key: 'ram', label: 'RAM', sort: 'num', optional: true, value: (r) => (r.ct ? sizeToBytes(r.ct.ram) : '') },
    { key: 'cpu', label: 'CPU', sort: 'num', optional: true, value: (r) => (r.ct ? Number(r.ct.cpu) : '') },
    { key: 'lastSnap', label: 'Last snapshot', optional: true, value: (r) => r.ct?.lastSnap ?? '' },
    { key: 'route', label: 'Route', optional: true, value: (r) => (r.ct ? routesOf(r).length : '') },
    { key: 'act', label: '', sort: false, align: 'right', width: '1%' },
  ];
  const providerOptions = [{ value: '', label: 'All' }, ...Object.entries(PROVIDERS).map(([v, label]) => ({ value: v, label }))];
  const typeOptions = [{ value: '', label: 'All' }, { value: 'container', label: 'Containers' }, { value: 'vm', label: 'Virtual machines' }];
  const openRecipe = (e, name) => { if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); setSelection('recipes', name); go(P.apps); } };
  const retry = () => refresh(['/api/sys/ct/list', ...(dockerOn ? ['/api/sys/docker/apps'] : [])]);
</script>

<PageHeader title="Apps & VMs" {sub}>
  {#snippet actions()}
    <Button need="app-manager" variant="primary" icon="plus" tooltip={'Create a new instance (a container or VM)'} onclick={() => openCreate(CreateInstance)}>Create</Button>
    {#if dockerOn}<Button need="app-manager" icon="shipping-container" disabled={off} reason="Docker is off" tooltip={'Write a compose file for a new app in Docker'} onclick={() => go(P.dockerNew)}>New Docker app</Button>{/if}
    <Menu items={headMenu} label="More actions for Apps & VMs" />
  {/snippet}
</PageHeader>

{#if broken.length}
  <Banner tone="bad">
    Docker is on, but not complete: {broken.map((b) => b.reason).join(' ')}
    {#snippet action()}<Button size="sm" tooltip="Open the Docker settings" onclick={() => go(capabilityPath('docker'))}>Open Docker settings</Button>{/snippet}
  </Banner>
{/if}
{#if askedOff}
  <Banner tone="info">
    Docker is off, so no Docker app is listed. Turn Docker on under Settings, Capabilities, Docker.
    {#snippet action()}<Button size="sm" tooltip="Open the Docker settings" onclick={() => go(capabilityPath('docker'))}>Open Docker settings</Button>{/snippet}
  </Banner>
{/if}
{#if dockerOn && appsPoll.error}
  <Banner tone="warn">Could not read the Docker apps: {appsPoll.error.message}
    {#snippet action()}<Button size="sm" tooltip="Read the list again" onclick={retry}>Try again</Button>{/snippet}
  </Banner>
{/if}

<PageState loading={!m.ctl.loaded} error={m.ctl.error?.message} hasData={m.ctl.data != null} empty={loaded && !all.length && !m.ctl.error && !appsPoll.error}
           emptyIcon="cube" emptyTitle="Nothing runs here yet" emptyText="An instance is a container or a virtual machine. Create the first one, or set an app up from the app catalog."
           {retry}>
  {#snippet emptyAction()}<Button need="app-manager" variant="primary" icon="plus" tooltip={'Create a new instance (a container or VM)'} onclick={() => openCreate(CreateInstance)}>Create</Button>{/snippet}
  <Row gap="3" wrap align="center">
    {#if dockerOn}<Segmented label="Provider" options={providerOptions} value={filters.provider} onchange={(v) => setFilter({ provider: v })} />{/if}
    <Segmented label="Type" options={typeOptions} value={filters.type} onchange={(v) => setFilter({ type: v })} />
    <TextInput value={filters.q} placeholder="Name, app, address or image" ariaLabel="Search apps and VMs" autocomplete="off" spellcheck={false} style="max-width:260px"
               oninput={(e) => setFilter({ q: e.currentTarget.value })} />
    {#if isFiltered(filters)}<Button variant="ghost" size="sm" tooltip="Show everything again" onclick={() => setFilter({ provider: null, type: null, q: null })}>Clear filters</Button>{/if}
  </Row>
  <div style="position:relative">
    <Card style="padding:4px 8px;overflow-x:auto">
      <Table id="workloads" {columns} rows={shown} key="id" compact loading={!loaded} empty={isFiltered(filters) ? 'Nothing matches the filters.' : 'No apps or VMs.'}
             kids={(r) => shownKids(r, closed)} rowClass={(r) => (r.context ? 'dimmed' : '')}>
        {#snippet cell(r, col)}
          {@const a = r.app}
          {@const c = r.ct}
          {#if col.key === 'name'}
            <Row gap="2" wrap align="center" style="display:inline-flex">
              {#if r.kids.length && !r.context}
                <Button variant="ghost" class="btn-icon" icon={isOpen(r, closed) ? 'caret-down' : 'caret-right'} label="{isOpen(r, closed) ? 'Collapse' : 'Expand'} apps of {r.name}" aria-expanded={isOpen(r, closed)} onclick={() => toggle(r.name)} />
              {/if}
              <Icon name={a ? 'corners-out' : ctIcon(c)} />
              <a href={url(pathOf(r))} use:tip={r.images} onclick={(e) => pageLink(e, r)}>{r.name}</a>
              {#if c?.owner}<span role="img" aria-label="Locked by {c.owner}" use:tip={`Locked by ${c.owner}: only hs ${c.owner} disable removes it`}><Icon name="lock" /></span>{/if}
              {#if a && filesChip(a)}{@const f = filesChip(a)}<Chip tone={f.tone} title={f.tip}>{f.text}</Chip>{/if}
              {#if r.total}<Chip>{r.total} {r.total === 1 ? 'app' : 'apps'}</Chip>{/if}
              {#if appsHidden(r, dockerOn)}<Muted>Its apps show once it runs.</Muted>{/if}
            </Row>
          {:else if col.key === 'provider'}<Muted>{PROVIDERS[r.provider]}</Muted>
          {:else if col.key === 'type'}<Muted>{TYPES[r.type]}</Muted>
          {:else if col.key === 'state'}
            {#if doing(r)}<Muted><Icon name="circle-notch" spin /> {doing(r)}…</Muted>
            {:else if a}
              <StatusDot state={appDot(a.state)} label={word(a.state)} />
              {#if a.running === '0/0'}<span use:tip={'No containers yet: save applies when the app is started or pulled'}><Muted>–</Muted></span>{:else}<Muted>{a.running}</Muted>{/if}
            {:else}<StatusDot state={dot(c.state)} label={word(c.state)} />{/if}
            {#if failure(r)} <span use:tip={failure(r).error.what}><Chip tone="bad">failed</Chip></span>{/if}
          {:else if col.key === 'app'}
            {#each r.apps as name, i (name)}{#if i > 0}, {/if}<a href={url(P.apps)} use:tip={'Set up by this recipe: open it in the app catalog'} onclick={(e) => openRecipe(e, name)}>{name}</a>{:else}<Muted>–</Muted>{/each}
          {:else if col.key === 'address'}
            {#if a}
              {#if r.address}<code>{r.address}</code>{/if}
              {#each r.ports as p, i (p)}{#if i > 0}, {:else}{' '}{/if}{#if portHref(a, p)}<a href={portHref(a, p)} target="_blank" rel="noopener">{p}</a>{:else}{p}{/if}{/each}
              {#if !r.address && !r.ports.length}<Muted>–</Muted>{/if}
            {:else}<code>{c.address}</code>{/if}
          {:else if col.key === 'boot'}{#if c}<Muted>{boots(c) ? 'yes' : 'no'}</Muted>{/if}
          {:else if col.key === 'ram'}{#if c}{spaced(c.ram)}{/if}
          {:else if col.key === 'cpu'}{#if c}{c.cpu}{/if}
          {:else if col.key === 'lastSnap'}{#if c}<Muted>{dash(c.lastSnap) || '–'}</Muted>{/if}
          {:else if col.key === 'route'}
            {#if c}
              {@const s = routesOf(r)}
              {#if s.length}<a {...link(P.services)}>{s[0].names && s[0].names !== '-' ? s[0].names.split(',')[0] : s[0].name}{s.length > 1 ? ` +${s.length - 1}` : ''}</a>{:else}<Muted>–</Muted>{/if}
            {/if}
          {:else if a}
            <Row gap="1" justify="end" align="center">
              <Button variant="ghost" class="btn-icon" icon="arrow-square-out" label="Open app" tooltip={'Open app'} onclick={() => go(pathOf(r))} />
              {#if isActionable(a)}
                {@const acts = dockerActs(a)}
                {@const keys = headerActions(a)}
                {@const first = acts[keys[0]]}
                <Button need="app-manager" variant="ghost" class="btn-icon" icon={first.icon} busy={first.busy} disabled={first.disabled} label="{first.label} {r.name}" tooltip={first.reason} onclick={first.onclick} />
                <Menu items={rowMenu(acts, keys.slice(1), a)} label="More actions for {r.name}" />
              {/if}
            </Row>
          {:else}
            <Row gap="1" justify="end">
              <Button variant="ghost" class="btn-icon" icon="arrow-square-out" label="Open instance" tooltip={'Open instance'} onclick={() => go(pathOf(r))} />
              <Button need="app-manager" variant="ghost" class="btn-icon" icon={isRunning(c) ? 'stop' : 'play'} busy={m.busyOf(c, ['stop'], ['stop', '--autostart', 'off'], ['start'])} tooltip={isRunning(c) ? 'Stop' : 'Start'} label="{isRunning(c) ? 'Stop' : 'Start'} {c.name}" onclick={() => plan(c, isRunning(c) ? 'stop' : 'start')} />
              <Button need="app-manager" variant="ghost" class="btn-icon" icon="arrow-clockwise" busy={m.busyOf(c, ['restart'])} tooltip={'Restart'} label="Restart {c.name}" onclick={() => plan(c, 'restart')} />
            </Row>
          {/if}
        {/snippet}
      </Table>
    </Card>
  </div>
</PageState>
