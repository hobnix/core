<script>
  import Chip from '../ui/Chip.svelte';
  import { tip } from '../ui/tooltip.svelte.js';
  import { poll, rows, refresh } from '../data.svelte.js';
  import { bytes, ago } from '../format.js';
  import { clock } from '../jobrecords.js';
  import { openPlan, openCreate, openJob, ui } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { backupPending, backupFailed } from './rows.js';
  import Button from '../ui/Button.svelte';
  import RestoreFiles from '../forms/backup/RestoreFiles.svelte';
  import SetupDisk from '../forms/backup/SetupDisk.svelte';
  import OffsiteTarget from '../forms/backup/OffsiteTarget.svelte';
  import { get, prefetchPlan } from '../api.js';
  import { sharesPath } from '../pools.svelte.js';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import StatusDot from '../ui/StatusDot.svelte';
  import Switch from '../ui/Switch.svelte';
  import Banner from '../ui/Banner.svelte';
  import EmptyState from '../ui/EmptyState.svelte';
  import { Card, Row, Muted, TextInput } from '../ui';
  import { P } from '../paths.js';
  import { link } from './instances/ct.js';
  import { restoreDrill, instanceDrill } from './backup-drill.js';

  let { deck } = $props();
  // locked storage: the share and instance rows cannot be read (and their switches would act on nothing), so they are left out
  const locked = $derived(!!deck?.data?.locked);

  const st = poll('/api/sys/backup/state', 15000);
  const ov = poll('/api/sys/backup/overview', 30000);
  const snS = poll('/api/sys/backup/snapshots?tag=shares', 30000, 'backup-state');
  const snH = poll('/api/sys/backup/snapshots?tag=host', 30000, 'backup-state');

  // key, value rows
  const s = $derived(Object.fromEntries(rows(st).map((r) => [r[0], r[1] ?? ''])));
  const configured = $derived(s.configured === 'yes');
  // kind (shares|sensitive|ct|always), name, on|off, bytes or -
  const items = $derived(rows(ov).map((r) => ({ kind: r[0], name: r[1], on: r[2] === 'on', size: r[3] })).filter((i) => !locked || i.kind === 'always'));
  // id, time (UTC), tags: shares and host together, newest first
  const points = $derived([...rows(snS), ...rows(snH)].map((r) => ({ id: r[0], time: r[1], tags: r[2] })).sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0)));
  const snapsLoaded = $derived(snS.loaded && snH.loaded);
  const snapsError = $derived(snS.error && snH.error);

  // find a file in every snapshot: snapshot, time, path, type, bytes
  let q = $state('');
  let finding = $state(false);
  let found = $state(null);
  let findError = $state('');
  const findOk = $derived(/^[^\x00-\x1f/\\*?[\]]{2,80}$/.test(q.trim()));
  async function find() {
    if (!findOk || finding) return;
    finding = true; findError = ''; found = null;
    try {
      const r = await get(`/api/sys/backup/find/${encodeURIComponent(q.trim())}`);
      found = (r?.rows ?? []).map((x) => ({ snap: x[0], time: x[1], path: x[2], type: x[3], size: Number(x[4]) }));
    } catch (e) { findError = e.message || 'The search failed (it can take a while on a big backup).'; }
    finally { finding = false; }
  }

  const age = (v) => (v && !isNaN(v) ? ago(Math.max(0, Math.floor(Date.now() / 1000) - Number(v))) : '');
  // "today 04:00", "tomorrow 04:00", "Sat, 10 Oct 04:00"
  const when = (v) => {
    if (!v || isNaN(v)) return '–';
    const d = new Date(Number(v) * 1000);
    const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const diff = Math.round((day(d) - day(new Date())) / 86400000);
    const hm = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
    const lab = diff === 0 ? 'today' : diff === 1 ? 'tomorrow' : diff === -1 ? 'yesterday' : d.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
    return `${lab} ${hm}`;
  };
  const dot = (v) => (v === 'ok' || v === 'yes' ? 'ok' : v ? 'bad' : 'off');
  const head = $derived(!st.loaded ? 'Loading…' : !configured ? 'No backup set up'
    : s.status === 'failed' ? 'Last backup failed' : s.last_ok ? 'Last backup ok' : 'No backup yet');
  const sub = $derived([s.last_ok ? when(s.last_ok) : '', s.status === 'failed' && s.last_try ? `last try ${age(s.last_try)}` : '', s.next ? `next ${when(s.next)}` : ''].filter(Boolean).join(' · '));
  const facts = $derived([
    ['Backup disk', `${s.disk === 'present' ? 'present' : s.disk || '–'}${s.vault === 'closed' ? ' · vault closed' : ''}`, s.disk === 'present' ? 'ok' : 'warn'],
    ['Repository', `${s.repo_size || '–'}${s.used_pct ? ` · disk ${s.used_pct} % used` : ''}`, s.repo_size ? 'ok' : 'off'],
    ['Restore points', s.snapshots || '–', 'off'],
    ['Off-site copy', s.offsite ? `${s.offsite}${s.offsite_ok ? (s.offsite_ok === 'ok' ? ' · ok' : ' · failed') : ''}` : 'not set', s.offsite ? dot(s.offsite_ok) : 'off'],
    ['Restore drill', ...restoreDrill(s, age)],
    ['Last try', s.last_try ? `${when(s.last_try)} · ${s.status === 'failed' ? 'failed' : 'ok'}` : '–', s.last_try ? (s.status === 'failed' ? 'bad' : 'ok') : 'off'],
    ...(instanceDrill(s, age) ? [['Instance drill', ...instanceDrill(s, age)]] : []),
  ]);
  // actions that need the backup disk: say why one is not possible
  const why = $derived(!st.loaded ? 'Loading…' : !configured ? 'The backup is not set up yet' : s.vault === 'closed' ? 'The vault is closed: unlock it first' : s.disk !== 'present' ? 'The backup disk is not plugged in' : '');
  const browsing = $derived(s.browse === 'on');
  const runningNow = $derived(rowstate.activeJob('backup', ['now']));   // a backup job runs: the button is busy, its tooltip names it and a click shows the job
  const tipWhy = (t) => (why ? `${t} (${why})` : t);
  const headDot = $derived(!configured ? 'off' : s.status === 'failed' ? 'bad' : s.last_ok ? 'ok' : 'warn');
  const itemLink = (i) => (i.kind === 'ct' ? link(P.appsGroup, 'instances', i.name) : link(sharesPath(), 'shares', i.name));
  const toggle = (i) => openPlan('backup', ['toggle', '--name', i.name, '--kind', i.kind, '--to', i.on ? 'off' : 'on'], `${i.on ? 'Leave out of' : 'Put into'} the backup: ${i.name}`);
  const kindName = { shares: 'share', sensitive: 'sensitive share', ct: 'instance', always: 'always' };
  const kindIcon = { shares: 'folder', sensitive: 'folder-lock', ct: 'cube', always: 'desktop-tower' };

  const columns = [
    { key: 'name', label: 'Item' }, { key: 'kind', label: 'Kind', optional: true, value: (i) => kindName[i.kind] ?? i.kind },
    { key: 'size', label: 'Size', sort: 'num', optional: true, value: (i) => Number(i.size) }, { key: 'on', label: 'In the backup', value: (i) => (i.kind === 'always' ? 'always' : i.on ? 'on' : 'off') },
  ];
  const pointCols = [
    { key: 'id', label: 'ID' }, { key: 'time', label: 'Time (UTC)' }, { key: 'tags', label: 'Tags', value: (p) => p.tags.split(',').join(' · ') },
  ];
  const foundCols = [
    { key: 'snap', label: 'Restore point' }, { key: 'time', label: 'Time (UTC)' }, { key: 'path', label: 'Path' }, { key: 'size', label: 'Size', sort: 'num', value: (f) => (f.type === 'file' ? f.size : NaN) },
  ];
