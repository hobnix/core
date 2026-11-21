<script>
  import { tip } from '../ui/tooltip.svelte.js';
  import { poll, rows, refresh } from '../data.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import { ErrorNote } from '../ui/index.js';
  import { takeSelection } from '../select.svelte.js';
  import { openCreate, openPlan, ui, track, showTab, tasks } from '../ui.svelte.js';
  import { start, get } from '../api.js';
  import InstallDialog from '../forms/ops/InstallDialog.svelte';
  import RemoveApp from '../forms/ops/RemoveApp.svelte';
  import AppServices from '../forms/ops/AppServices.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import { TextInput, Switch, Dialog, Muted } from '../ui/index.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import StageBadge from '../ui/StageBadge.svelte';
  import Chip from '../ui/Chip.svelte';
  import { parseStates, parseHealth, stageActions } from './states.js';
  import { link } from './instances/ct.js';
  import { appAction } from './apps.js';

  const list = poll('/api/sys/recipes/list', 30000);
  // the lifecycle stage and flags of every app (ADR 0027): name, kind, stage, flags, repo, available, installed, instances, title
  const stateList = poll('/api/sys/apps/list', 30000);
  const stageOf = $derived(parseStates(rows(stateList)));
  // the declared health check of the apps that have one: name, healthy|unhealthy|stopped. Follows the event stream (topic apps-health); the
  // timer is only the fallback while the stream is down
  const healthList = poll('/api/sys/apps/health', 30000);
  const healthOf = $derived(parseHealth(rows(healthList)));
  // name, available version, applied version (- = not known), state: current | update | unknown
  const vers = poll('/api/sys/recipes/versions', 30000);
  const verOf = $derived(new Map(rows(vers).map((r) => [r[0], { avail: r[1], applied: r[2], vstate: r[3] }])));
  // the app's own version and its update policy, one row per installed instance: name, instance, package, offered, running (- = not known), policy, state
  const appVers = poll('/api/sys/apps/versions', 30000);
  // keyed by instance: a second instance of one recipe has its own row
  const appVerOf = $derived(new Map(rows(appVers).map((r) => [r[1], { name: r[0], pkg: r[2], offered: r[3], running: r[4], policy: r[5], astate: r[6] }])));
  // services app: name, container, ... the containers that have a described service
  const svc = poll('/api/sys/services/app', 30000);
  const withService = $derived(new Set(rows(svc).map((r) => r[1])));
  const hasService = (a) => !!a.cts && a.cts.split(',').some((c) => withService.has(c));

  // name, description, containers (comma separated, - for none), state: installed | partly | not installed | parked | unknown
  const apps = $derived(rows(list).map((r) => {
    const v = verOf.get(r[0]) ?? { avail: '-', applied: '-', vstate: 'unknown' };
    const avs = (r[2] === '-' ? [] : r[2].split(',')).map((c) => ({ inst: c, ...appVerOf.get(c) })).filter((x) => x.name === r[0]);
    return { name: r[0], desc: r[1], cts: r[2] === '-' ? '' : r[2], state: r[3], ...v, avs, ver: v.applied !== '-' ? v.applied : v.avail !== '-' ? v.avail : '' };
  }));
  const installed = $derived(apps.filter((a) => a.state === 'installed').length);

  // the icons the design gives the known recipes; anything else is a package
  const icons = {
    arr: 'film-slate', authentik: 'key', bulwark: 'envelope-open', cloudflared: 'cloud', docker: 'shipping-container', docs: 'book-open',
    homeassistant: 'house-line', domain: 'identification-badge', immich: 'images', jellyfin: 'film-strip', 'matrix-hook': 'chat-circle-text',
    monitoring: 'chart-line', ntfy: 'bell', paperclip: 'robot', pelican: 'game-controller', qbittorrent: 'download-simple', sabnzbd: 'download', seerr: 'magnifying-glass',
    stalwart: 'envelope-simple', sunshine: 'television', synapse: 'chat-circle', tdarr: 'swap', 'upload-storage': 'cloud-arrow-up', 'uptime-kuma': 'heartbeat', zoraxy: 'arrows-split',
  };
  const tag = (a) => (a.state === 'installed' ? (a.cts ? `in ${a.cts.split(',').join(', ')}` : 'installed') : a.state);

  // Start/Stop of one instance of an app (the plan of the instance, like the Instances page); the container docker is not stopped from here
  const flipCt = (c, running) => openPlan('ct', [c, running ? 'stop' : 'start'], `${running ? 'Stop' : 'Start'} ${c}`);
  const run = (a) => (a.state === 'installed' ? openPlan('recipes', [a.name, 'run'], `${a.name}`) : openCreate(InstallDialog, { pkg: a.name }));
  // Remove one instance of an app: the plan, the data question, the typed name (step 11)
  const removeCt = (c) => openCreate(RemoveApp, { app: c, ondone: () => refresh(['/api/sys/apps/list', '/api/sys/recipes/list']) });
  // the form only writes the description: read the services and the plan again now, so the Services page's Apply count is right at once
  const services = (a) => openCreate(AppServices, { app: a.name, cts: a.cts ? a.cts.split(',') : [], ondone: () => refresh(['/api/sys/services/app', '/api/sys/services/list', '/api/sys/services/routes']) });

  // what a row is doing, from its jobs (also one started in a terminal), and the newest failed job of the row
  const instOf = (a) => (a.cts ? a.cts.split(',') : []);
  const doing = (a) => (rowstate.pending('recipes', [a.name, 'run']) ? (a.state === 'installed' ? 'Updating…' : 'Installing…')
    : instOf(a).some((c) => rowstate.pending('apps', ['remove', c])) ? 'Removing…'
    : instOf(a).some((c) => rowstate.pending('ct', [c, 'start'])) ? 'Starting…'
    : instOf(a).some((c) => rowstate.pending('ct', [c, 'stop'])) ? 'Stopping…' : '');
  const failure = (a) => rowstate.failed('recipes', [a.name, 'run'])
    ?? instOf(a).map((c) => rowstate.failed('apps', ['remove', c]) ?? rowstate.failed('ct', [c, 'start']) ?? rowstate.failed('ct', [c, 'stop'])).find(Boolean) ?? null;

  let q = $state('');
  let show = $state('all');
  const shown = $derived(apps.filter((a) => (show === 'all' || (show === 'installed' ? a.state === 'installed' : a.state !== 'installed'))
    && (!q.trim() || (a.name + ' ' + a.desc).toLowerCase().includes(q.trim().toLowerCase()))));
  const columns = [
    { key: 'sel', label: '', sort: false, width: '44px' },
    { key: 'go', label: '', sort: false }, { key: 'name', label: 'App' }, { key: 'desc', label: 'What it does' },
    { key: 'ver', label: 'Version' }, { key: 'state', label: 'State' }, { key: 'tools', label: '', sort: false, align: 'right' },
  ];

  let copied = $state('');
  let hl = $state('');
  $effect(() => { const n = takeSelection('recipes'); if (n) hl = n; });
  $effect(() => { if (hl && apps.length) document.getElementById('app-' + hl)?.scrollIntoView({ block: 'center' }); });
  async function copy(name) {
    const text = `hs recipe ${name}`;
    try { await navigator.clipboard.writeText(text); }
    catch {
      // a page served over plain HTTP has no clipboard API: select the text in a hidden field instead
      const t = document.createElement('textarea');
      t.value = text; t.style.position = 'fixed'; t.style.opacity = '0';
      document.body.appendChild(t); t.select();
      try { document.execCommand('copy'); } catch { /* nothing more to try */ }
      t.remove();
    }
    copied = name;
    setTimeout(() => { if (copied === name) copied = ''; }, 1500);
  }

  // ═══ bulk selection ═══
  let selected = $state(new Set());
  const toggle = (name, checked) => { const s = new Set(selected); if (checked) s.add(name); else s.delete(name); selected = s; };
  const selectedApps = $derived(apps.filter((a) => selected.has(a.name)));
  const canInstall = $derived(selectedApps.some((a) => a.state !== 'installed'));
  const canUpdate = $derived(selectedApps.some((a) => a.state === 'installed'));
  let bulkBusy = $state(false);
  let bulkOpen = $state(null);           // { action, items } while the confirmation dialog is open
  let bulkSummary = $state([]);          // { name, ok, state, reason }
  let showSummary = $state(false);

  // wait until a job unit reaches a terminal state (the task follows the unit through the event stream), then return it ('ok' | 'failed' | ...)
  const awaitJob = (unit) => new Promise((done) => {
    const stop = $effect.root(() => {
      $effect(() => {
        const t = tasks.list.find((x) => x.unit === unit);
        if (t && t.state !== 'running') { done(t.state); queueMicrotask(() => stop()); }
      });
    });
  });

  // start one recipe as its own background job (install and update are both `hs sys recipes start <name> run`)
  const startOne = async (name) => {
    try {
      const r = await start('recipes', [name, 'run']);
      if (r.status === 'started' && r.unit) { track(r.unit, name); showTab('tasks'); return { unit: r.unit }; }
      return { ok: false, reason: r.reason || `could not start (${r.status})`, status: r.status };
    } catch (e) {
      return { ok: false, reason: e.message, status: 'error' };
    }
  };

  // run the selected items one job after another, then refresh and report
  const runBulk = async (action) => {
    const items = selectedApps.filter((a) => action === 'install' ? a.state !== 'installed' : a.state === 'installed');
    if (!items.length) return;
    bulkOpen = { action, items };
  };

  const confirmBulk = async () => {
    const { action, items } = bulkOpen;
    bulkOpen = null;
    bulkBusy = true;
    bulkSummary = [];
    try {
      for (const a of items) {
        const r = await startOne(a.name);
        if (r.unit) {
          const state = await awaitJob(r.unit);
          bulkSummary.push({ name: a.name, ok: state === 'ok', state });
        } else {
          bulkSummary.push({ name: a.name, ok: false, reason: r.reason, status: r.status });
        }
      }
      selected = new Set();
      await refresh(['/api/sys/recipes/list', '/api/sys/recipes/versions', '/api/sys/services/app']);
      showSummary = true;
    } finally {
      bulkBusy = false;
    }
  };

  const cancelBulk = () => { bulkOpen = null; };
  const dismissSummary = () => { showSummary = false; bulkSummary = []; };
  const failedCount = $derived(bulkSummary.filter((r) => !r.ok).length);
