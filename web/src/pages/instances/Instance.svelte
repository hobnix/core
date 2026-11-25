<script>
  // Apps & VMs > one instance: /apps/instance/<name>[/<tab>] (D6). The Object template (shell/ObjectPage.svelte) with the tabs Overview, Config, Network and Console (D3 a):
  //   Overview  the facts, the recipe that set it up, backup, the Docker apps of a Docker host, the linked shares, route and recipes
  //   Config    the settings, the storage bindings and the snapshots
  //   Network   the address and the route the reverse proxy publishes
  //   Console   a shell (and the screen of a VM) in their windows, and the journal
  // Actions (D4): primary Start or Stop; ONE secondary that follows the tab (Overview: Restart, Config: Settings, Network: Settings, Console: Terminal); the rest in
  // the More menu; Delete only in the danger section. A running or failed job shows on the header and the job strip. A viewer sees all of it read-only.
  import { P, poolPath, dockerAppPagePath } from '../../paths.js';
  import { setSelection } from '../../select.svelte.js';
  import { route, go } from '../../route.svelte.js';
  import { objectOf, objects } from '../../objects.js';
  import { poll, rows } from '../../data.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { openPlan, openCreate, ui } from '../../ui.svelte.js';
  import ObjectPage from '../../shell/ObjectPage.svelte';
  import ErrorNote from '../../ui/ErrorNote.svelte';
  import { Banner, Button, Card, Chip, Kv, Muted, Row } from '../../ui/index.js';
  import Terminal from '../../shell/Terminal.svelte';
  import VmConsole from '../../shell/VmConsole.svelte';
  import InstanceSettings from '../../forms/instances/InstanceSettings.svelte';
  import BindStorage from '../../forms/instances/BindStorage.svelte';
  import ConfigTab from './ConfigTab.svelte';
  import NetworkTab from './NetworkTab.svelte';
  import ConsoleTab from './ConsoleTab.svelte';
  import { instancePath } from './path.js';
  import { sharePath } from '../shares/path.js';
  import { childrenOf } from '../docker/apps.js';
  import { isVm, isRunning } from './ct.js';
  import { instanceModel, kindOf, word, dot, boots, spaced, dash } from './model.svelte.js';

  const at = $derived(objectOf(route.path));
  const name = $derived(at?.kind === 'instance' ? at.id : '');
  const tabId = $derived(at?.tab ?? '');
  const tab = $derived(objects.instance.tabs.some((t) => t.id === tabId) ? tabId : 'overview');
  const m = instanceModel({ sel: () => name, detail: true, tab: () => tab });
  const dl = poll('/api/sys/docker/list', 30000);

  const c = $derived(m.ct);
  const doing = $derived(m.doing(c));
  const failure = $derived(m.failure(c));
  const running = $derived(!!c && isRunning(c));
  const kids = $derived(c && c.owner === 'docker' ? (childrenOf(rows(dl)).get(c.name) ?? []) : []);
  const terminalWhy = $derived(!ui.features.terminal ? 'Switch on webTerminal in machine.toml' : !running ? 'The instance is not running' : '');

  const plan = (action) => openPlan('ct', [name, action], `${action} ${name}`, action === 'stop' ? { option: { label: 'also keep it off at boot', args: ['--autostart', 'off'] } } : {});
  const act = $derived({
    power: { label: running ? 'Stop' : 'Start', icon: running ? 'stop' : 'play', need: 'app-manager', busy: m.busyOf(c, ['stop'], ['stop', '--autostart', 'off'], ['start']), reason: running ? 'Stop this instance' : 'Start this instance', onclick: () => plan(running ? 'stop' : 'start') },
    restart: { label: 'Restart', icon: 'arrow-clockwise', need: 'app-manager', busy: m.busyOf(c, ['restart']), reason: 'Stop and start this instance again', onclick: () => plan('restart') },
    update: { label: 'Update', icon: 'arrows-clockwise', need: 'app-manager', busy: m.busyOf(c, ['update']), reason: 'Snapshot the instance, then update the software inside', onclick: () => openPlan('ct', [name, 'update'], `Update ${name}`) },
    snapshot: { label: 'Snapshot now', icon: 'camera', need: 'app-manager', busy: m.busyOf(c, ['snapshot']), reason: 'Take a snapshot of this instance now', onclick: () => openPlan('ct', [name, 'snapshot'], `Snapshot ${name}`) },
    settings: { label: 'Settings…', icon: 'sliders', need: 'app-manager', reason: 'Change memory, CPU, storage and other settings', onclick: () => openCreate(InstanceSettings, { ct: c }) },
    bind: { label: 'Bind a share…', icon: 'plus', need: 'app-manager', reason: 'Give this instance a folder of a pool or a share', onclick: () => openCreate(BindStorage, { ct: name }) },
    terminal: { label: 'Terminal', icon: 'terminal-window', need: 'admin', disabled: !!terminalWhy, reason: terminalWhy || 'A shell inside the instance', onclick: () => openCreate(Terminal, { target: name, title: name }) },
    screen: { label: 'Screen…', icon: 'monitor', need: 'admin', disabled: !!terminalWhy, reason: terminalWhy || 'The screen of the virtual machine', onclick: () => openCreate(VmConsole, { target: name, title: name }) },
  });
  // the one secondary action of the header follows the tab
  const second = $derived(tab === 'config' || tab === 'network' ? 'settings' : tab === 'console' ? 'terminal' : 'restart');
  const menu = $derived.by(() => {
    if (!c) return [];
    const keys = ['restart', 'update', 'snapshot', 'settings', ...(c.owner ? [] : ['bind']), 'terminal', ...(isVm(c) ? ['screen'] : [])].filter((k) => k !== second);
    return keys.map((k) => ({ label: act[k].label, icon: act[k].icon, need: act[k].need, disabled: act[k].disabled, reason: act[k].reason, onclick: act[k].onclick }));
  });
  const danger = $derived(!c || c.owner ? [] : [{ label: 'Delete…', text: 'Removes the instance and its own volume. The plan asks for its name; a snapshot is the only way back.', need: 'app-manager', onclick: () => openPlan('ct', [name, 'delete'], `Delete ${name}`) }]);
  const links = $derived.by(() => {
    if (!c) return [];
    return [
      ...m.bindings.filter((b) => b.share && b.share !== '-').map((b) => ({ kind: 'Share', name: b.share, href: sharePath(b.share), note: b.mode })),
      ...m.bindings.filter((b) => (!b.share || b.share === '-') && b.pool && b.pool !== '-').map((b) => ({ kind: 'Pool', name: b.pool, href: poolPath(b.pool) })).filter((x, i, a) => a.findIndex((y) => y.href === x.href) === i),
      ...m.myServices.map((s) => ({ kind: 'Service', name: s.title && s.title !== '-' ? s.title : s.name, href: P.services, note: s.exposure })),
      ...m.myRecipes.map((r) => ({ kind: 'Recipe', name: r.name, href: P.apps })),
      { kind: 'Pages', name: 'Backup', href: P.backup, note: m.backupKnown && c.name in m.backupOf ? (m.backupOf[c.name] ? 'in the backup' : 'not in the backup') : '' },
    ];
  });
  const openRecipe = (recipe) => { setSelection('recipes', recipe); go(P.apps); };
  const re = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const jobs = $derived((r) => !!name && new RegExp(`(^|[^\\w-])${re(name)}($|[^\\w-])`).test(r.description ?? ''));
