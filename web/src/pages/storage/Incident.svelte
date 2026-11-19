<script>
  // Storage > Incident: a degraded pool, a missing pool disk or a failing disk, step by step (hobnix/server#255). Everything comes from
  // `hs sys incident state` (scripts/storage-incident.sh --state); the page changes nothing by itself. Pausing the writing apps is a plan
  // (area `incident`); the replace is the existing Replace form of the pools (plan, typed disk name, job), so the destructive step is the same one.
  import PageHeader from '../../shell/PageHeader.svelte';
  import PageState from '../../shell/PageState.svelte';
  import Table from '../../shell/Table.svelte';
  import { StatusDot, Banner, Chip, Stepper, Card, Row, Stack, Muted, Progress } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { go } from '../../route.svelte.js';
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import ReplaceMember from '../../forms/storage/ReplaceMember.svelte';

  let { deck } = $props();
  const locked = $derived(!!deck?.data?.locked);

  const st = poll('/api/sys/incident/state', 10000);
  const lines = $derived(rows(st));
  const of = (tag) => lines.filter((r) => r[0] === tag);
  const none = $derived(st.loaded && (lines.length === 0 || lines[0][0] === 'ok'));
  const incidents = $derived(of('incident').map((r) => ({ id: r[1], pool: r[2], kind: r[3], severity: r[4], text: r[5] })));
  const members = $derived(of('member').map((r) => ({ pool: r[1], name: r[2], state: r[3], group: r[4], disk: r[5], why: r[6] })));
  const target = $derived(of('target').map((r) => ({ pool: r[1], member: r[2], dev: r[3], disk: r[4] }))[0]);
  const shares = $derived(of('share').map((r) => ({ pool: r[1], name: r[2], path: r[3], impact: r[4] })));
  const apps = $derived(of('app').map((r) => ({ pool: r[1], name: r[2], state: r[3], via: r[4], writes: r[5] === 'yes' })));
  const progress = $derived(of('progress').map((r) => ({ pool: r[1], kind: r[2], pct: r[3] === '-' ? null : Number(r[3]), text: r[4] })));
  const paused = $derived(of('paused')[0]?.[1] === 'yes' ? of('paused')[0][2] : '');
  const free = $derived(of('free'));
  const steps = $derived(of('step').map((r) => ({ n: r[1], state: r[2], title: r[3] })));
  const next = $derived(of('next')[0]);
  const worst = $derived(incidents.some((i) => i.severity === 'error') ? 'bad' : 'warn');
  const writers = $derived(apps.filter((a) => a.writes && a.state === 'RUNNING'));
  const running = $derived(progress.length > 0);
  const snap = $derived(/^(data|parity)-\d+$/.test(target?.member ?? ''));

  const shareCols = [{ key: 'name', label: 'Share' }, { key: 'path', label: 'Path', optional: true }, { key: 'impact', label: 'State' }];
  const appCols = [{ key: 'name', label: 'App' }, { key: 'state', label: 'State' }, { key: 'via', label: 'Uses' }];
  const replace = () => openCreate(ReplaceMember, { pool: target.pool, member: target.member, snap });
</script>

