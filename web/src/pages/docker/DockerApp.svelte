<script>
  // One Docker app: /apps/docker-app/<name>[/<tab>]. The Object template (shell/ObjectPage.svelte) with the tabs Overview, Compose and Logs; which of them an app
  // has follows who manages it (apps.js pageTabs: unmanaged = Overview only, Compose only for a web-managed app), the same rules as its row in the list Apps & VMs.
  //   Overview  the facts, and the recipe in the app catalog when one set the app up
  //   Compose   the editor (AppEditPage.svelte, embedded); picking another tab with unsaved edits asks first
  //   Logs      the Compose log
  // Actions: one primary and one secondary in the header (apps.js headerActions), the rest in the More menu; Delete in the danger section. On the Compose tab the
  // editor has the primary button of the page (its Apply), so all app actions are in the menu there.
  import { P, capabilityPath, dockerAppPagePath, withQuery } from '../../paths.js';
  import { route, go } from '../../route.svelte.js';
  import { objectOf, objects } from '../../objects.js';
  import { poll, rows } from '../../data.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { openPlan, ui } from '../../ui.svelte.js';
  import { setSelection } from '../../select.svelte.js';
  import { roleOk, refusal } from '../../roles.js';
  import ObjectPage from '../../shell/ObjectPage.svelte';
  import ErrorNote from '../../ui/ErrorNote.svelte';
  import { Banner, Button, Card, Chip, Dialog, Kv, Muted, Row, Stack } from '../../ui/index.js';
  import { dockerPending, dockerFailed } from '../instances/pending.js';
  import { appOf, filesChip, applyOf, isActionable, pageTabs, headerActions } from './apps.js';
  import AppEditPage from './AppEditPage.svelte';
  import AppLogs from './AppLogs.svelte';

  const appsPoll = poll('/api/sys/docker/apps', 30000);
  const statusPoll = poll('/api/sys/docker/status', 15000);
  const recipesPoll = poll('/api/sys/recipes/list', 30000);

  const at = $derived(objectOf(route.path));
  const name = $derived(at?.kind === 'docker-app' ? at.id : '');
  const listed = $derived(rows(appsPoll).map(appOf).find((x) => x?.name === name) ?? null);
  // unsaved edits of the Compose tab (the editor says so). While there are any, an app that is missing from one answer of the list (around a save) keeps
  // its last row, so the editor stays mounted and keeps the text.
  let dirty = $state(false);
  let last = $state.raw(null);
  $effect(() => { if (listed) last = listed; });
  const a = $derived(listed ?? (dirty && last?.name === name ? last : null));
  const docker = $derived(Object.fromEntries(rows(statusPoll).map((r) => [r[0], r[1]])));
  const off = $derived(!!docker.state && docker.state !== 'on');
  const tabs = $derived(objects['docker-app'].tabs.filter((t) => pageTabs(a).includes(t.id)));
  // a tab this app does not have (or an unknown one) is Overview
  const tab = $derived(tabs.some((t) => t.id === at?.tab) ? at.tab : 'overview');
  const recipe = $derived(a?.managed === 'recipe' && rows(recipesPoll).some((r) => r[0] === a.name));

  const doing = $derived(a ? dockerPending(a.name, rowstate.pending) : '');
  const failure = $derived(a && !doing ? dockerFailed(a.name, rowstate.failed) : null);
  const dot = (s) => (s === 'running' ? 'ok' : s === 'partial' ? 'warn' : 'off');

  const plan = (action, title = `${action} ${name}`) => openPlan('docker-app', [name, action], title);
  const busy = (...args) => rowstate.pending('docker-app', [name, ...args]);
  const act = $derived({
    apply: { label: 'Apply', icon: 'check-circle', busyLabel: 'Applying…', busy: busy('recreate'), disabled: !!a && !applyOf(a).ok, reason: a && !applyOf(a).ok ? applyOf(a).reason : 'Recreate the app from the files on disk', onclick: () => plan('recreate', `apply ${name}`) },
    start: { label: 'Start', icon: 'play', busyLabel: 'Starting…', busy: busy('start'), reason: 'Start this app', onclick: () => plan('start') },
    stop: { label: 'Stop', icon: 'stop', busyLabel: 'Stopping…', busy: busy('stop'), reason: 'Stop this app', onclick: () => plan('stop') },
    restart: { label: 'Restart', icon: 'arrow-clockwise', busyLabel: 'Restarting…', busy: busy('restart'), reason: 'Restart this app', onclick: () => plan('restart') },
    pull: { label: 'Pull', icon: 'download-simple', busyLabel: 'Pulling…', busy: busy('pull'), reason: 'Pull images and recreate', onclick: () => plan('pull') },
    rebuild: { label: 'Rebuild', icon: 'arrow-clockwise', busyLabel: 'Rebuilding…', busy: busy('rebuild'), reason: 'Rebuild', onclick: () => plan('rebuild') },
  });
  const keys = $derived(headerActions(a));
  const shown = $derived(tab === 'compose' ? [] : keys.slice(0, 2));
  const menu = $derived(keys.filter((k) => !shown.includes(k)).map((k) => ({ label: act[k].label, icon: act[k].icon, need: 'app-manager', disabled: act[k].disabled || act[k].busy, reason: act[k].busy ? act[k].busyLabel : act[k].reason, onclick: act[k].onclick })));
  const deleting = $derived(!!a && (busy('delete') || busy('delete', '--delete-data')));
  const danger = $derived(a?.managed !== 'web' ? [] : [
    { label: 'Delete…', text: 'Removes the containers; the folder in /opt/apps stays, so the app can be started again.', need: 'app-manager', disabled: deleting, reason: 'Deleting…', onclick: () => plan('delete') },
    { label: 'Delete with data…', text: 'Removes the containers and also deletes the config and data (/opt/apps).', need: 'app-manager', disabled: deleting, reason: 'Deleting…', onclick: () => openPlan('docker-app', [name, 'delete', '--delete-data'], `delete ${name} and its data`) },
  ]);
  const jobs = $derived((r) => !!name && !!r.key && r.key.startsWith(`docker-app ${name} `));

  // another tab would drop unsaved edits of the Compose tab, so it asks first
  let leaving = $state('');      // the tab asked for while the editor has unsaved edits, '' = no question
  const show = (id) => go(dockerAppPagePath(name, id));
  const pick = (id) => { if (dirty && tab === 'compose' && id !== 'compose') leaving = id; else show(id); };
  const discard = () => { const id = leaving; leaving = ''; show(id); };

  const openRecipe = () => { setSelection('recipes', name); go(P.apps); };