</script>

<ObjectPage title={name} chip={c ? kindOf(c) : ''} state={c ? (failure ? 'bad' : doing ? 'info' : dot(c.state)) : ''} stateLabel={failure ? 'failed' : doing ? `${doing.toLowerCase()}…` : c ? word(c.state) : ''}
            tabs={objects.instance.tabs} {tab} onpick={(id) => go(instancePath(name, id))} {menu} {danger} {links} {jobs} need="app-manager"
            loading={!m.ctl.loaded} error={m.ctl.error && !m.ctl.data ? m.ctl.error.message : ''} notFound={m.ctl.loaded && !c} notFoundTitle="No such instance" backTo={P.appsGroup} backLabel="All apps and VMs"
            notFoundText={`No instance called “${name}” exists. It may have been deleted or renamed.`}>
  {#snippet primary()}
    {#if c}
      <Button need={act.power.need} variant="primary" icon={act.power.icon} busy={act.power.busy} busyLabel={running ? 'Stopping…' : 'Starting…'} tooltip={act.power.reason} onclick={act.power.onclick}>{act.power.label}</Button>
      <Button need={act[second].need} icon={act[second].icon} busy={act[second].busy} disabled={act[second].disabled} tooltip={act[second].reason} onclick={act[second].onclick}>{act[second].label}</Button>
    {/if}
  {/snippet}
  {#snippet banners()}
    {#if c}
      {#if doing}<Banner tone="info">{doing}… a job is running on this instance; this page follows it.</Banner>
      {:else if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
      {#if c.owner}<Banner tone="info">Managed by {c.owner}: turn it off under Settings, Capabilities to change its storage or delete it.</Banner>{/if}
    {/if}
  {/snippet}
  {#snippet children(t)}
    {#if c}
      {#if t === 'config'}
        <ConfigTab {m} />
      {:else if t === 'network'}
        <NetworkTab {m} />
      {:else if t === 'console'}
        <ConsoleTab {m} />
      {:else}
        <Card title="Overview">
          <Row gap="2" wrap><Chip>{boots(c) ? 'starts at boot' : 'not set to start at boot'}</Chip>{#if c.owner}<Chip kind="strong">locked: {c.owner}</Chip>{/if}</Row>
          <Kv items={[
            { k: 'Type', v: isVm(c) ? 'virtual machine' : 'container' }, { k: 'State', v: doing ? `${doing}…` : word(c.state) }, { k: 'Address', v: dash(c.address) },
            { k: 'RAM / CPU', v: `${spaced(c.ram) || '–'} / ${c.cpu || '–'}` }, { k: 'Disk', v: dash(c.disk) }, { k: 'Last snapshot', v: dash(c.lastSnap) },
            { k: 'Backup', v: m.backupKnown && c.name in m.backupOf ? (m.backupOf[c.name] ? 'in the nightly backup' : 'not in the backup') : '' },
          ]} />
          {#if m.myRecipes.length}
            <Row gap="2" wrap align="center"><Muted>Set up by the recipe</Muted>{#each m.myRecipes as r (r.name)}<Button variant="ghost" size="sm" tooltip="Open the recipe in the app catalog" onclick={() => openRecipe(r.name)}>{r.name}</Button>{/each}</Row>
          {/if}
          <Muted as="p">Whether it is in the backup is set on <Button variant="ghost" size="sm" tooltip="Open the Backup page" onclick={() => go(P.backup)}>Backup</Button>.</Muted>
        </Card>
        {#if kids.length}
          <Card title="Docker apps">
            <Row gap="3" wrap>{#each kids as r (r[0])}<Button size="sm" icon="shipping-container" tooltip="Open the page of this Docker app" onclick={() => go(dockerAppPagePath(r[0]))}>{r[0]} · {r[3]}</Button>{/each}</Row>
          </Card>
        {/if}
      {/if}
    {/if}
  {/snippet}
</ObjectPage>
