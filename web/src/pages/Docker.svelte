<script>
  import { P, capabilityPath, dockerAppPath, dockerAppPagePath } from '../paths.js';
  // The Docker page: the apps (compose projects) that run in the locked docker container. A row opens the quick look over the list (?sel=<app>); "Open page" in it
  // goes to the page of the app (docker/DockerApp.svelte).
  import { objects } from '../objects.js';
  import { poll, rows, refresh } from '../data.svelte.js';
  import { takeSelection } from '../select.svelte.js';
  import { selected, select, close } from '../selection.svelte.js';
  import { tip } from '../ui/tooltip.svelte.js';
  import { openPlan } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { dockerPending, dockerFailed } from './instances/pending.js';
  import { url, go } from '../route.svelte.js';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import Button from '../ui/Button.svelte';
  import QuickLook from '../ui/QuickLook.svelte';
  import Kv from '../ui/Kv.svelte';
  import Chip from '../ui/Chip.svelte';
  import StatusDot from '../ui/StatusDot.svelte';
  import EmptyState from '../ui/EmptyState.svelte';
  import Banner from '../ui/Banner.svelte';
  import AppLogs from './docker/AppLogs.svelte';
  import { appOf, filesChip, applyOf, isActionable, pageTabs } from './docker/apps.js';
  import { problems } from './docker/health.js';

  const appsPoll = poll('/api/sys/docker/apps', 30000);
  const statusPoll = poll('/api/sys/docker/status', 15000);
  const healthPoll = poll('/api/sys/docker/health', 30000);

  const selName = $derived(selected());
  let tab = $state('overview');
  // a search result asks for an app with setSelection (select.svelte.js): it becomes ?sel= here
  $effect(() => { const n = takeSelection('docker'); if (n) select(n); });
  $effect(() => { if (sel) tab = 'overview'; });

  const apps = $derived(rows(appsPoll).map(appOf).filter(Boolean));
  const status = $derived(Object.fromEntries(rows(statusPoll).map((r) => [r[0], r[1]])));
  // Docker is on, but something it needs is missing (the share apps, its mount): said once at the top, with the command that fixes it
  const broken = $derived(status.state === 'on' ? problems(rows(healthPoll)) : []);
  const sel = $derived(apps.find((a) => a.name === selName) ?? null);
  const runningCount = $derived(apps.filter((a) => a.state === 'running').length);

  const doing = (a) => dockerPending(a.name, rowstate.pending);
  const failure = (a) => (doing(a) ? null : dockerFailed(a.name, rowstate.failed));
  const dot = (s) => (s === 'running' ? 'ok' : s === 'partial' ? 'warn' : 'off');
  const portHref = (app, port) => (app.address && app.address !== '-' ? `http://${app.address}:${port}` : null);
  const applyPlan = (e, app) => { e.stopPropagation(); openPlan('docker-app', [app.name, 'recreate'], `apply ${app.name}`); };
  const plan = (e, app, action) => { e.stopPropagation(); openPlan('docker-app', [app.name, action], `${action} ${app.name}`); };

  const columns = [
    { key: 'name', label: 'Name' },
    { key: 'state', label: 'State' },
    { key: 'running', label: 'Running' },
    { key: 'ports', label: 'Ports' },
    { key: 'images', label: 'Images', optional: true },
    { key: 'managed', label: 'Managed' },
    { key: 'actions', label: '', sort: false, align: 'right' },
  ];
  const tabs = $derived(objects['docker-app'].tabs.filter((t) => pageTabs(sel).includes(t.id)));
</script>

<PageHeader title="Docker" sub={apps.length ? `${runningCount} of ${apps.length} apps running${status.address && status.address !== '-' ? ` · ${status.address}` : ''}` : 'Apps that run in the Docker container.'} />

