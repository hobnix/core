<script>
  // The Marketplace: every package of every repository (recipes and extensions are both just packages), and the repositories they come from.
  // Reads: hs sys pkg market / repos. Changes: hs sys pkg plan|start (install, update, remove, fetch, repo-add, repo-remove); a package or repository
  // that came from a repository somebody added is red (the typed word is its name).
  import { poll, rows, refresh } from '../data.svelte.js';
  import { openPlan, openCreate, jobRunning, ui } from '../ui.svelte.js';
  import { route, go } from '../route.svelte.js';
  import { start } from '../api.js';
  import RepoAdd from '../forms/ops/RepoAdd.svelte';
  import InstallDialog from '../forms/ops/InstallDialog.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import PageTabs from '../ui/PageTabs.svelte';
  import Button from '../ui/Button.svelte';
  import { TextInput, Switch, Dialog, Muted } from '../ui/index.js';
  import StatusDot from '../ui/StatusDot.svelte';
  import StageBadge from '../ui/StageBadge.svelte';
  import { parseStates, stageActions } from './states.js';

  const market = poll('/api/sys/pkg/market', 30000);
  const repoList = poll('/api/sys/pkg/repos', 30000);
  // the lifecycle stage and flags of every package (ADR 0027); the table still reads the market for the versions and `core`
  const stateList = poll('/api/sys/pkg/states', 30000);
  const stageOf = $derived(parseStates(rows(stateList)));
  const PATHS = ['/api/sys/pkg/market', '/api/sys/pkg/repos', '/api/sys/pkg/states'];

  // name, kind, repository, available version, installed version (- = none), state (new|current|update|waits|orphan), core, audience, title
  const pkgs = $derived(rows(market).map((r) => ({ name: r[0], kind: r[1], repo: r[2], avail: r[3], inst: r[4] === '-' ? '' : r[4], state: r[5], core: r[6] === 'yes', title: r[8] === '-' ? '' : r[8] })));
  // name, address, signed|unsigned, default|added
  const repos = $derived(rows(repoList).map((r) => ({ name: r[0], url: r[1], signed: r[2] === 'signed', from: r[3] })));
  const updates = $derived(pkgs.filter((p) => p.state === 'update').length);

  const tabs = [{ id: 'packages', label: 'Packages' }, { id: 'repos', label: 'Repositories' }];
  const tab = $derived(tabs.some((t) => t.id === route.query.tab) ? route.query.tab : 'packages');
  const pick = (id) => go(id === 'packages' ? '/marketplace' : `/marketplace?tab=${id}`);

  let q = $state('');
  let kind = $state('all');
  let show = $state('all');
  const shown = $derived(pkgs.filter((p) => (kind === 'all' || p.kind === kind)
    && (show === 'all' || (show === 'installed' ? p.state !== 'new' : show === 'updates' ? p.state === 'update' : p.state === 'new'))
    && (!q.trim() || (p.name + ' ' + p.title).toLowerCase().includes(q.trim().toLowerCase()))));

  const kindLabel = (k) => (k === 'recipe' ? 'App' : k === 'extension' ? 'Extension' : 'Package');
  const kindIcon = (k) => (k === 'extension' ? 'puzzle-piece' : 'package');
  const stateDot = (p) => (p.state === 'current' ? 'ok' : p.state === 'update' || p.state === 'waits' || p.state === 'orphan' ? 'warn' : 'off');
  const stateText = (p) => (p.state === 'new' ? 'not installed' : p.state === 'current' ? `installed ${p.inst}` : p.state === 'update' ? `${p.inst} → ${p.avail}` : 'repository gone');
  const columns = [
    { key: 'sel', label: '', sort: false, width: '44px' },
    { key: 'go', label: '', sort: false }, { key: 'name', label: 'Package' }, { key: 'title', label: 'What it is' },
    { key: 'repo', label: 'Repository' }, { key: 'state', label: 'State' }, { key: 'tools', label: '', sort: false, align: 'right' },
  ];
  const repoColumns = [
    { key: 'name', label: 'Repository' }, { key: 'url', label: 'Address' }, { key: 'signed', label: 'Releases' }, { key: 'from', label: 'From' },
    { key: 'tools', label: '', sort: false, align: 'right' },
  ];

  const install = (p) => openCreate(InstallDialog, { pkg: p.name, repo: p.repo });
  const update = (p) => openPlan('pkg', ['update', p.name], `Update ${p.name}`);
  const turn = (p, want) => openPlan('parts', [want, p.name], `${want === 'enable' ? 'Turn on' : 'Turn off'} ${p.name}`);
  const remove = (p) => openPlan('pkg', ['remove', p.name], `Remove ${p.name}`);
  const fetchAll = () => openPlan('pkg', ['fetch'], 'Read the repositories again');
  const addRepo = () => openCreate(RepoAdd, {});
  const dropRepo = (r) => openPlan('pkg', ['repo-remove', r.name], `Remove the repository ${r.name}`);

  // a package that came from an added repository is red: installing it needs the name typed, which a bulk run cannot do per item
  const red = (p) => repos.find((r) => r.name === p.repo)?.from === 'added';

  // what a change did shows after its dialog closes
  let was = false;
  $effect(() => {
    const open = !!ui.dialog || !!ui.create;
    if (was && !open) setTimeout(() => refresh(PATHS), 400);
    was = open;
  });

  // ═══ bulk selection ═══
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

