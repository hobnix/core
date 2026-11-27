<script>
  import { P, packagePath, appPath } from '../paths.js';
  // The Marketplace as a store (#474): cards of the apps first, add-ons (extensions, capabilities, blueprints) on their own tab, Installed and
  // Updates with a count, and the repositories, the package builder and the full package table on Advanced. A card opens the page of its package.
  // Reads: hs sys pkg market / states / cards / repos, services app / tiles (where Open goes). Changes: the install dialog (plan and typed
  // confirmation) and the plans of hs sys pkg (update, remove, fetch, repo-add, repo-remove) and parts (turn on/off); a package or repository that
  // came from a repository somebody added is red (the typed word is its name).
  import { poll, rows, refresh } from '../data.svelte.js';
  import { openPlan, openCreate, ui } from '../ui.svelte.js';
  import Chip from '../ui/Chip.svelte';
  import { rowstate } from '../rowstate.svelte.js';
  import { ErrorNote, AppTile, Grid, EmptyState } from '../ui/index.js';
  import { route, go } from '../route.svelte.js';
  import { link } from './instances/ct.js';
  import { start } from '../api.js';
  import RepoAdd from '../forms/ops/RepoAdd.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import PageTabs from '../ui/PageTabs.svelte';
  import Button from '../ui/Button.svelte';
  import { TextInput, Switch, Dialog, Muted } from '../ui/index.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import StageBadge from '../ui/StageBadge.svelte';
  import { parseStates, stageActions } from './states.js';
  import { parseCards, parseRepos, storeRows, rowsOf, tabsOf, TABS, categoriesOf, filterRows, categoryLabel, kindLabel, stateLine, cardActions, openHref, trustOf, testedText } from './market.js';
  import { runAction, busyOf, failureOf, needOf } from './marketrun.js';

  const market = poll('/api/sys/pkg/market', 30000);
  const repoList = poll('/api/sys/pkg/repos', 30000);
  // the lifecycle stage and flags of every package (ADR 0027); the table still reads the market for the versions and `core`
  const stateList = poll('/api/sys/pkg/states', 30000);
  // category, icon and tested date of each card; it changes with a fetch, so it follows the market topic
  const cardList = poll('/api/sys/pkg/cards', 120000, 'pkg-market');
  // where Open goes: the dashboard link of a service in one of the app's instances
  const svcApp = poll('/api/sys/services/app', 60000);
  const tiles = poll('/api/sys/services/tiles', 60000);
  const stageOf = $derived(parseStates(rows(stateList)));
  const PATHS = ['/api/sys/pkg/market', '/api/sys/pkg/repos', '/api/sys/pkg/states', '/api/sys/pkg/cards'];

  const store = $derived(storeRows(rows(market), parseCards(rows(cardList))));
  // name, kind, repository, available version, installed version, state, core, title (the Advanced table)
  const pkgs = $derived(store);
  const repos = $derived(parseRepos(rows(repoList)));
  const updates = $derived(pkgs.filter((p) => p.state === 'update').length);
  // the recipes that declare a [web.page]: Open goes to that page when no address of the app is known
  const withPage = $derived(new Set((ui.features.extensions ?? []).filter((e) => e.kind === 'recipe').map((e) => e.name)));
  const openOf = (p) => openHref(stageOf.get(p.name)?.instances, rows(svcApp), rows(tiles)) || (withPage.has(p.name) ? appPath(p.name) : '');

  const tabs = $derived(tabsOf(store));
  const tab = $derived(TABS.includes(route.query.tab) ? route.query.tab : route.query.tab === 'repos' ? 'advanced' : 'apps');   // ?tab=repos: the old Repositories tab
  const pick = (id) => go(id === 'apps' ? P.marketplace : `${P.marketplace}?tab=${id}`);

  let q = $state('');
  let category = $state('all');
  const inTab = $derived(rowsOf(tab, store));
  const cats = $derived(categoriesOf(inTab));
  $effect(() => { if (!cats.some((c) => c.value === category)) category = 'all'; });
  const cards = $derived(filterRows(inTab, { q, category }));
  const emptyText = { apps: 'No app is offered yet. Use Check for updates to read the repositories.', addons: 'No add-on is offered yet.',
    installed: 'Nothing is installed from a repository yet.', updates: 'Everything installed is up to date.' };

  const kindIcon = (k) => (k === 'extension' ? 'puzzle-piece' : 'package');
  const stateDot = (p) => (p.state === 'current' ? 'ok' : p.state === 'update' || p.state === 'waits' || p.state === 'orphan' ? 'warn' : 'off');
  const stateText = (p) => (p.state === 'new' ? 'not installed' : p.state === 'current' ? `installed ${p.inst}` : p.state === 'update' ? `${p.inst} → ${p.avail}` : p.state === 'waits' ? 'needs a newer Hobnix' : 'repository gone');
  const columns = [
    { key: 'sel', label: '', sort: false, width: '44px' },
    { key: 'go', label: '', sort: false }, { key: 'name', label: 'Package' }, { key: 'title', label: 'What it is' },
    { key: 'repo', label: 'Repository' }, { key: 'state', label: 'State' }, { key: 'tools', label: '', sort: false, align: 'right' },
  ];
  const repoColumns = [
    { key: 'name', label: 'Repository' }, { key: 'url', label: 'Address' }, { key: 'signed', label: 'Releases' }, { key: 'from', label: 'From' },
    { key: 'tools', label: '', sort: false, align: 'right' },
  ];

  const install = (p) => runAction('install', p);
  const update = (p) => runAction('update', p);
  const turn = (p, want) => runAction(want, p);
  const remove = (p) => runAction('remove', p);
  const fetchAll = () => openPlan('pkg', ['fetch'], 'Read the repositories again');
  const addRepo = () => openCreate(RepoAdd, {});
  const dropRepo = (r) => openPlan('pkg', ['repo-remove', r.name], `Remove the repository ${r.name}`);

  // a package that came from an added repository is red: installing it needs the name typed, which a bulk run cannot do per item
  const red = (p) => repos.find((r) => r.name === p.repo)?.from === 'added';

  // what a change did shows when its job ends (from the job events, also for a job started in a terminal); no timer
  const busyNow = $derived(['pkg', 'apps', 'parts'].some((a) => rowstate.pending(a)));
  let wasBusy = false;
  $effect(() => {
    if (wasBusy && !busyNow) refresh(PATHS);
    wasBusy = busyNow;
  });
  // the pending word of a package row, from its job
  const doing = (p) => (rowstate.pending('apps', ['install', p.name]) ? 'Installing…' : rowstate.pending('pkg', ['update', p.name]) ? 'Updating…'
    : rowstate.pending('pkg', ['remove', p.name]) ? 'Removing…' : rowstate.pending('parts', ['enable', p.name]) ? 'Turning on…' : rowstate.pending('parts', ['disable', p.name]) ? 'Turning off…' : '');
  const failure = failureOf;

  // ═══ bulk selection (Advanced: the full table) ═══
  let selected = $state(new Set());
  const toggle = (name, checked) => { const s = new Set(selected); if (checked) s.add(name); else s.delete(name); selected = s; };
  const selectedPkgs = $derived(pkgs.filter((p) => selected.has(p.name)));
  const canInstall = $derived(selectedPkgs.some((p) => p.state === 'new' && !red(p)));
  const canUpdate = $derived(selectedPkgs.some((p) => p.state === 'update'));
  const canRemove = $derived(selectedPkgs.some((p) => p.state !== 'new' && !p.core));
  let bulkBusy = $state(false);
  let bulkOpen = $state(null);           // { action, items } while the confirmation dialog is open
  let bulkSummary = $state([]);
  let showSummary = $state(false);

  // start one package (synchronous: status done / refused); each call blocks until the package change is finished
  const startOne = async (action, name) => {
    try {
      const r = await start('pkg', [action, name]);
      return { ok: r.status === 'done', reason: r.reason, status: r.status };
    } catch (e) {
      return { ok: false, reason: e.message, status: 'error' };
    }
  };

  const runBulk = (action) => {
    let items;
    if (action === 'install') items = selectedPkgs.filter((p) => p.state === 'new');
    else if (action === 'update') items = selectedPkgs.filter((p) => p.state === 'update');
    else items = selectedPkgs.filter((p) => p.state !== 'new' && !p.core);
    if (!items.length) return;
    bulkOpen = { action, items };
  };

  const confirmBulk = async () => {
    const { action, items } = bulkOpen;
    bulkOpen = null;
    bulkBusy = true;
    bulkSummary = [];
    try {
      for (const p of items) {
        const r = await startOne(action, p.name);
        bulkSummary.push({ name: p.name, ok: r.ok, reason: r.reason, status: r.status });
      }
      selected = new Set();
      await refresh(PATHS);
      showSummary = true;
    } finally {
      bulkBusy = false;
    }
  };

  const cancelBulk = () => { bulkOpen = null; };
  const dismissSummary = () => { showSummary = false; bulkSummary = []; };
  const failedCount = $derived(bulkSummary.filter((r) => !r.ok).length);