{#if broken.length}
  <Banner tone="bad">
    Docker is on, but not complete: {broken.map((b) => b.reason).join(' ')}
    {#snippet action()}<a class="btn" href={url(capabilityPath('docker'))}>Open Docker settings</a>{/snippet}
  </Banner>
{/if}

<PageState loading={!appsPoll.loaded} error={appsPoll.error?.message} hasData={appsPoll.data != null}
           empty={appsPoll.loaded && !apps.length && !appsPoll.error} emptyIcon="shipping-container" emptyTitle="No apps yet" emptyText="No apps run in Docker yet."
           retry={() => refresh(['/api/sys/docker/apps'])}>
  {#if status.state !== 'on'}
    <EmptyState icon="shipping-container" title="Docker is off" tone="info" text="Turn Docker on under Settings, Capabilities, Docker.">
      {#snippet action()}<a class="btn" href={url(capabilityPath('docker'))}>Open Docker settings</a>{/snippet}
    </EmptyState>
  {:else}
    <div class="toolbar"><Button need="app-manager" size="sm" icon="plus" onclick={() => go(P.dockerNew)}>New app</Button> <Button size="sm" icon="magic-wand" onclick={() => go(P.dockerWizard)}>Guided</Button></div>
    <div style="position:relative">
        <div class="card" style="padding:0">
          <Table id="docker-apps" {columns} rows={apps} key="name" selected={sel?.name} onrow={(a) => select(a.name)} loading={!appsPoll.loaded} empty="No apps.">
            {#snippet cell(a, col)}
              {#if col.key === 'name'}{a.name}
                {#if filesChip(a)}{@const c = filesChip(a)} <Chip tone={c.tone} title={c.tip}>{c.text}</Chip>{/if}
              {:else if col.key === 'state'}{#if doing(a)}<span class="pend"><i class="ph ph-circle-notch spin"></i> {doing(a)}…</span>{:else}<StatusDot state={dot(a.state)} label={a.state} />{/if}{#if failure(a)}<span use:tip={failure(a).error.what}><Chip tone="bad">failed</Chip></span>{/if}
              {:else if col.key === 'running'}{#if a.running === '0/0'}<span use:tip={"No containers yet: save applies when the app is started or pulled"}>–</span>{:else}{a.running}{/if}
              {:else if col.key === 'ports'}
                {@const ports = a.ports === '-' ? [] : a.ports.split(',').filter(Boolean)}
                {#if ports.length}
                  {#each ports as p, i}{#if i > 0}, {/if}{#if portHref(a, p)}<a href={portHref(a, p)} target="_blank" rel="noopener" onclick={(e) => e.stopPropagation()}>{p}</a>{:else}{p}{/if}{/each}
                {:else}–{/if}
              {:else if col.key === 'images'}<span class="images" use:tip={a.images}>{a.images}</span>
              {:else if col.key === 'managed'}<Chip>{a.managed}</Chip>
              {:else if !isActionable(a)}
                <span class="acts"></span>
              {:else}
                <span class="acts">
                  {#if applyOf(a).show}
                    <Button need="app-manager" variant="ghost" size="sm" icon="check-circle" disabled={!applyOf(a).ok} busy={rowstate.pending('docker-app', [a.name, 'recreate'])} tooltip={applyOf(a).ok ? 'Apply: docker compose up -d from the files on disk (no pull, no build)' : applyOf(a).reason} aria-label="Apply {a.name}" onclick={(e) => applyPlan(e, a)}>Apply</Button>
                  {/if}
                  {#if a.state === 'exited' || a.state === 'created' || a.state === 'stopped'}
                    <Button need="app-manager" variant="ghost" class="btn-icon ib" icon="play" busy={rowstate.pending('docker-app', [a.name, 'start'])} tooltip="Start" aria-label="Start {a.name}" onclick={(e) => plan(e, a, 'start')} />
                  {:else if a.state === 'running' || a.state === 'partial'}
                    <Button need="app-manager" variant="ghost" class="btn-icon ib" icon="stop" busy={rowstate.pending('docker-app', [a.name, 'stop'])} tooltip="Stop" aria-label="Stop {a.name}" onclick={(e) => plan(e, a, 'stop')} />
                  {/if}
                  <Button need="app-manager" variant="ghost" class="btn-icon ib" icon="arrow-clockwise" busy={rowstate.pending('docker-app', [a.name, 'restart'])} tooltip="Restart" aria-label="Restart {a.name}" onclick={(e) => plan(e, a, 'restart')} />
                  <Button need="app-manager" variant="ghost" class="btn-icon ib" icon="download-simple" busy={rowstate.pending('docker-app', [a.name, 'pull'])} tooltip="Pull" aria-label="Pull {a.name}" onclick={(e) => plan(e, a, 'pull')} />
                </span>
              {/if}
            {/snippet}
          </Table>
        </div>
        {#if sel}
          <QuickLook href={dockerAppPagePath(sel.name)} title={sel.name} chip={sel.managed} state={dot(sel.state)} stateLabel={sel.state} rowKey={sel.name} {tabs} bind:tab onclose={close}>
            {#snippet children(t)}
              {#if failure(sel)}<ErrorNote error={failure(sel).error} ondismiss={() => rowstate.dismiss(failure(sel).id)} />{/if}
              {#if t === 'overview'}
                <Kv items={[{ k: 'State', v: sel.state }, { k: 'Running', v: sel.running }, { k: 'Project', v: sel.project }, { k: 'Address', v: sel.address }, { k: 'Ports', v: sel.ports }, { k: 'Images', v: sel.images }, { k: 'Managed', v: sel.managed }, { k: 'Update', v: sel.update }, ...(sel.files !== '-' ? [{ k: 'Files', v: sel.files }] : [])]} />
              {:else if t === 'compose'}
                <Button need="app-manager" icon="pencil-simple" onclick={() => go(dockerAppPath(sel.name))}>Open editor</Button>
              {:else}
                {#key sel.name}<AppLogs app={sel.name} />{/key}
              {/if}
            {/snippet}
            {#snippet actions()}
              {#if !isActionable(sel)}
                <Chip title={filesChip(sel).tip}>{filesChip(sel).text}</Chip>
              {:else}
              {#if applyOf(sel).show}
                <Button need="app-manager" size="sm" variant="primary" icon="check-circle" disabled={!applyOf(sel).ok} busy={rowstate.pending('docker-app', [sel.name, 'recreate'])} busyLabel="Applying…" tooltip={applyOf(sel).ok ? 'Recreate the app from the files on disk' : applyOf(sel).reason} onclick={(e) => applyPlan(e, sel)}>Apply</Button>
              {/if}
              {#if sel.state === 'exited' || sel.state === 'created' || sel.state === 'stopped'}
                <Button need="app-manager" size="sm" icon="play" busy={rowstate.pending('docker-app', [sel.name, 'start'])} busyLabel="Starting…" tooltip="Start this app" onclick={(e) => plan(e, sel, 'start')}>Start</Button>
              {:else if sel.state === 'running' || sel.state === 'partial'}
                <Button need="app-manager" size="sm" icon="stop" busy={rowstate.pending('docker-app', [sel.name, 'stop'])} busyLabel="Stopping…" tooltip="Stop this app" onclick={(e) => plan(e, sel, 'stop')}>Stop</Button>
              {/if}
              <Button need="app-manager" size="sm" icon="arrow-clockwise" busy={rowstate.pending('docker-app', [sel.name, 'restart'])} busyLabel="Restarting…" tooltip="Restart this app" onclick={(e) => plan(e, sel, 'restart')}>Restart</Button>
              <Button need="app-manager" size="sm" icon="download-simple" busy={rowstate.pending('docker-app', [sel.name, 'pull'])} busyLabel="Pulling…" tooltip="Pull images and recreate" onclick={(e) => plan(e, sel, 'pull')}>Pull</Button>
              {#if sel.managed === 'web'}
                <Button need="app-manager" size="sm" icon="arrow-clockwise" busy={rowstate.pending('docker-app', [sel.name, 'rebuild'])} busyLabel="Rebuilding…" tooltip="Rebuild" onclick={(e) => openPlan('docker-app', [sel.name, 'rebuild'], `rebuild ${sel.name}`)}>Rebuild</Button>
                <Button need="app-manager" size="sm" variant="danger" busy={rowstate.pending('docker-app', [sel.name, 'delete'])} busyLabel="Deleting…" tooltip="Remove the containers; the folder in /opt/apps stays, so the app can be started again" onclick={(e) => openPlan('docker-app', [sel.name, 'delete'], `delete ${sel.name}`)}>Delete</Button>
                <Button need="app-manager" size="sm" variant="danger" busy={rowstate.pending('docker-app', [sel.name, 'delete', '--delete-data'])} busyLabel="Deleting…" tooltip="Also delete the config and data (/opt/apps)" onclick={(e) => openPlan('docker-app', [sel.name, 'delete', '--delete-data'], `delete ${sel.name} and its data`)}>Delete with data</Button>
              {/if}
              {/if}
            {/snippet}
          </QuickLook>
        {:else if selName && appsPoll.loaded}
          <QuickLook title={selName} onclose={close}><p style="padding:12px 16px;margin:0;color:var(--fg-3)">No app called “{selName}” runs in Docker. It may have been deleted.</p></QuickLook>
        {/if}
    </div>
  {/if}
</PageState>

<style>
  .images { font-size: 12px; color: var(--fg-3); max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: inline-block; }
  .pend { color: var(--fg-3); }
  .acts { display: flex; justify-content: flex-end; gap: 2px; }
  .acts :global(.ib) { width: 28px; min-height: 28px; height: 28px; padding: 0; color: var(--fg-2); }
</style>