<PageHeader title="Incident" crumb="Storage" sub="A degraded pool or a failing disk: what happened, what it touches, the next safe step.">
  {#snippet actions()}
    <Button tooltip={'Back to the pools'} onclick={() => go('/storage/pools')}><i class="ph ph-cylinder"></i>Pools</Button>
  {/snippet}
</PageHeader>

<PageState loading={!st.loaded} hasData={st.loaded} empty={none} emptyIcon="shield-check" emptyTitle="No storage incident"
           emptyText="Every pool and every disk looks fine. This page opens by itself in the alert when that changes.">
  <Stack gap="4">
    {#each incidents as i (i.id)}
      <Banner tone={i.severity === 'error' ? 'bad' : 'warn'}>{i.text}</Banner>
    {/each}

    <Card title="Steps">
      {#snippet actions()}{#if running}<Chip>replacement running</Chip>{/if}{/snippet}
      <Stepper vertical steps={steps.map((s) => ({ label: s.title, state: s.state === 'done' ? 'done' : s.state === 'now' ? 'current' : 'todo', note: s.state === 'optional' ? 'optional' : '' }))} />
      {#if next}<p><b>Next safe step:</b> {next[2]}</p>{/if}
      <Row gap="2" wrap>
        <Button variant="primary" icon="swap" disabled={locked || !target || running || !free.length} busy={rowstate.active('pool', [target?.pool ?? '']).some((k) => k.split(' ')[2] === 'replace')}
          tooltip={running ? 'A replacement is already running' : !free.length ? 'Plug in a new disk that is at least as large first' : 'Pick the new disk, see the plan, type the disk name'} onclick={replace}>Replace the disk…</Button>
        {#if paused}
          <Button icon="play" tooltip={'Let the paused apps run again'} onclick={() => openPlan('incident', ['resume'], 'Resume apps')}>Resume apps</Button>
        {:else}
          <Button icon="pause" disabled={!writers.length} tooltip={writers.length ? 'Freeze the apps that write to an affected share (shows the plan first)' : 'No running app writes to an affected share'}
            onclick={() => openPlan('incident', ['pause'], 'Pause apps')}>Pause writing apps</Button>
        {/if}
      </Row>
      {#if !free.length && !running}<Muted as="p">No free disk that is large enough was found yet. Plug in the new disk; this page notices it.</Muted>{/if}
    </Card>

    {#each progress as p}
      <Card title={`${p.kind === 'resilver' ? 'Resilver' : 'Rebuild'} of ${p.pool}`}>
        {#snippet actions()}{#if p.pct != null}<Muted>{p.pct} %</Muted>{/if}{/snippet}
        {#if p.pct != null}<Progress value={p.pct} total={100} label={`${p.kind === 'resilver' ? 'Resilver' : 'Rebuild'} of ${p.pool}`} text="" />{/if}
        <Muted as="p">{p.text}. The pool stays usable; do not pull or unplug any disk until it is done.</Muted>
      </Card>
    {/each}

    {#if members.length}
      <Card title={`The disk${members.length === 1 ? '' : 's'}`}>
        {#each members as m (m.pool + m.name)}
          <Row gap="2" wrap><StatusDot state={m.state === 'ONLINE' ? 'warn' : 'bad'} label={`${m.name} in ${m.pool}: ${m.state.toLowerCase()}`} /><Muted>{m.disk !== '-' ? m.disk : ''}{m.why !== '-' ? ` · SMART: ${m.why}` : ''}</Muted></Row>
        {/each}
        {#if target}
          <Muted as="p">{target.dev === '-' ? `${target.member} is gone: nothing to pull. Plug in its replacement.`
            : `To pull: ${target.disk} (${target.dev}). Check the serial number on the label; never go by the device letter alone.`}</Muted>
        {/if}
      </Card>
    {/if}

    {#if shares.length}
      <Card title="Affected shares">
        <Table id="incident-shares" columns={shareCols} rows={shares} key="name" compact empty="None.">
          {#snippet cell(r, col)}
            {#if col.key === 'name'}{r.name}
            {:else if col.key === 'path'}<code>{r.path}</code>
            {:else}<StatusDot state={r.impact === 'unavailable' ? 'bad' : 'warn'} label={r.impact === 'unavailable' ? 'files not reachable' : 'readable, no redundancy'} />{/if}
          {/snippet}
        </Table>
      </Card>
    {/if}

    {#if apps.length}
      <Card title="Affected apps">
        {#snippet actions()}{#if paused}<Muted>paused by you: {paused}</Muted>{/if}{/snippet}
        <Table id="incident-apps" columns={appCols} rows={apps} key="name" compact empty="None.">
          {#snippet cell(r, col)}
            {#if col.key === 'name'}{r.name}
            {:else if col.key === 'state'}<StatusDot state={r.state === 'RUNNING' ? 'ok' : 'off'} label={r.state.toLowerCase()} />
            {:else}{r.via === 'pool' ? 'lives on this pool' : `share ${r.via}`}{r.writes ? ' (writes)' : ''}{/if}
          {/snippet}
        </Table>
        <Muted as="p">Pausing is only a suggestion: nothing is stopped unless you press the button. A paused app keeps its memory and carries on after Resume.</Muted>
      </Card>
    {/if}
  </Stack>
</PageState>