<PageHeader title="Marketplace" crumb={ui.host}
            sub={market.loaded && !market.error ? `${pkgs.length} packages from ${repos.length} repositories${updates ? ` · ${updates} update${updates > 1 ? 's' : ''}` : ''}` : 'Apps and extensions from the repositories you trust.'}>
  {#snippet actions()}
    <Button icon="arrows-clockwise" busy={jobRunning('pkg', ['fetch'])} busyLabel="Checking…" tooltip={'Read the repositories again and find the newest releases'} onclick={fetchAll}>Check for updates</Button>
    <Button icon="hammer" tooltip={'Write the manifest of a new app or extension'} onclick={() => go('/marketplace/builder')}>Package builder</Button>
    <Button variant="primary" tooltip={'Add a repository of packages'} onclick={addRepo}><i class="ph ph-plus"></i>Add repository</Button>
  {/snippet}
</PageHeader>

<PageTabs {tabs} {tab} onpick={pick} />

{#if tab === 'packages'}
  <PageState loading={!market.loaded} error={market.error?.message} hasData={market.data != null} empty={market.loaded && !market.error && !pkgs.length}
             emptyIcon="storefront" emptyTitle="Nothing to install yet" emptyText="No release of any repository has been read. Use Check for updates." retry={() => refresh(PATHS)}>
    <div class="bar">
      {#each [['all', 'All'], ['recipe', 'Apps'], ['extension', 'Extensions']] as [k, l]}
        <Button variant={kind === k ? 'primary' : 'ghost'} size="sm" onclick={() => (kind = k)}>{l}</Button>
      {/each}
      <span class="sep"></span>
      {#each [['all', 'Any'], ['installed', 'Installed'], ['updates', 'Updates'], ['new', 'Not installed']] as [k, l]}
        <Button variant={show === k ? 'primary' : 'ghost'} size="sm" onclick={() => (show = k)}>{l}</Button>
      {/each}
      <div class="find"><TextInput bind:value={q} placeholder="Search packages" ariaLabel="Search packages" autocomplete="off" /></div>
    </div>

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
      <Table id="market" {columns} rows={shown} key="name" loading={!market.loaded} empty="No package matches.">
        {#snippet cell(p, col)}
          {@const on = p.state !== 'new'}
          {#if col.key === 'sel'}
            <Switch box checked={selected.has(p.name)} onchange={(c) => toggle(p.name, c)} label="Select {p.name}" />
          {:else if col.key === 'go'}
            {#if p.state === 'new'}
              <Button variant="primary" size="sm" busy={jobRunning('apps', ['install', p.name])} busyLabel="Installing…" tooltip={`Install ${p.name} from ${p.repo}`} onclick={() => install(p)}>Install</Button>
            {:else if p.state === 'update'}
              <Button variant="primary" size="sm" busy={jobRunning('pkg', ['update', p.name])} busyLabel="Updating…" tooltip={`Update to ${p.avail}: shows what changed first`} onclick={() => update(p)}>Update</Button>
            {/if}
          {:else if col.key === 'name'}
            <span class="nm"><i class="ph ph-{kindIcon(p.kind)}" style="color:{p.state === 'new' ? 'var(--fg-3)' : 'var(--accent-ink)'}"></i>{p.name}</span>
            <div class="in">{kindLabel(p.kind)}{p.core ? ' · the server needs it' : ''}</div>
          {:else if col.key === 'title'}
            <span class="ds">{p.title}</span>
          {:else if col.key === 'repo'}
            {p.repo}
          {:else if col.key === 'state'}
            {#if stageOf.get(p.name)}
              <StageBadge stage={stageOf.get(p.name).stage} flags={stageOf.get(p.name).flags} />
            {:else}
              <StatusDot state={stateDot(p)} label={stateText(p)} />
            {/if}
          {:else if p.state !== 'new'}
            {@const turnTo = stageActions(stageOf.get(p.name)).turn}
            {#if turnTo}
              <Button size="sm" busy={jobRunning('parts', ['enable', p.name]) || jobRunning('parts', ['disable', p.name])} tooltip={turnTo === 'enable' ? 'Switch it on (shows the plan)' : 'Switch it off (shows the plan)'} onclick={() => turn(p, turnTo)}>{turnTo === 'enable' ? 'Turn on' : 'Turn off'}</Button>
            {/if}
            <Button variant="ghost" class="btn-icon" icon="trash" disabled={p.core} busy={jobRunning('pkg', ['remove', p.name])} tooltip={p.core ? 'The server refers to this package by name: it stays' : 'Remove the installed copy (data and containers stay)'} aria-label="Remove {p.name}" onclick={() => remove(p)} />
          {/if}
        {/snippet}
      </Table>
    </div>
  </PageState>
{:else}
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
            <Button variant="ghost" class="btn-icon" icon="trash" busy={jobRunning('pkg', ['repo-remove', r.name])} tooltip={'Take this repository out (installed packages stay)'} aria-label="Remove {r.name}" onclick={() => dropRepo(r)} />
          {/if}
        {/snippet}
      </Table>
    </div>
    <div class="note">Packages run as root on this server. A release is used only when its signature verifies against the key the repository was added with.</div>
  </PageState>
{/if}

{#if bulkOpen}
  <Dialog title="Bulk change" panel="dialog" width="460px" onclose={cancelBulk}>
    <div class="bulkd">
      <h3 class:{bad}={bulkOpen.action === 'remove'}>
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
      <h3 class:{bad}={failedCount > 0}>{failedCount > 0 ? 'Some changes failed' : 'All changes finished'}</h3>
      <ul class="bulk-list">
        {#each bulkSummary as r}
          <li class:{bad}={!r.ok}>{r.name} <Muted>{r.ok ? 'finished' : (r.reason ?? ('status: ' + (r.status ?? 'failed')))}</Muted></li>
        {/each}
      </ul>
      <div class="bulk-foot">
        <Button variant="primary" onclick={dismissSummary}>Done</Button>
      </div>
    </div>
  </Dialog>
{/if}

<style>
  .bar { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-top: 12px; }
  .sep { width: 1px; height: 18px; background: var(--line); margin: 0 4px; }
  .find { margin-left: auto; max-width: 240px; }
  .nm { display: inline-flex; align-items: center; gap: 8px; font-weight: 600; font-size: 13.5px; }
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
</style>
