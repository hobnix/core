<script>
  // Developer > Components (#449): every `ui` component, and the shell pieces that are shared, in each of its states. The reference for the pages
  // (docs/PLAN-web-design.md section 5) and for packages that declare pages (#195). A component without an `<Entry name="...">` here fails
  // tests/web-gallery.sh. Static data only: nothing here reads the server, except the two live shell pieces (JobStrip, Inbox) that read their own stores.
  import PageHeader from '../shell/PageHeader.svelte';
  import Table from '../shell/Table.svelte';
  import UsageBar from '../shell/UsageBar.svelte';
  import Spark from '../shell/Spark.svelte';
  import PageState from '../shell/PageState.svelte';
  import LinkedObjects from '../shell/LinkedObjects.svelte';
  import JobStrip from '../shell/JobStrip.svelte';
  import Inbox from '../shell/Inbox.svelte';
  import Entry from './gallery/Entry.svelte';
  import Logo from '../ui/Logo.svelte';
  import PageTabs from '../ui/PageTabs.svelte';
  import {
    Banner, Button, Card, Checkbox, Segmented, ChoiceList, Chip, Combobox, DangerZone, Dialog, Drawer, EmptyState, ErrorNote, Field, Icon, Kv, Menu, Muted, NetMap, NodePopover,
    Progress, QuickLook, Row, Select, Skeleton, Split, Stack, StageBadge, StateCard, StatusDot, StepList, Stepper, Slider, Switch, TextInput, Textarea,
    Timeline, Wizard, toast,
  } from '../ui/index.js';
  import { SMALL, SMALL_RATES, big } from '../netmap/fixtures.js';
  import { theme, toggleTheme } from '../theme.svelte.js';
  import { tr } from '../i18n.js';

  let phone = $state(false);
  let dialog = $state(false);
  let quick = $state(false);
  let split = $state(true);
  let drawerTab = $state('info');
  let tab = $state('overview');
  let on = $state(true);
  let box = $state(false);
  let checked = $state(true);
  let text = $state('photos');
  let level = $state(40);
  let area = $state('One line\nAnother line');
  let combo = $state('');
  let sel = $state('zfs');
  let timeFilters = $state({ level: '' });
  let wiz = $state(1);
  let choice = $state('a');

  const bigMap = big(100);
  const now = Math.floor(Date.now() / 1000);
  const entries = [
    { id: 1, time: now - 60, severity: 'bad', title: 'Backup failed', text: 'The target was not reachable.', kind: 'job.failed', object: { label: 'nightly', href: '#' }, ackable: true },
    { id: 2, time: now - 3600, severity: 'warn', title: 'Disk is warm', text: '54 °C', kind: 'disk.temp', ackable: true, acked: true },
    { id: 3, time: now - 90000, severity: 'ok', title: 'Scrub finished', kind: 'pool.scrub' },
    { id: 4, time: now - 100000, severity: 'info', title: 'Update available' },
  ];
  const cols = [
    { key: 'name', label: 'Name' },
    { key: 'size', label: 'Size', sort: 'num', align: 'right' },
    { key: 'note', label: 'Note', optional: true },
  ];
  const rowsData = [{ name: 'tank', size: 4000, note: 'mirror' }, { name: 'data', size: 12000, note: '' }, { name: 'scratch', size: 500, note: 'stripe' }];
  const steps = [{ label: 'Download', state: 'done' }, { label: 'Install', state: 'current', note: 'about 2 min' }, { label: 'Start' }, { label: 'Check', state: 'failed' }, { label: 'Clean up', state: 'skipped' }];
  const menu = [{ label: 'Rename', icon: 'pencil-simple', onclick: () => {} }, { sep: true }, { label: 'Move', disabled: true, reason: 'Needs the admin role' }, { label: 'Delete', danger: true, onclick: () => {} }];
  const icons = ['check-circle', 'warning', 'warning-octagon', 'info', 'lock', 'gear-six', 'trash', 'plus', 'x'];
  const linked = [{ kind: 'Pool', name: 'tank', href: '#', state: 'ok' }, { kind: 'Share', name: 'photos', href: '#', state: 'warn', label: 'full' }, { kind: 'Instance', name: 'nextcloud', href: '#', state: 'off', note: 'stopped' }];
  const danger = [{ label: 'Remove pool…', text: 'Frees the disks. The data on them is lost.', area: 'pool', args: ['destroy', 'tank'], title: 'Remove pool tank' }, { label: 'Wipe…', text: 'Only an admin may.', area: 'pool', args: ['wipe'], disabled: true, reason: 'Needs the admin role' }];
  const hist = [10, 20, 35, 30, 60, 80, 95, 70, 40, 30, 45, 50];
  const slow = () => new Promise((r) => setTimeout(r, 1500));
