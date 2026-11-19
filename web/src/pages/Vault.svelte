<script>
  import { poll, rows } from '../data.svelte.js';
  import { bytes } from '../format.js';
  import { openPlan } from '../ui.svelte.js';
  import { rowstate } from '../rowstate.svelte.js';
  import ErrorNote from '../ui/ErrorNote.svelte';
  import { vaultFailed } from './rows.js';
  import Button from '../ui/Button.svelte';
  import { go } from '../route.svelte.js';
  import Table from '../shell/Table.svelte';
  import UsageBar from '../shell/UsageBar.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import { StatusDot, Banner, Card, Stack, Muted } from '../ui/index.js';

  let { deck } = $props();
  const list = poll('/api/sys/vault/list', 30000, 'vault-list');
  const status = poll('/api/sys/status', 15000, 'status');
  const usage = poll('/api/sys/vault/usage', 30000, 'vault-usage');
  const uses = poll('/api/sys/vault/uses', 60000, 'vault-uses');

  // `sys vault usage`: key/value lines (state, device, size, used, free in bytes, header-backup-days); `sys vault uses`: item name, who uses it
  const u = $derived(Object.fromEntries(rows(usage).map((r) => [r[0], r[1]])));
  const usedBy = $derived(Object.fromEntries(rows(uses).map((r) => [r[0], r[1]])));
  const by = (name) => {
    const v = usedBy[name.replace(/ \(.*$/, '')];
    return v && v !== '-' ? v : '–';
  };
  const size = $derived(Number(u.size));
  const used = $derived(Number(u.used));
  const hasUsed = $derived(u.state === 'open' && u.used != null && size > 0);

  // name, kind (secret|folder), state (in vault|closed|not moved|not mounted|-)
  const items = $derived(rows(list).map((r) => ({ name: r[0], kind: r[1], state: r[2] })));
  const locked = $derived(!!deck?.data?.locked || rows(status).some((r) => r[0] === 'encryption' && r[1] === 'locked'));
  const closed = $derived(items.some((i) => i.state === 'closed'));
  const dot = (s) => (s === 'in vault' ? 'ok' : s === 'closed' || s === '-' ? 'off' : 'warn');
  const n = $derived(items.length);
  const title = $derived(!list.loaded ? 'Loading…' : list.error && !n ? (locked ? 'Locked · items unavailable' : 'The vault could not be read') : closed || locked ? 'Locked · items unavailable' : `Open · ${n} item${n === 1 ? '' : 's'}`);
  const vstate = $derived(!list.loaded ? 'off' : closed || locked || (list.error && !n) ? 'warn' : 'ok');

  const columns = [
    { key: 'name', label: 'Item' }, { key: 'kind', label: 'Kind', optional: true }, { key: 'by', label: 'Used by', value: (i) => by(i.name) }, { key: 'state', label: 'State' },
  ];
</script>

<PageHeader title="Vault" crumb="Storage" sub="Secrets for the server's own services, in a LUKS partition of their own.">
  {#snippet actions()}
    <Button icon="floppy-disk" busy={rowstate.pending('secrets', ['header-backup'])} disabled={u.state !== 'open'} tooltip={'Save the LUKS header outside the vault'} onclick={() => openPlan('secrets', ['header-backup'], 'Save the LUKS header')}>Save header</Button>
    <Button icon="arrow-square-in" busy={rowstate.pending('secrets', ['move'])} disabled={u.state !== 'open'} tooltip={'Move the usual secrets into the vault'} onclick={() => openPlan('secrets', ['move'], 'Move secrets into the vault')}>Move secrets in</Button>
    <Button icon="shield-check" busy={rowstate.pending('secrets', ['secrets-fix'])} tooltip={'Root-only permissions on the secret files'} onclick={() => openPlan('secrets', ['secrets-fix'], 'Fix the permissions of the secrets')}>Fix permissions</Button>
    <Button icon="lock-simple" busy={rowstate.pending('secrets', ['close'])} disabled={u.state !== 'open'} tooltip={'Close the vault (refused while something uses it)'} onclick={() => openPlan('secrets', ['close'], 'Close the vault')}>Close…</Button>
  {/snippet}
</PageHeader>
{#if vaultFailed(rowstate.failed)}{@const vf = vaultFailed(rowstate.failed)}<ErrorNote error={vf.error} ondismiss={() => rowstate.dismiss(vf.id)} />{/if}

<Stack gap="4">
<Card>
  <div class="hero">
    <i class="ph ph-vault big-i {vstate}"></i>
    <div class="tx">
      <div class="big">{title}</div>
      <div class="desc">A 10 GiB LUKS partition on the system disk, opened with the same passphrase as the pools. Not part of the host backup snapshot.</div>
      {#if u.device}<Muted as="div">on <code>{u.device}</code>{#if u['header-backup-days'] != null} · LUKS header saved {u['header-backup-days']} day{u['header-backup-days'] === '1' ? '' : 's'} ago{/if}</Muted>{/if}
    </div>
    <Stack gap="2" style="flex:0 1 300px">
      <Muted as="div">Space</Muted>
      {#if hasUsed}<UsageBar {used} {size} />
      {:else}<Muted>{size > 0 ? `${bytes(size)} partition${u.state === 'closed' ? ' · usage is only known while it is open' : ''}` : usage.loaded ? 'not available' : 'Loading…'}</Muted>{/if}
    </Stack>
  </div>
</Card>
{#if closed || locked}<Banner tone="warn">The vault is closed because the storage is locked. Unlock it on the <button class="link-btn" onclick={() => go('/storage/encryption')}>Encryption</button> page; locked is a normal state after a boot.</Banner>{/if}

<Card title="Vault items">
  <Muted as="p">values are never shown</Muted>
  <div class="scrollx">
    <Table id="vault" {columns} rows={items} key="name" compact loading={!list.loaded}
           empty={list.error ? 'The vault could not be read (is the storage locked?).' : 'No items.'}>
      {#snippet cell(i, col)}
        {#if col.key === 'name'}<code>{i.name}</code>
        {:else if col.key === 'kind'}<Muted>{i.kind}</Muted>
        {:else if col.key === 'by'}<Muted>{by(i.name)}</Muted>
        {:else}<StatusDot state={dot(i.state)} label={i.state} />{/if}
      {/snippet}
    </Table>
  </div>
  <Muted as="p">Making the vault (<code>hs vault init</code>, it erases a partition) and moving a whole folder in (<code>hs vault bind</code>) stay in the terminal; the vault is opened from the Encryption page.</Muted>
  <Muted as="p">{uses.error ? 'Who uses an item could not be read.' : 'Who uses an item comes from a fixed list of the server\'s own services; an item that list does not know shows a dash.'}</Muted>
</Card>
</Stack>

<style>
  .hero { display: flex; align-items: center; gap: 18px; flex-wrap: wrap; }
  .big-i { font-size: 30px; color: var(--off); }
  .big-i.ok { color: var(--ok); }
  .big-i.warn { color: var(--warn); }
  .tx { flex: 1 1 320px; }
  .big { font-size: 18px; font-weight: 600; }
  .desc { color: var(--fg-2); }
  .scrollx { overflow-x: auto; }
  code { font-size: 12px; }
</style>