</script>

<PageHeader title="Apps" crumb="{ui.host} › Instances" sub={list.loaded && !list.error ? `${installed} of ${apps.length} installed · safe to run again` : 'One-command installers, safe to run again.'} />

<PageState loading={!list.loaded} error={list.error?.message} hasData={list.data != null} empty={list.loaded && !list.error && !apps.length}
           emptyIcon="package" emptyTitle="No recipes" emptyText="This server has no app recipes." retry={() => refresh(['/api/sys/recipes/list'])}>
  <div class="bar">
    {#each [['all', 'All'], ['installed', 'Installed'], ['todo', 'Not installed']] as [k, l]}
      <Button variant={show === k ? 'primary' : 'ghost'} size="sm" onclick={() => (show = k)}>{l}</Button>
    {/each}
    <div class="find"><TextInput bind:value={q} placeholder="Search apps" ariaLabel="Search apps" autocomplete="off" /></div>
  </div>

  {#if selected.size}
    <div class="bulk">
      <span class="bulk-count">{selected.size} selected</span>
      <Button need="app-manager" size="sm" variant={canInstall ? 'primary' : 'ghost'} disabled={!canInstall || bulkBusy} onclick={() => runBulk('install')}>Install selected</Button>
      <Button need="app-manager" size="sm" variant={canUpdate ? 'primary' : 'ghost'} disabled={!canUpdate || bulkBusy} onclick={() => runBulk('update')}>Update selected</Button>
      <Button variant="ghost" size="sm" disabled={bulkBusy} onclick={() => (selected = new Set())}>Clear selection</Button>
    </div>
  {/if}

  <div class="card tc">
    <Table id="apps" {columns} rows={shown} key="name" loading={!list.loaded} empty="No app matches.">
      {#snippet cell(a, col)}
        {@const on = a.state === 'installed'}
        {#if col.key === 'sel'}
          <Switch box checked={selected.has(a.name)} onchange={(c) => toggle(a.name, c)} label="Select {a.name}" />
        {:else if col.key === 'go'}
          {@const act = appAction(a)}
          <Button need="app-manager" variant={act.primary ? 'primary' : 'secondary'} size="sm" class="apps-go" disabled={a.state === 'parked'} tooltip={act.tip} onclick={() => run(a)}><i class="ph ph-{act.icon}"></i>{act.label}</Button>
        {:else if col.key === 'ver'}
          {#if a.applied !== '-' && (a.avail === '-' || a.avail === a.applied)}
            <span class="vr">{a.applied}</span>
          {:else if a.applied !== '-'}
            <span class="vr" use:tip={`Applied ${a.applied}, available ${a.avail}`}>{a.applied} <span class="vnew">→ {a.avail}</span></span>
          {:else if a.avail !== '-'}
            <span class="vr dim" use:tip={a.state === 'installed' ? 'Available version. The applied one is not known yet: it is recorded at the next successful run' : 'Available version'}>{a.avail}</span>
          {:else}
            <span class="vr dim">-</span>
          {/if}
          {#each a.avs as av (av.inst)}
            {#if av.running !== '-' || av.policy === 'pinned'}
              <span class="vr" use:tip={av.astate === 'update' ? `${av.inst}: running ${av.running}, the release offers ${av.offered}` : `${av.inst}: the version of the app itself, read on this server`}>
                {#if av.running !== '-'}{av.running}{#if av.pkg !== '-'} <span class="dim">(package {av.pkg})</span>{/if}{#if av.astate === 'update'} <span class="vnew">→ {av.offered}</span>{/if}{/if}
                {#if av.policy === 'pinned'}<Chip tone="info" title="Pinned: this app is never offered an update">pinned</Chip>{/if}
              </span>
            {/if}
          {/each}
        {:else if col.key === 'name'}
          <span id="app-{a.name}" class="nm" class:hl={hl === a.name}><i class="ph ph-{icons[a.name] ?? 'package'}" style="color:{on ? 'var(--accent-ink)' : 'var(--fg-3)'}"></i>{a.name}</span>
          {#if failure(a)}{@const f = failure(a)}<ErrorNote error={f.error} ondismiss={() => rowstate.dismiss(f.id)} />{/if}
        {:else if col.key === 'desc'}
          <span class="ds">{a.desc}</span>{#if a.cts}<div class="in">In {#each a.cts.split(',') as c, i}{i ? ', ' : ''}<a {...link('/instances', 'instances', c)}>{c}</a>{/each}</div>{/if}
        {:else if col.key === 'state'}
          {#if doing(a)}<Chip tone="info">{doing(a)}</Chip>{/if}
          {#if stageOf.get(a.name)}
            <StageBadge stage={stageOf.get(a.name).stage} flags={stageOf.get(a.name).flags.filter((f) => f !== 'unhealthy' || !healthOf.has(a.name))} />
          {:else}
            <StatusDot state={on ? 'ok' : a.state === 'partly' ? 'warn' : 'off'} label={a.state} />
          {/if}
          {#if healthOf.get(a.name)}
            <div class="hl-row"><StatusDot state={healthOf.get(a.name).dot} label={healthOf.get(a.name).word} /></div>
          {/if}
        {:else}
          {#each stageActions(stageOf.get(a.name)).instances ?? [] as c}
            {#if c !== 'docker'}
              {@const live = stageOf.get(a.name).stage === 'running' || !stageOf.get(a.name).flags.includes('stopped')}
              <Button need="app-manager" variant="ghost" class="btn-icon" icon={live ? 'stop' : 'play'} busy={rowstate.pending('ct', [c, 'stop']) || rowstate.pending('ct', [c, 'start'])} tooltip={live ? `Stop ${c}` : `Start ${c}`} aria-label="{live ? 'Stop' : 'Start'} {c}" onclick={() => flipCt(c, live)} />
            {/if}
          {/each}
          {#each stageActions(stageOf.get(a.name)).instances ?? [] as c}
            {#if c !== 'docker'}
              <Button need="app-manager" variant="ghost" class="btn-icon" icon="trash" busy={rowstate.pending('apps', ['remove', c])} tooltip={`Remove ${c}: keep or delete its data`} aria-label="Remove {c}" onclick={() => removeCt(c)} />
            {/if}
          {/each}
          <Button need="admin" variant="ghost" class="btn-icon" disabled={!hasService(a)} tooltip={hasService(a) ? 'Services: local and public access' : a.cts ? 'No service is described yet: Update the app to describe it' : 'Install the app first'} aria-label="Services of {a.name}" onclick={() => services(a)}><i class="ph ph-globe-hemisphere-west"></i></Button>
          <Button variant="ghost" class="btn-icon" icon={copied === a.name ? 'check' : 'terminal-window'} tooltip={copied === a.name ? 'Copied' : 'Copy the terminal command: hs recipe ' + a.name} aria-label="Copy hs recipe {a.name}" onclick={() => copy(a.name)} />
        {/if}
      {/snippet}
    </Table>
  </div>
</PageState>

{#if bulkOpen}
  <Dialog title="Bulk change" panel="dialog" width="460px" onclose={cancelBulk}>
    <div class="bulkd">
      <h3>{bulkOpen.action === 'install' ? 'Install the selected apps' : 'Update the selected apps'}</h3>
      <p>Each app gets its own background job and the jobs run one after another. The result appears under Jobs.</p>
      <ul class="bulk-list">
        {#each bulkOpen.items as a}<li>{a.name} <Muted>({a.state})</Muted></li>{/each}
      </ul>
      <div class="bulk-foot">
        <Button onclick={cancelBulk}>Cancel</Button>
        <Button need="app-manager" variant="primary" disabled={bulkBusy} onclick={confirmBulk}>Start {bulkOpen.items.length} job{bulkOpen.items.length === 1 ? '' : 's'}</Button>
      </div>
    </div>
  </Dialog>
{/if}

{#if showSummary}
  <Dialog title="Result" panel="dialog" width="460px" onclose={dismissSummary}>
    <div class="bulkd">
      <h3 class:{bad}={failedCount > 0}>{failedCount > 0 ? 'Some jobs failed' : 'All jobs finished'}</h3>
      <ul class="bulk-list">
        {#each bulkSummary as r}
          <li class:{bad}={!r.ok}>{r.name} <Muted>{r.ok ? 'finished' : (r.reason ?? ('state: ' + (r.state ?? 'failed')))}</Muted></li>
        {/each}
      </ul>
      <div class="bulk-foot">
        <Button variant="primary" onclick={dismissSummary}>Done</Button>
      </div>
    </div>
  </Dialog>
{/if}

<style>
  .bar { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }
  .find { margin-left: auto; max-width: 240px; }
  .nm { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; font-size: 13.5px; }
  .nm i { font-size: 18px; }
  .nm.hl { outline: 2px solid var(--accent); outline-offset: 3px; }
  .ds { font-size: 12.5px; color: var(--fg-3); }
  .in { font-size: 12px; color: var(--fg-2); }
  .hl-row { margin-top: 2px; }
  :global(.btn.apps-go) { min-width: 96px; }
  .vr { font: 500 12.5px var(--mono); }
  .vr.dim { color: var(--fg-3); }
  .vnew { color: var(--accent-ink); }
  .bulk { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin: 10px 0 6px; }
  .bulk-count { font: 500 12.5px var(--mono); color: var(--fg-2); }
  .bulkd { display: flex; flex-direction: column; gap: 12px; }
  .bulkd h3 { margin: 0 0 2px; font-size: 17px; font-weight: 600; letter-spacing: -0.02em; }
  .bulkd h3.bad { color: var(--bad-ink); }
  .bulkd p { margin: 0; font-size: 12.5px; color: var(--fg-3); }
  .bulk-list { margin: 0; padding: 0 0 0 20px; font-size: 13px; color: var(--fg); gap: 6px; display: flex; flex-direction: column; }
  .bulk-list li { display: flex; justify-content: space-between; gap: 10px; }
  .bulk-list li.bad { color: var(--bad-ink); }
  .bulk-foot { display: flex; gap: 8px; justify-content: flex-end; padding-top: 8px; border-top: 1px solid var(--line); }
  .bad { color: var(--bad-ink); }
</style>
