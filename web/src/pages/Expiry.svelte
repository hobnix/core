<script>
  import { P } from '../paths.js';
  import Chip from '../ui/Chip.svelte';
  import { tip } from '../ui/tooltip.svelte.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { openCreate, openPlan } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { expiryFailed } from './rows.js';
  import Button from '../ui/Button.svelte';
  import ExpiryForm from '../forms/ops/ExpiryForm.svelte';
  import Table from '../shell/Table.svelte';
  import { go } from '../route.svelte.js';
  import { Card, Stack, Row, Muted, Progress } from '../ui';

  // days left sorts as a number (an invalid date has none and goes last)
  const columns = [
    { key: 'name', label: 'What' },
    { key: 'date', label: 'Expires' },
    { key: 'days', label: 'Left', sort: 'num', width: '200px' },
    { key: 'note', label: 'Note' },
    { key: 'rm', label: '', sort: false },
  ];

  const ex = poll('/api/sys/expiry/list', 10000);

  // name, date (ISO), days left or "-", state (ok|soon|due|expired|invalid), how to renew
  const items = $derived(rows(ex).map((r) => {
    const d = r[2] === undefined || r[2] === '-' || isNaN(r[2]) ? null : Number(r[2]);
    return { name: r[0], date: r[1], days: d, state: r[3], note: r[4] ?? '' };
  }));
  // The certificates, read only (the Certificates page under Identity owns them): key, value rows of `sys dc state`; no domain controller = nothing to show
  const dc = poll('/api/sys/dc/state', 30000);
  const c = $derived(Object.fromEntries(rows(dc).map((r) => [r[0], r[1] ?? ''])));
  const cDays = $derived(c.days_left !== undefined && c.days_left !== '' && !isNaN(c.days_left) ? Number(c.days_left) : null);
  const certs = $derived([
    ...(c.ca === 'yes' && c.ca_until ? [{ what: 'CA of this setup', until: c.ca_until, days: null }] : []),
    ...(c.cert === 'ok' ? [{ what: `Certificate of ${c.dc && c.dc !== '-' ? c.dc : 'the domain controller'}`, until: c.valid_until, days: cDays }] : []),
  ]);
  const warn = (i) => i.state !== 'ok';
  // The bar shows the time left on a one-year scale (the list holds no start date).
  const pct = (i) => (i.days === null ? 0 : Math.min(100, Math.max(i.days <= 0 ? 0 : 3, Math.round((i.days / 365) * 100))));
  const left = (i) => (i.days === null ? 'invalid' : i.days < 0 ? `${-i.days} d ago` : `${i.days} d`);
  const tone = (i) => (warn(i) ? 'warn' : 'info');
</script>

<Stack gap="4">
  <PageHeader title="Expiry dates" crumb="Protection" sub="The health check warns 30 and 7 days before.">
    {#snippet actions()}<Button need="admin" variant="primary" tooltip={'Write down something that runs out'} onclick={() => openCreate(ExpiryForm)}><i class="ph ph-plus"></i>Add</Button>{/snippet}
  </PageHeader>

  <Card>
    <Table id="expiry" {columns} rows={items} key="name" loading={!ex.loaded} empty={ex.error ? 'The list could not be read.' : 'Nothing is entered yet. On the server: hs expiry add <name> <YYYY-MM-DD>.'}>
      {#snippet cell(i, col)}
        {#if col.key === 'name'}{i.name}{#if expiryFailed(i.name, rowstate.failed) && !rowstate.pending('expiry', ['remove', i.name])}{@const ef = expiryFailed(i.name, rowstate.failed)} <span use:tip={ef.error.what}><Chip tone="bad">failed</Chip></span> <Button size="sm" variant="ghost" onclick={() => rowstate.dismiss(ef.id)}>Dismiss</Button>{/if}
        {:else if col.key === 'date'}<Muted style="white-space:nowrap">{i.date}</Muted>
        {:else if col.key === 'days'}<Progress value={pct(i)} total={100} tone={tone(i)} size="sm" label="Time left on {i.name}" text={left(i)} />
        {:else if col.key === 'note'}<Muted>{i.note}</Muted>
        {:else}<Button need="admin" variant="ghost" class="btn-icon expiry-rm" icon="x" busy={rowstate.pending('expiry', ['remove', i.name])} aria-label="Remove {i.name}" tooltip={`Remove ${i.name} from the list`} onclick={() => openPlan('expiry', ['remove', i.name], 'Remove ' + i.name)}></Button>{/if}
      {/snippet}
    </Table>
  </Card>

  {#if certs.length}
    <Card title="Certificates">
      {#snippet actions()}<Button variant="ghost" size="sm" tooltip={'Open the certificates page'} onclick={() => go(P.certificates)}>Manage<i class="ph ph-arrow-right"></i></Button>{/snippet}
      {#each certs as k}
        <Row gap="3" justify="between"><span>{k.what}</span>
          <Row gap="3"><Muted style="white-space:nowrap">{k.until}</Muted>{#if k.days !== null}<Muted style="white-space:nowrap">{k.days < 0 ? `${-k.days} d ago` : `${k.days} d`}</Muted>{/if}</Row></Row>
      {/each}
    </Card>
  {/if}
</Stack>

<style>
  :global(.btn.expiry-rm) { width: 26px; height: 26px; }
</style>