</script>

<div class="page">
  <PageHeader title="Components" crumb="Developer" sub={tr('Every shared component in each of its states. A component without an entry here fails the gallery test.')}>
    {#snippet actions()}
      <Button onclick={toggleTheme}>{theme.dark ? 'Show light' : 'Show dark'}</Button>
      <Button aria-pressed={phone} onclick={() => (phone = !phone)}>{phone ? 'Full width' : 'Phone width (375 px)'}</Button>
    {/snippet}
  </PageHeader>
  <Banner tone="info">{tr('Phone width narrows the column the entries sit in. Rules that depend on the width of the window (the drawer covering the page, the stepper showing one step) need a narrow window.')}</Banner>

  <div class="gal" class:phone>
    <Entry name="Button" text="Every button that starts something. Busy keeps its width and ignores clicks; a disabled button says why.">
      <div class="cell"><small>primary</small><Button variant="primary" icon="plus">Add</Button></div>
      <div class="cell"><small>secondary</small><Button>Cancel</Button></div>
      <div class="cell"><small>ghost</small><Button variant="ghost">Skip</Button></div>
      <div class="cell"><small>danger</small><Button variant="danger" icon="trash">Remove</Button></div>
      <div class="cell"><small>sm</small><Button size="sm">Small</Button></div>
      <div class="cell"><small>busy</small><Button variant="primary" busy busyLabel="Applying…">Apply</Button></div>
      <div class="cell"><small>busy after click (1.5 s)</small><Button icon="check-circle" onclick={slow}>Run</Button></div>
      <div class="cell"><small>disabled + reason</small><Button disabled reason="Storage is locked">Mount</Button></div>
      <div class="cell"><small>role refused (need=admin)</small><Button need="admin">Reboot</Button></div>
      <div class="cell"><small>icon only</small><Button variant="ghost" icon="trash" label="Remove photos" /></div>
    </Entry>

    <Entry name="Icon" text="One icon by name. Decorative unless it has a label.">
      <div class="cell"><small>names</small><Row>{#each icons as n (n)}<Icon name={n} />{/each}</Row></div>
      <div class="cell"><small>labelled</small><Icon name="warning" label="Needs attention" /></div>
      <div class="cell"><small>spin</small><Icon name="circle-notch" spin /></div>
    </Entry>

    <Entry name="Chip" text="Small mono label. Trust and status chips carry an icon and a word.">
      <div class="cell"><small>plain</small><Chip>zfs</Chip></div>
      <div class="cell"><small>strong</small><Chip kind="strong">strong</Chip></div>
      <div class="cell"><small>out / in</small><Row><Chip kind="out">outside</Chip><Chip kind="in">this server</Chip></Row></div>
      <div class="cell"><small>tone</small><Row><Chip tone="accent">accent</Chip><Chip tone="soft">soft</Chip><Chip tone="warn">warn</Chip><Chip tone="bad">bad</Chip><Chip tone="info">info</Chip></Row></div>
      <div class="cell"><small>trust</small><Row><Chip kind="trust" level="official" /><Chip kind="trust" level="signed" tested="2026-11-18" /><Chip kind="trust" level="community" /></Row></div>
      <div class="cell"><small>status</small><Row>{#each ['ok', 'warn', 'bad', 'info', 'off'] as s (s)}<Chip kind="status" state={s} />{/each}</Row></div>
    </Entry>

    <Entry name="StatusDot" text="Never colour alone: the word comes with it. Bare keeps the word for screen readers.">
      {#each ['ok', 'warn', 'bad', 'info', 'off'] as s (s)}<div class="cell"><small>{s}</small><StatusDot state={s} /></div>{/each}
      <div class="cell"><small>own word</small><StatusDot state="warn" label="3 problems" /></div>
      <div class="cell"><small>bare</small><StatusDot state="ok" bare label="online" /></div>
      <div class="cell"><small>large</small><StatusDot state="bad" large /></div>
    </Entry>

    <Entry name="StageBadge" text="The lifecycle stage of a package, with its flags.">
      {#each ['available', 'on', 'running'] as s (s)}<div class="cell"><small>{s}</small><StageBadge stage={s} /></div>{/each}
      <div class="cell"><small>flags</small><StageBadge stage="running" flags={['update']} /></div>
    </Entry>

    <Entry name="Banner" text="A line of advice above a page or a card.">
      {#each ['ok', 'info', 'warn', 'bad'] as t (t)}<div class="cell wide"><small>{t}</small><Banner tone={t}>This is a {t} banner.</Banner></div>{/each}
      <div class="cell wide"><small>with action</small><Banner tone="warn">Storage is locked.{#snippet action()}<Button size="sm">Unlock</Button>{/snippet}</Banner></div>
    </Entry>

    <Entry name="ErrorNote" text="The coded error: what, why, next step, guide.">
      <div class="cell wide"><small>full</small><ErrorNote error={{ code: 'disk.full', what: 'Could not write to tank', why: 'The pool has no free space.', next: 'hs pool status tank', guide: '' }} /></div>
      <div class="cell wide"><small>what only, dismissable</small><ErrorNote code="unknown.code" what="Something the web does not know" ondismiss={() => {}} /></div>
    </Entry>

    <Entry name="EmptyState" text="One sentence and the one action that creates the first object.">
      <div class="cell"><small>with action</small><EmptyState icon="folders" title="No shares yet" text="Create the first one.">{#snippet action()}<Button variant="primary">New share</Button>{/snippet}</EmptyState></div>
      <div class="cell"><small>info, no action</small><EmptyState tone="info" title="Nothing to show" /></div>
    </Entry>

    <Entry name="Skeleton" text="Grey blocks while a page loads.">
      <div class="cell" style="width:240px"><small>lines</small><Skeleton lines={4} /></div>
      <div class="cell" style="width:240px"><small>block</small><Skeleton height={80} /></div>
    </Entry>

    <Entry name="Progress" text="One bar. Never colour alone: the number or text is beside it.">
      <div class="cell" style="width:260px"><small>42 %</small><Progress value={42} total={100} label="Copying" /></div>
      <div class="cell" style="width:260px"><small>unknown total</small><Progress label="Waiting" /></div>
      {#each ['ok', 'warn', 'bad'] as t (t)}<div class="cell" style="width:260px"><small>{t}</small><Progress value={80} total={100} tone={t} label={t} text="{t}: 80 %" /></div>{/each}
      <div class="cell" style="width:260px"><small>sm</small><Progress value={3} total={4} size="sm" label="Small" /></div>
    </Entry>

    <Entry name="StepList" text="The steps of a job, a state word each.">
      <div class="cell"><small>list</small><StepList {steps} /></div>
      <div class="cell"><small>compact</small><StepList {steps} compact /></div>
    </Entry>

    <Entry name="Stepper" text="The steps of a flow, a number or mark and a word each.">
      <div class="cell"><small>row (done step goes back)</small><Stepper steps={['Image', 'Ports', 'Folders']} onselect={() => {}} /></div>
      <div class="cell"><small>states, vertical</small><Stepper vertical steps={steps.slice(0, 4)} /></div>
    </Entry>

    <Entry name="Wizard" text="One question per screen: progress, back, question, primary button.">
      <div class="cell wide box">
        <Wizard index={wiz} total={3} question="Which page?" help="Pick the one you need." primary="Next" steps={['Kind', 'Name', 'Done']} onnext={() => (wiz = (wiz + 1) % 3)} onback={() => (wiz = Math.max(0, wiz - 1))}>
          <ChoiceList options={[{ id: 'a', label: 'Shares', text: 'Folders on the network' }]} value="a" />
        </Wizard>
      </div>
    </Entry>

    <Entry name="ChoiceList" text="One question, one answer: radio rows.">
      <div class="cell" style="width:340px"><small>picked, recommended chip</small>
        <ChoiceList label="Layout" value={choice} onpick={(id) => (choice = id)} options={[{ id: 'a', label: 'Mirror', text: 'Two copies', recommended: true }, { id: 'b', label: 'Stripe', text: 'No safety' }]} /></div>
    </Entry>

    <Entry name="Card" text="The one card: header with actions, a body, optional dither.">
      <div class="cell"><small>title + actions</small><Card title="The CA">{#snippet actions()}<Button size="sm">Make</Button>{/snippet}Body text.</Card></div>
      <div class="cell"><small>no header</small><Card>A plain block.</Card></div>
      <div class="cell"><small>kicker, pad lg</small><Card title="Node" kicker="main" pad="lg">Roomy.</Card></div>
      <div class="cell"><small>dither</small><Card title="Summary" dither="top-right">Over the halftone.</Card></div>
    </Entry>

    <Entry name="Row" text="Children side by side, gap from the spacing tokens.">
      <div class="cell"><small>gap 2 / 6</small><Row gap="2"><Chip>a</Chip><Chip>b</Chip></Row><Row gap="6"><Chip>a</Chip><Chip>b</Chip></Row></div>
      <div class="cell" style="width:260px"><small>wrap, justify between</small><Row wrap justify="between"><Chip>one</Chip><Chip>two</Chip><Chip>three</Chip></Row></div>
    </Entry>

    <Entry name="Stack" text="Children one below the other.">
      <div class="cell"><small>gap 1 / stretch</small><Stack gap="1"><Chip>a</Chip><Chip>b</Chip></Stack></div>
      <div class="cell"><small>gap 6 / center</small><Stack gap="6" align="center"><Chip>a</Chip><Chip>b</Chip></Stack></div>
    </Entry>

    <Entry name="Muted" text="The one secondary text style.">
      <div class="cell"><small>span</small><Muted>12 GB free</Muted></div>
      <div class="cell"><small>as p</small><Muted as="p">No CA yet.</Muted></div>
    </Entry>

    <Entry name="Kv" text="Key-value cells for a drawer or a card.">
      <div class="cell" style="width:340px"><small>2 columns, empty = dash</small><Kv items={[{ k: 'Layout', v: 'raidz1' }, { k: 'Size', v: '4 TB' }, { k: 'Spare', v: '' }, { k: 'Count', v: 3 }]} /></div>
      <div class="cell" style="width:340px"><small>1 column</small><Kv cols={1} items={[{ k: 'Layout', v: 'mirror' }]} /></div>
    </Entry>

    <Entry name="Field" text="Label, hint, error and required marker; gives its id and aria to the control inside.">
      <div class="cell"><small>hint</small><Field label="Name" help="Lowercase letters"><TextInput bind:value={text} /></Field></div>
      <div class="cell"><small>required</small><Field label="Name" required><TextInput value="" /></Field></div>
      <div class="cell"><small>error</small><Field label="Name" error="Not allowed"><TextInput value="Bad Name" /></Field></div>
    </Entry>

    <Entry name="TextInput" text="Native input with the global look.">
      <div class="cell"><small>value</small><TextInput bind:value={text} ariaLabel="Name" /></div>
      <div class="cell"><small>placeholder</small><TextInput value="" placeholder="photos" ariaLabel="Name" /></div>
      <div class="cell"><small>disabled</small><TextInput value="locked" disabled ariaLabel="Name" /></div>
    </Entry>

    <Entry name="Textarea" text="Native textarea.">
      <div class="cell"><small>rows 3</small><Textarea bind:value={area} rows={3} ariaLabel="Note" /></div>
      <div class="cell"><small>disabled</small><Textarea value="locked" disabled ariaLabel="Note" /></div>
    </Entry>

    <Entry name="Select" text="Native select; options as data or children.">
      <div class="cell"><small>options as data</small><Select bind:value={sel} options={['zfs', 'ext4', 'xfs']} ariaLabel="Type" /></div>
      <div class="cell"><small>children</small><Select value="" ariaLabel="Pool"><option value="">Choose...</option><option value="a">tank</option></Select></div>
      <div class="cell"><small>disabled</small><Select value="zfs" options={['zfs']} disabled ariaLabel="Type" /></div>
    </Entry>

    <Entry name="Combobox" text="A custom trigger and a popover instead of a native select.">
      <div class="cell"><small>placeholder</small><Combobox bind:value={combo} options={[{ value: 'a', label: 'All' }, 'Urgent only', { value: 'x', label: 'Off', disabled: true }]} placeholder="Priority" /></div>
      <div class="cell"><small>disabled</small><Combobox value="" options={['a']} disabled /></div>
    </Entry>

    <Entry name="Segmented" text="Two to four short choices as joined segments; ChoiceList is the one with explanations.">
      <div class="cell"><small>with a count</small><Segmented value="all" label="Filter" options={[{ value: 'all', label: 'All', count: 4 }, { value: 'free', label: 'Free', count: 1 }]} /></div>
      <div class="cell"><small>with icons</small><Segmented value="a" label="Kind" options={[{ value: 'a', label: 'Folder', icon: 'folder' }, { value: 'b', label: 'Sensitive', icon: 'folder-lock' }]} /></div>
    </Entry>
    <Entry name="Checkbox" text="Native checkbox with a clickable label (forms).">
      <div class="cell"><small>checked + hint</small><Checkbox bind:checked label="Mount it into an instance" hint="Optional" /></div>
      <div class="cell"><small>unchecked</small><Checkbox checked={false} label="Off" /></div>
      <div class="cell"><small>disabled</small><Checkbox checked disabled label="Fixed" /></div>
    </Entry>

    <Entry name="Slider" text="Native range: accent-filled track, square thumb. oninput while dragging, onchange on release.">
      <div class="cell"><small>40 %</small><Slider bind:value={level} min={0} max={100} step={5} ariaLabel="Level" /></div>
      <div class="cell"><small>disabled</small><Slider value={70} disabled ariaLabel="Level" /></div>
    </Entry>
    <Entry name="Switch" text="A switch, or with box the checkbox for table cells. A disabled one shows its reason.">
      <div class="cell"><small>switch</small><Switch bind:checked={on} label="Backup" /></div>
      <div class="cell"><small>box</small><Switch box bind:checked={box} label="Select" /></div>
      <div class="cell"><small>disabled + reason</small><Switch box checked disabled reason="Email cannot carry a heartbeat" showReason /></div>
    </Entry>

    <Entry name="PageTabs" text="The tab row of a page.">
      <div class="cell wide"><small>tab {tab}</small><PageTabs tabs={[{ id: 'overview', label: 'Overview' }, { id: 'dns', label: 'DNS' }, { id: 'ports', label: 'Ports' }]} bind:tab /></div>
    </Entry>

    <Entry name="Menu" text="The More menu and row actions; a disabled item says why.">
      <div class="cell"><small>default</small><Menu items={menu} /></div>
      <div class="cell"><small>align start</small><Menu items={menu} align="start" label="Actions" /></div>
    </Entry>

    <Entry name="NetMap" text="The network map (issue 875): SVG nodes, canvas dots that follow the rate (none at zero). With the system setting 'reduce motion' the dots stop and a busy link is drawn thicker. Issue 876, without a mouse: Tab enters the map at one node, arrow keys move to the parent, first child and neighbours, Home and End to the ends, Enter or Space opens the detail popover (the first map below has a link for instances), Escape closes it and focus returns to the node. Each node is read with its kind, state and rates. The button above a map switches to the table with the same facts. Fixture graphs from netmap/fixtures.js.">
      <div class="cell wide"><small>small server, traffic</small><NetMap graph={SMALL} rates={SMALL_RATES} label="Fixture: small server" hrefFor={(r) => (r.kind === 'instance' ? '#/instances/' + r.id : '')} /></div>
      <div class="cell wide"><small>table view (the text alternative)</small><NetMap graph={SMALL} rates={SMALL_RATES} label="Fixture: small server" table hrefFor={(r) => (r.kind === 'instance' ? '#/instances/' + r.id : '')} /></div>
      <div class="cell wide"><small>no traffic (no dots)</small><NetMap graph={SMALL} label="Fixture: idle server" /></div>
      <div class="cell wide"><small>100 nodes (wrapped tiers)</small><NetMap graph={bigMap.graph} rates={bigMap.rates} label="Fixture: 100 nodes" /></div>
      <div class="cell wide"><small>empty graph</small><NetMap graph={[]} /></div>
    </Entry>

    <Entry name="NodePopover"text="Spike for the Network Map (issue 871): the detail popover of a node, behaviour from @ui-sdk/svelte, look from our tokens. Press Enter on the trigger, Tab inside, Escape closes and focus returns.">
      <div class="cell"><small>default</small><NodePopover label="gateway" title="Gateway 192.168.1.1"><Kv items={[{ k: 'Seen from here', v: '12 Mbit/s' }, { k: 'State', v: 'up' }]} /></NodePopover></div>
      <div class="cell"><small>near the edge (flips)</small><div style="text-align:right"><NodePopover label="br0" title="Bridge br0"><Kv items={[{ k: 'Ports', v: '4' }]} /></NodePopover></div></div>
    </Entry>

    <Entry name="Tooltip" text="The one tooltip element; a control asks for it with the tooltip prop of a Button. Hover or focus these.">
      <div class="cell"><small>on a button</small><Button tooltip="Shows the plan first">Hover me</Button></div>
      <div class="cell"><small>on text</small><Button variant="ghost" tooltip="A longer explanation that wraps onto more than one line when it has to, so the placement is visible.">Focus me</Button></div>
    </Entry>

    <Entry name="Toast" text="Short results and jobs that ask for input; mounted once in the shell.">
      <div class="cell"><small>kinds</small><Row>
        <Button onclick={() => toast({ kind: 'ok', title: 'Share created' })}>ok</Button>
        <Button onclick={() => toast({ kind: 'info', title: 'Scrub started', text: 'It runs in the background.' })}>info</Button>
        <Button onclick={() => toast({ kind: 'bad', title: 'Backup failed', ttl: 0 })}>bad, stays</Button>
        <Button onclick={() => toast({ key: 'gallery-ask', kind: 'ask', title: 'Install nextcloud needs an answer', href: '#', linkLabel: 'Open the job' })}>asks, link</Button>
      </Row></div>
    </Entry>

    <Entry name="Dialog" text="The base of every modal: focus trap, Escape, backdrop.">
      <div class="cell"><small>modal</small><Button onclick={() => (dialog = true)}>Open dialog</Button></div>
      {#if dialog}
        <Dialog title="Delete share" width="420px" dismiss onclose={() => (dialog = false)}>
          <div style="padding:16px"><p>Escape or a click on the backdrop closes it.</p><Button data-autofocus onclick={() => (dialog = false)}>Close</Button></div>
        </Dialog>
      {/if}
    </Entry>

    <Entry name="Drawer" text="The side drawer of a list page (400 px, full screen on a phone).">
      <div class="cell wide box">
        <Drawer title="tank" chip="zfs" state="ok" stateLabel="online" tabs={[{ id: 'info', label: 'Info' }, { id: 'snap', label: 'Snapshots' }]} bind:tab={drawerTab} onclose={() => {}}>
          <Kv items={[{ k: 'Size', v: '4 TB' }, { k: 'Tab', v: drawerTab }]} />
          {#snippet actions()}<Button size="sm">Scrub</Button>{/snippet}
        </Drawer>
      </div>
    </Entry>

    <Entry name="QuickLook" text="The drawer as an overlay above a list; the list stays usable behind it.">
      <div class="cell wide box" style="min-height:300px">
        <Button onclick={() => (quick = !quick)}>{quick ? 'Close' : 'Open'} quick look</Button>
        {#if quick}<QuickLook title="tank" chip="zfs" state="ok" stateLabel="online" href="#" onclose={() => (quick = false)}><Kv items={[{ k: 'Size', v: '4 TB' }]} /></QuickLook>{/if}
      </div>
    </Entry>

    <Entry name="Split" text="The list-and-drawer layout. Under 1100 px the drawer drops below, under 860 px it covers the page.">
      <div class="cell wide box">
        <Button onclick={() => (split = !split)}>{split ? 'Close' : 'Open'} drawer</Button>
        <Split open={split}>
          {#snippet list()}<p>The list.</p>{/snippet}
          {#snippet side()}<Drawer title="tank" onclose={() => (split = false)}><Kv items={[{ k: 'Size', v: '4 TB' }]} /></Drawer>{/snippet}
        </Split>
      </div>
    </Entry>

    <Entry name="StateCard" text="The card of a Group page: the state of one place.">
      {#each [['ok', 'online'], ['warn', '1 degraded'], ['bad', 'failed'], ['off', 'off']] as [s, l] (s)}
        <div class="cell"><small>{s}</small><StateCard title="Pools" state={s} label={l} line="3 pools, 12.4 TB used" href="#" /></div>
      {/each}
      <div class="cell"><small>with action</small><StateCard title="Backup" state="info" label="running" line="Nightly, 40 %" href="#" linkText="Open backup">{#snippet actions()}<Button size="sm">Stop</Button>{/snippet}</StateCard></div>
    </Entry>

    <Entry name="DangerZone" text="Destructive actions of an Object page; each opens a plan. Not run here.">
      <div class="cell" style="width:420px"><small>one enabled, one off with reason</small><DangerZone actions={danger} /></div>
    </Entry>

    <Entry name="Timeline" text="The body of a Feed page: entries by day, each day on the panel surface, filters, severity word, acknowledge.">
      <div class="cell wide"><small>entries</small><Timeline {entries} bind:values={timeFilters} filters={[{ key: 'level', label: 'Level', options: ['', 'info', 'warn', 'bad'] }]} onack={() => {}} onundo={() => {}} more onmore={() => {}} /></div>
      <div class="cell wide"><small>empty</small><Timeline entries={[]} emptyTitle="No events" empty="Nothing happened yet." /></div>
    </Entry>

    <Entry name="Logo" text="The Hobnix mark; follows the theme and the accent.">
      <div class="cell"><small>26 / 64</small><Row><Logo /><Logo size={64} /></Row></div>
    </Entry>

    <Entry from="shell" name="PageHeader" text="Breadcrumb, title, subtitle and the actions.">
      <div class="cell wide box"><PageHeader title="Disks" crumb="Storage" sub="Every disk of this server.">{#snippet actions()}<Button variant="primary" icon="plus">Add disks</Button>{/snippet}</PageHeader></div>
    </Entry>

    <Entry from="shell" name="PageState" text="Loading, error with and without old data, empty, content.">
      <div class="cell" style="width:260px"><small>loading</small><PageState loading /></div>
      <div class="cell" style="width:260px"><small>error, no data</small><PageState error="Could not read." retry={() => {}} /></div>
      <div class="cell" style="width:260px"><small>error, data kept</small><PageState error="Timed out" hasData age={120} retry={() => {}}>Old data stays.</PageState></div>
      <div class="cell" style="width:260px"><small>empty</small><PageState hasData empty emptyTitle="No instances yet" emptyText="Create the first one." /></div>
      <div class="cell" style="width:260px"><small>content</small><PageState hasData>The page.</PageState></div>
    </Entry>

    <Entry from="shell" name="Table" text="Declared columns, data rows, sort by header, empty text, loading; optional columns drop on a phone.">
      <div class="cell wide"><small>rows, selected</small><Table id="gallery" columns={cols} rows={rowsData} key="name" selected="data" onrow={() => {}} /></div>
      <div class="cell wide"><small>empty</small><Table columns={cols} rows={[]} empty="No pools." /></div>
      <div class="cell wide"><small>loading</small><Table columns={cols} rows={[]} loading /></div>
    </Entry>

    <Entry from="shell" name="UsageBar" text="Segmented bar of a fixed width; amber over 90 %.">
      <div class="cell"><small>40 %</small><UsageBar used={2e12} size={5e12} /></div>
      <div class="cell"><small>over 90 %</small><UsageBar used={4.6e12} size={5e12} /></div>
      <div class="cell"><small>unknown</small><UsageBar free="-" size={5e12} /></div>
      <div class="cell" style="width:260px"><small>block</small><UsageBar free={1e12} size={4e12} block /></div>
    </Entry>

    <Entry from="shell" name="Spark" text="A small dithered sparkline; turns amber at or over `hot`.">
      <div class="cell"><small>readings</small><Spark values={hist} /></div>
      <div class="cell"><small>hot 60</small><Spark values={hist} hot={60} /></div>
      <div class="cell"><small>too few</small><Spark values={[5]} /></div>
    </Entry>

    <Entry from="shell" name="LinkedObjects" text="Related objects with status, grouped by kind.">
      <div class="cell" style="width:340px"><small>items</small><LinkedObjects items={linked} /></div>
      <div class="cell" style="width:340px"><small>none</small><LinkedObjects items={[]} /></div>
    </Entry>

    <Entry from="shell" name="JobStrip" text="The running or last jobs of one object. Live: it reads the job records of this server.">
      <div class="cell" style="width:420px"><small>every job</small><JobStrip /></div>
      <div class="cell" style="width:420px"><small>no job matches</small><JobStrip match={() => false} /></div>
    </Entry>

    <Entry from="shell" name="Inbox" text="The bell of the top bar. Live: it reads the problems and notifications of this server.">
      <div class="cell"><small>bell</small><Inbox /></div>
    </Entry>
  </div>
</div>