</script>

<ObjectPage title={name} chip={a?.managed ?? ''} state={a ? (failure ? 'bad' : doing ? 'info' : dot(a.state)) : ''} stateLabel={failure ? 'failed' : doing ? `${doing.toLowerCase()}…` : a?.state ?? ''}
            {tabs} {tab} onpick={pick} {menu} {danger} {jobs} need="app-manager"
            loading={!appsPoll.loaded || (!a && !statusPoll.loaded)} error={appsPoll.error && !appsPoll.data ? appsPoll.error.message : ''} notFound={appsPoll.loaded && statusPoll.loaded && !a}
            notFoundTitle={off ? 'Docker is off' : 'No such Docker app'} backTo={withQuery(P.appsGroup, { provider: 'docker' })} backLabel="All Docker apps"
            notFoundText={off ? `Docker is off, so the app “${name}” cannot be shown. Turn Docker on under Settings, Capabilities, Docker.` : `No app called “${name}” is listed in Docker. It may have been deleted, or the docker container is stopped.`}>
  {#snippet primary()}
    {#each shown as k, i (k)}
      <Button need="app-manager" variant={i === 0 ? 'primary' : undefined} icon={act[k].icon} busy={act[k].busy} busyLabel={act[k].busyLabel} disabled={act[k].disabled} tooltip={act[k].reason} onclick={act[k].onclick}>{act[k].label}</Button>
    {/each}
  {/snippet}
  {#snippet banners()}
    {#if a}
      {#if doing}<Banner tone="info">{doing}… a job is running on this app; this page follows it.</Banner>
      {:else if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
      {#if !listed}<Banner tone="warn">The app is not in the Docker list right now. Your unsaved edits are still here.</Banner>{/if}
      {#if !isActionable(a)}<Banner tone="info">{filesChip(a).tip}.</Banner>{/if}
      {#if off}
        <Banner tone="warn">Docker is off.
          {#snippet action()}<Button size="sm" tooltip="Open the Docker settings" onclick={() => go(capabilityPath('docker'))}>Open Docker settings</Button>{/snippet}
        </Banner>
      {/if}
    {/if}
  {/snippet}
  {#snippet children(t)}
    {#if a}
      {#if t !== 'overview' && !roleOk(ui.role, 'app-manager')}
        <!-- the editor and the log (`docker logs`) need app-manager -->
        <Muted as="p">{refusal(ui.role, 'app-manager')}</Muted>
      {:else if t === 'compose'}
        <div>{#key name}<AppEditPage embedded={name} ondirty={(d) => { dirty = d; }} />{/key}</div>
      {:else if t === 'logs'}
        <Card title="Logs">{#key name}<AppLogs app={name} />{/key}</Card>
      {:else}
        <Card title="Overview">
          {#if filesChip(a)}{@const c = filesChip(a)}<Row gap="2" wrap><Chip tone={c.tone} title={c.tip}>{c.text}</Chip></Row>{/if}
          <Kv items={[{ k: 'State', v: doing ? `${doing}…` : a.state }, { k: 'Running', v: a.running }, { k: 'Project', v: a.project }, { k: 'Address', v: a.address }, { k: 'Ports', v: a.ports }, { k: 'Images', v: a.images }, { k: 'Managed', v: a.managed }, { k: 'Update', v: a.update }, ...(a.files !== '-' ? [{ k: 'Files', v: a.files }] : [])]} />
          {#if recipe}
            <Row gap="2" wrap align="center"><Muted>Set up by the recipe</Muted><Button variant="ghost" size="sm" tooltip="Open the recipe in the app catalog" onclick={openRecipe}>{a.name}</Button></Row>
          {/if}
        </Card>
      {/if}
    {/if}
  {/snippet}
</ObjectPage>

{#if leaving}
  <Dialog title="Unsaved changes" width="440px" onclose={() => { leaving = ''; }}>
    <div style="padding:var(--space-6)">
      <Stack gap="4">
        <strong>Unsaved changes</strong>
        <p style="margin:0">The compose and env text has edits that are not saved. Leaving this tab drops them.</p>
        <Row gap="2" wrap>
          <Button variant="primary" onclick={() => { leaving = ''; }}>Stay here</Button>
          <Button onclick={discard}>Leave and drop the edits</Button>
        </Row>
      </Stack>
    </div>
  </Dialog>
{/if}