</script>

<PageHeader title="Backup" sub="restic on the backup disk · 7 daily / 4 weekly / 6 monthly · the one place that decides what is in the backup">
  {#snippet actions()}
    <Button need="admin" icon="seal-check" busy={rowstate.pending('backup', ['verify'])} busyLabel="Verifying…" disabled={!!why} onpointerenter={() => prefetchPlan('backup', ['verify'])} onfocus={() => prefetchPlan('backup', ['verify'])} tooltip={tipWhy('Read part of the stored data and check it')} onclick={() => openPlan('backup', ['verify'], 'Verify the backup')}>Verify</Button>
    <Button need="admin" icon="broom" busy={rowstate.pending('backup', ['prune'])} busyLabel="Freeing space…" disabled={!!why} onpointerenter={() => prefetchPlan('backup', ['prune'])} onfocus={() => prefetchPlan('backup', ['prune'])} tooltip={tipWhy('Give space back: delete leftovers of a failed run, apply the retention, prune')} onclick={() => openPlan('backup', ['prune'], 'Free space on the backup disk')}>Free space</Button>
    <Button need="admin" icon="first-aid-kit" busy={rowstate.pending('backup', ['drill'])} disabled={!!why} onpointerenter={() => prefetchPlan('backup', ['drill'])} onfocus={() => prefetchPlan('backup', ['drill'])} tooltip={tipWhy('Restore a few random files and compare them with the originals')} onclick={() => openPlan('backup', ['drill'], 'Restore drill')}>Restore drill</Button>
    <Button need="admin" icon="folder-open" busy={(rowstate.pending('backup', ['browse', '--to', 'off']) || rowstate.pending('backup', ['browse', '--to', 'on']))} disabled={!!why && !browsing} tooltip={browsing ? 'Stop showing the backup as a read-only share' : tipWhy('Show the whole backup as a read-only share')} onclick={() => openPlan('backup', ['browse', '--to', browsing ? 'off' : 'on'], browsing ? 'Stop browsing the backup' : 'Browse the backup')}>{browsing ? 'Stop browsing' : 'Browse'}</Button>
    <Button need="admin" variant="primary" icon="cloud-arrow-up" busy={rowstate.pending('backup', ['now'])} busyLabel="Backing up…" disabled={!!why} onpointerenter={() => prefetchPlan('backup', ['now'])} onfocus={() => prefetchPlan('backup', ['now'])} tooltip={runningNow ? `Backup running since ${clock(runningNow.started)}` : tipWhy('Back up right now')} onbusyclick={() => runningNow && openJob(runningNow.id)} onclick={() => openPlan('backup', ['now'], 'Back up now')}>Back up now</Button>
  {/snippet}
</PageHeader>
{#if backupFailed(rowstate.failed) && !backupPending(rowstate.pending)}{@const bf = backupFailed(rowstate.failed)}<ErrorNote error={bf.error} ondismiss={() => rowstate.dismiss(bf.id)} />{/if}

<PageState loading={!st.loaded} error={st.error?.message} hasData={st.data != null} retry={() => refresh(['/api/sys/backup/state'])}>
  {#if !configured}
    <Card>
      <EmptyState icon="cloud-slash" title="No backup set up" text="Nothing is backed up yet. Make a free disk the backup disk: it is erased, the plan shows what happens first, and the backup password is made inside the vault.">
        {#snippet action()}<Button need="admin" variant="primary" tooltip={'Make a free disk the backup disk (it is erased)'} onclick={() => openCreate(SetupDisk)}><i class="ph ph-hard-drive"></i>Set up backup disk…</Button>{/snippet}
      </EmptyState>
    </Card>
  {:else}
    <Card>
     <div class="status">
      <div class="lead">
        <StatusDot state={headDot} large bare label={head} />
        <div><div class="big">{head}</div>{#if sub}<div class="small">{sub}</div>{/if}</div>
      </div>
      <div class="facts">
        {#each facts as f}
          <div class="fact"><StatusDot state={f[2]} bare label={f[1]} /><span class="fl">{f[0]}</span><span class="fv">{f[1]}</span></div>
        {/each}
      </div>
      <div class="offs">
        {#if s.offsite}
          <Button need="admin" size="sm" icon="arrows-clockwise" busy={rowstate.pending('backup', ['offsite-now'])} disabled={!!why} tooltip={tipWhy('Copy the new backups to the off-site repository now')} onclick={() => openPlan('backup', ['offsite-now'], 'Copy to the off-site repository')}>Copy off-site now</Button>
          <Button need="admin" variant="ghost" size="sm" icon="cloud-slash" busy={rowstate.pending('backup', ['offsite-off'])} tooltip={'Stop copying off site (what is there stays)'} onclick={() => openPlan('backup', ['offsite-off'], 'Switch the off-site copy off')}>Switch off</Button>
        {:else}
          <Muted>Off-site copy: not set.</Muted>
        {/if}
        <Button need="admin" size="sm" icon="cloud-arrow-up" disabled={!!why} tooltip={tipWhy('Choose where the off-site copy goes: S3, REST server, SFTP or a folder')} onclick={() => openCreate(OffsiteTarget)}>{s.offsite ? 'Change target…' : 'Set up off-site copy…'}</Button>
      </div>
      {#if ui.offsitePass}
        <Banner tone="warn" icon="key">
          The new off-site repository has its OWN password. Write it down now; it is shown only once and without it that copy cannot be opened:
          <span class="mono">{ui.offsitePass}</span>
          {#snippet action()}<Button size="sm" onclick={() => { ui.offsitePass = ''; }}>I wrote it down</Button>{/snippet}
        </Banner>
      {/if}
     </div>
    </Card>

    <Card title="What is in the backup">
      <Muted as="p">the switch here is the only place that decides it; the host files are always in</Muted>
      {#if locked}<Banner tone="warn">The storage is locked: the shares and instances are not listed until it is unlocked.</Banner>{/if}
      <Table id="backup-items" {columns} rows={items} loading={!ov.loaded} empty={ov.error ? 'This could not be read (is the backup disk there?).' : 'Nothing listed.'}>
        {#snippet cell(i, col)}
          {#if col.key === 'name'}<Row gap="2"><Muted><i class="ph ph-{kindIcon[i.kind] ?? 'folder'}"></i></Muted>{#if i.kind === 'always'}{i.name}{:else}<a {...itemLink(i)} use:tip={i.kind === 'ct' ? 'Open the instance' : 'Open the share'}>{i.name}</a>{/if}</Row>
          {:else if col.key === 'kind'}<Muted>{kindName[i.kind] ?? i.kind}</Muted>
          {:else if col.key === 'size'}{i.size && i.size !== '-' && !isNaN(i.size) ? bytes(Number(i.size)) : '–'}
          {:else if i.kind === 'always'}<Chip tone="accent">always</Chip>
          {:else}<Row gap="3"><Switch bind:checked={() => i.on, () => toggle(i)} label="{i.name} in the backup" /><Muted>{i.on ? 'on' : 'off'}</Muted></Row>{/if}
        {/snippet}
      </Table>
    </Card>

    <Card title="Restore points">
      {#snippet actions()}<Button need="admin" size="sm" tooltip={'Bring files back into the share restored; originals stay'} onclick={() => openCreate(RestoreFiles)}><i class="ph ph-arrow-counter-clockwise"></i>Restore files…</Button>{/snippet}
      {#if s.snapshots}<Muted as="p">{s.snapshots} in the repository</Muted>{/if}
      <Table id="backup-points" columns={pointCols} rows={points} loading={!snapsLoaded}
             empty={snapsError ? 'The restore points could not be read (backup disk missing or storage locked).' : 'No restore points yet.'}>
        {#snippet cell(p, col)}
          {#if col.key === 'id'}<span class="mono">{p.id}</span>
          {:else if col.key === 'time'}{p.time}
          {:else}<Muted>{p.tags.split(',').join(' · ')}</Muted>{/if}
        {/snippet}
      </Table>
    </Card>

    {#if ui.role === 'admin'}<Card title="Find a file">
      <Muted as="p">in every restore point</Muted>
      <form class="findrow" onsubmit={(e) => { e.preventDefault(); find(); }}>
        <TextInput bind:value={q} placeholder="Part of a file name, e.g. Rechnung" maxlength={80} autocomplete="off" spellcheck={false} ariaLabel="Part of a file name" />
        <Button type="submit" icon="magnifying-glass" disabled={!findOk} busy={finding} busyLabel="Searching…" tooltip={!findOk ? 'Type at least part of a file name first' : 'Look for this name in all backups'}>Find</Button>
      </form>
      {#if findError}<Muted as="p">{findError}</Muted>{/if}
      {#if found}
        <Table id="backup-found" columns={foundCols} rows={found} empty="Nothing found.">
          {#snippet cell(f, col)}
            {#if col.key === 'snap'}<span class="mono">{f.snap}</span>
            {:else if col.key === 'time'}{f.time}
            {:else if col.key === 'path'}<Muted style="overflow-wrap:anywhere">{f.path}{f.type === 'dir' ? '/' : ''}</Muted>
            {:else}{f.type === 'file' ? bytes(f.size) : ''}{/if}
          {/snippet}
        </Table>
        {#if found.length >= 200}<Muted as="p">Only the first 200 hits are shown: use a longer word.</Muted>{/if}
        <Muted as="p">To bring a file back: Restore files… above, with the path and the restore point.</Muted>
      {/if}
    </Card>{/if}
  {/if}
</PageState>

<style>
  .findrow { display: flex; gap: 8px; margin: 8px 0; }
  .findrow :global(.input) { flex: 1; min-width: 0; }
  .status { display: flex; flex-wrap: wrap; align-items: center; gap: 24px 28px; }
  .lead { flex: 1 1 260px; display: flex; align-items: center; gap: 14px; }
  .big { font-size: 20px; font-weight: 600; letter-spacing: -0.02em; }
  .small { font-size: 13px; color: var(--fg-3); }
  .offs { flex: 1 1 100%; display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
  .facts { flex: 2 1 460px; display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); column-gap: 28px; }
  .fact { position: relative; display: flex; align-items: center; gap: 8px; padding: 6px 0; border-bottom: 1px solid var(--line); }
  .fl { width: 100px; flex: none; color: var(--fg-3); }
  .fv { flex: 1; min-width: 0; }
  .mono { font-size: 12px; }
</style>