</script>

<PageHeader title="Marketplace"
            sub={market.loaded && !market.error ? `${store.filter((p) => p.kind === 'recipe').length} apps and ${store.filter((p) => p.kind !== 'recipe').length} add-ons${updates ? ` · ${updates} update${updates > 1 ? 's' : ''}` : ''}` : 'Apps and add-ons from the repositories you trust.'}>
  {#snippet actions()}
    <Button icon="arrows-clockwise" busy={rowstate.pending('pkg', ['fetch'])} busyLabel="Checking…" tooltip={'Read the repositories again and find the newest releases'} onclick={fetchAll}>Check for updates</Button>
    {#if tab === 'advanced'}
      <Button icon="hammer" tooltip={'Write the manifest of a new app or extension'} onclick={() => go(P.builder)}>Package builder</Button>
      <Button variant="primary" icon="plus" tooltip={'Add a repository of packages'} onclick={addRepo}>Add repository</Button>
    {/if}
  {/snippet}
</PageHeader>

<PageTabs {tabs} {tab} onpick={pick} controlled />

{#if tab !== 'advanced'}
  <PageState loading={!market.loaded} error={market.error?.message} hasData={market.data != null} empty={false} retry={() => refresh(PATHS)}>
    <div class="bar">
      {#if cats.length > 2}
        <div class="cats" role="group" aria-label="Categories">
          {#each cats as c (c.value)}
            <Button variant={category === c.value ? 'primary' : 'ghost'} size="sm" aria-pressed={category === c.value} onclick={() => (category = c.value)}>{c.label} <span class="cnt">{c.count}</span></Button>
          {/each}
        </div>
      {/if}
      <div class="find"><TextInput bind:value={q} type="search" placeholder={tab === 'addons' ? 'Search add-ons' : 'Search apps'} ariaLabel="Search" autocomplete="off" /></div>
    </div>

    {#if !inTab.length}
      <EmptyState icon={tab === 'updates' ? 'check-circle' : 'storefront'} title={tab === 'updates' ? 'No updates' : 'Nothing here yet'} text={emptyText[tab]} />
    {:else if !cards.length}
      <EmptyState icon="magnifying-glass" title="Nothing matches" text="Try another word or category." />
    {:else}
      <Grid min="250" gap="4">
        {#each cards as p (p.repo + '/' + p.name)}
          {@const acts = cardActions(p, openOf(p))}
          <AppTile title={p.name} line={p.title} href={packagePath(p.repo, p.name)} icon={p.icon} src={p.src} on={p.installed}
                   kicker={p.kind === 'recipe' ? '' : kindLabel(p.kind)} status={doing(p) || stateLine(p)}>
            {#snippet meta()}
              {#if p.category}<Chip>{categoryLabel(p.category)}</Chip>{/if}
              {#if trustOf(p.repo, repos)}<Chip kind="trust" level={trustOf(p.repo, repos)} title={`From the repository ${p.repo}. ${testedText(p.verified, trustOf(p.repo, repos))}`} />{/if}
              <Muted>{testedText(p.verified, trustOf(p.repo, repos))}</Muted>
              {#if failure(p)}{@const f = failure(p)}<ErrorNote error={f.error} ondismiss={() => rowstate.dismiss(f.id)} />{/if}
            {/snippet}
            {#snippet actions()}
              {#each acts as a (a.id)}
                <Button need={needOf(a.id)} variant={a.primary ? 'primary' : 'secondary'} size="sm" icon={a.icon} disabled={!!a.reason} reason={a.reason}
                        busy={busyOf(a.id, p)} tooltip={`${a.label} ${p.name}`} aria-label="{a.label} {p.name}" onclick={() => runAction(a.id, p, openOf(p))}>{a.label}</Button>
              {/each}
            {/snippet}
          </AppTile>
        {/each}
      </Grid>
    {/if}
  </PageState>
{:else}
  <h2 class="sect">Repositories</h2>
  <PageState loading={!repoList.loaded} error={repoList.error?.message} hasData={repoList.data != null} empty={repoList.loaded && !repoList.error && !repos.length}
             emptyIcon="database" emptyTitle="No repositories" emptyText="Add a repository to see its packages." retry={() => refresh(PATHS)}>
    <div class="card tc">
      <Table id="repos" columns={repoColumns} rows={repos} key="name" loading={!repoList.loaded} empty="No repository.">
        {#snippet cell(r, col)}
          {#if col.key === 'name'}
            <span class="nm"><i class="ph ph-database"></i>{r.name}</span>
          {:else if col.key === 'url'}
            <span class="ds">{r.url}</span>
          {:else if col.key === 'signed'}
            <StatusDot state={r.signed ? 'ok' : 'bad'} label={r.signed ? 'signed releases only' : 'unsigned'} />
          {:else if col.key === 'from'}
            {r.from === 'default' ? 'this project' : 'added by you'}
          {:else if r.from === 'added'}
            <Button need="admin" variant="ghost" class="btn-icon" icon="trash" busy={rowstate.pending('pkg', ['repo-remove', r.name])} tooltip={'Take this repository out (installed packages stay)'} aria-label="Remove {r.name}" onclick={() => dropRepo(r)} />
          {/if}
        {/snippet}
      </Table>
    </div>
    <div class="note">Packages run as root on this server. A release is used only when its signature verifies against the key the repository was added with.</div>
  </PageState>

  <h2 class="sect">All packages</h2>
  <PageState loading={!market.loaded} error={market.error?.message} hasData={market.data != null} empty={market.loaded && !market.error && !pkgs.length}
             emptyIcon="storefront" emptyTitle="Nothing to install yet" emptyText="No release of any repository has been read. Use Check for updates." retry={() => refresh(PATHS)}>
    {#if selected.size}
      <div class="bulk">
        <span class="bulk-count">{selected.size} selected</span>
        <Button variant={canInstall ? 'primary' : 'ghost'} size="sm" disabled={!canInstall || bulkBusy} onclick={() => runBulk('install')}>Install selected</Button>
        <Button variant={canUpdate ? 'primary' : 'ghost'} size="sm" disabled={!canUpdate || bulkBusy} onclick={() => runBulk('update')}>Update selected</Button>
        <Button variant={canRemove ? 'danger' : 'ghost'} size="sm" disabled={!canRemove || bulkBusy} onclick={() => runBulk('remove')}>Remove selected</Button>
        <Button variant="ghost" size="sm" disabled={bulkBusy} onclick={() => (selected = new Set())}>Clear selection</Button>
      </div>
    {/if}

    <div class="card tc">
      <Table id="market" {columns} rows={pkgs} key="name" loading={!market.loaded} empty="No package.">
        {#snippet cell(p, col)}
          {#if col.key === 'sel'}
            <Switch box checked={selected.has(p.name)} onchange={(c) => toggle(p.name, c)} label="Select {p.name}" />
          {:else if col.key === 'go'}
            {#if p.state === 'new'}
              <Button need="app-manager" variant="primary" size="sm" busy={rowstate.pending('apps', ['install', p.name])} busyLabel="Installing…" tooltip={`Install ${p.name} from ${p.repo}`} onclick={() => install(p)}>Install</Button>
            {:else if p.state === 'update'}
              <Button need="admin" variant="primary" size="sm" busy={rowstate.pending('pkg', ['update', p.name])} busyLabel="Updating…" tooltip={`Update to ${p.avail}: shows what changed first`} onclick={() => update(p)}>Update</Button>
            {/if}
          {:else if col.key === 'name'}
            <a class="nm" {...link(packagePath(p.repo, p.name))}><i class="ph ph-{kindIcon(p.kind)}" style="color:{p.state === 'new' ? 'var(--fg-3)' : 'var(--accent-ink)'}"></i>{p.name}</a>
            <div class="in">{kindLabel(p.kind)}{p.core ? ' · the server needs it' : ''}</div>
            {#if failure(p)}{@const f = failure(p)}<ErrorNote error={f.error} ondismiss={() => rowstate.dismiss(f.id)} />{/if}
          {:else if col.key === 'title'}
            <span class="ds">{p.title}</span>
          {:else if col.key === 'repo'}
            {p.repo}
          {:else if col.key === 'state'}
            {#if doing(p)}<Chip tone="info">{doing(p)}</Chip>{/if}
            {#if stageOf.get(p.name)}
              <StageBadge stage={stageOf.get(p.name).stage} flags={stageOf.get(p.name).flags} />
            {:else}
              <StatusDot state={stateDot(p)} label={stateText(p)} />
            {/if}
          {:else if p.state !== 'new'}
            {@const turnTo = stageActions(stageOf.get(p.name)).turn}
            {#if turnTo}
              <Button need="admin" size="sm" busy={rowstate.pending('parts', ['enable', p.name]) || rowstate.pending('parts', ['disable', p.name])} tooltip={turnTo === 'enable' ? 'Switch it on (shows the plan)' : 'Switch it off (shows the plan)'} onclick={() => turn(p, turnTo)}>{turnTo === 'enable' ? 'Turn on' : 'Turn off'}</Button>
            {/if}
            <Button need="admin" variant="ghost" class="btn-icon" icon="trash" disabled={p.core} busy={rowstate.pending('pkg', ['remove', p.name])} tooltip={p.core ? 'The server refers to this package by name: it stays' : 'Remove the installed copy (data and containers stay)'} aria-label="Remove {p.name}" onclick={() => remove(p)} />
          {/if}
        {/snippet}
      </Table>
    </div>
  </PageState>
{/if}

{#if bulkOpen}
  <Dialog title="Bulk change" panel="dialog" width="460px" onclose={cancelBulk}>
    <div class="bulkd">
      <h3 class:bad={bulkOpen.action === 'remove'}>
        {bulkOpen.action === 'install' ? 'Install the selected packages'
         : bulkOpen.action === 'update' ? 'Update the selected packages'
         : 'Remove the selected packages'}
      </h3>
      <p class={bulkOpen.action === 'remove' ? 'bulk-warn' : ''}>
        {bulkOpen.action === 'remove' ? 'This removes the installed copy of each package. Data and containers made by a recipe stay.'
         : 'Each package gets its own change and they run one after another.'}
      </p>
      <ul class="bulk-list">
        {#each bulkOpen.items as p}<li>{p.name} <Muted>({stateText(p)})</Muted></li>{/each}
      </ul>
      <div class="bulk-foot">
        <Button onclick={cancelBulk}>Cancel</Button>
        <Button variant={bulkOpen.action === 'remove' ? 'danger' : 'primary'} disabled={bulkBusy} onclick={confirmBulk}>
          {bulkOpen.action === 'remove' ? 'Remove' : 'Start'}{bulkOpen.items.length === 1 ? '' : ' ' + bulkOpen.items.length + (bulkOpen.action === 'remove' ? '' : ' jobs')}
        </Button>
      </div>
    </div>
  </Dialog>
{/if}

{#if showSummary}
  <Dialog title="Result" panel="dialog" width="460px" onclose={dismissSummary}>
    <div class="bulkd">
      <h3 class:bad={failedCount > 0}>{failedCount > 0 ? 'Some changes failed' : 'All changes finished'}</h3>
      <ul class="bulk-list">
        {#each bulkSummary as r}
          <li class:bad={!r.ok}>{r.name} <Muted>{r.ok ? 'finished' : (r.reason ?? ('status: ' + (r.status ?? 'failed')))}</Muted></li>
        {/each}
      </ul>
      <div class="bulk-foot">
        <Button variant="primary" onclick={dismissSummary}>Done</Button>
      </div>
    </div>
  </Dialog>
{/if}

<style>
  .bar { display: flex; gap: var(--space-3); align-items: center; flex-wrap: wrap; margin: 14px 0 14px; }
  .cats { display: flex; gap: 4px; flex-wrap: wrap; min-width: 0; }
  .cnt { font: 500 10.5px var(--mono); opacity: 0.75; }
  .find { margin-left: auto; width: 240px; max-width: 100%; }
  .sect { margin: 18px 0 8px; font-size: 15px; font-weight: 600; }
  .nm { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; font-size: 13.5px; color: var(--fg); text-decoration: none; }
  a.nm:hover { text-decoration: underline; }
  .nm i { font-size: 18px; }
  .ds { font-size: 12.5px; color: var(--fg-3); }
  .in { font-size: 12px; color: var(--fg-3); margin-left: 26px; }
  .note { font-size: 12.5px; color: var(--fg-3); margin-top: 10px; }
  .bulk { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin: 10px 0 6px; }
  .bulk-count { font: 500 12.5px var(--mono); color: var(--fg-2); }
  .bulkd { display: flex; flex-direction: column; gap: 12px; }
  .bulkd h3 { margin: 0 0 2px; font-size: 17px; font-weight: 600; letter-spacing: -0.02em; }
  .bulkd h3.bad { color: var(--bad-ink); }
  .bulkd p { margin: 0; font-size: 12.5px; color: var(--fg-3); }
  .bulk-warn { color: var(--bad-ink); }
  .bulk-list { margin: 0; padding: 0 0 0 20px; font-size: 13px; color: var(--fg); gap: 6px; display: flex; flex-direction: column; }
  .bulk-list li { display: flex; justify-content: space-between; gap: 10px; }
  .bulk-list li.bad { color: var(--bad-ink); }
  .bulk-foot { display: flex; gap: 8px; justify-content: flex-end; padding-top: 8px; border-top: 1px solid var(--line); }
  .bad { color: var(--bad-ink); }
  @media (max-width: 640px) { .find { margin-left: 0; width: 100%; } }
</style>
