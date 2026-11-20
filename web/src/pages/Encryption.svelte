<script>
  import { tip } from '../ui/tooltip.svelte.js';
  import { poll, rows } from '../data.svelte.js';
  import { bytes, sizeToBytes } from '../format.js';
  import { go } from '../route.svelte.js';
  import UnlockForm from '../forms/unlock/UnlockForm.svelte';
  import Table from '../shell/Table.svelte';
  import PageHeader from '../shell/PageHeader.svelte';
  import { StatusDot, Card, Row, Stack, Muted } from '../ui/index.js';

  let { deck } = $props();    // the shared status document
  const status = poll('/api/sys/status', 15000, 'status');
  const list = poll('/api/sys/encryption/list', 15000, 'encryption');

  const enc = $derived.by(() => {
    const r = rows(status).find((x) => x[0] === 'encryption');
    return r ? r[1] : (deck?.data?.encryption ?? null);
  });
  const locked = $derived(enc === 'locked' || !!deck?.data?.locked);
  const known = $derived(locked || enc === 'open' || enc === 'none');
  const title = $derived(locked ? 'Locked' : enc === 'open' ? 'Open' : enc === 'none' ? 'Not encrypted' : status.loaded || deck?.loaded ? 'Unknown' : 'Loading…');
  const dot = $derived(locked ? 'warn' : enc === 'open' ? 'ok' : 'off');

  // `sys encryption list`: type (vault|luks|zfs), device, state (open|locked|unmanaged), size in bytes (zfs: used); other people's disks are not listed
  const KIND = { vault: ['ph-vault', 'LUKS · vault'], luks: ['ph-hard-drive', 'LUKS disk'], zfs: ['ph-stack', 'ZFS encryption root'] };
  const STATE = { open: ['open', 'ok'], locked: ['locked', 'warn'], unmanaged: ['open · not managed by hs unlock', 'off'] };
  const listed = $derived(rows(list).map((r) => {
    const k = KIND[r[0]] ?? ['ph-lock', r[0]], st = STATE[r[2]] ?? [r[2], 'off'];
    const n = Number(r[3]);
    return { name: r[0] === 'vault' ? 'vault' : r[1].replace(/^\/dev\//, ''), on: r[0] === 'zfs' ? '–' : r[1], icon: k[0], kind: k[1], size: r[3] && !isNaN(n) && n > 0 ? bytes(n) : '–', state: st[0], dot: st[1] };
  }));
  // the plain system disk is a known fact, not a read
  const vols = $derived(!list.loaded || (enc === 'none' && !listed.length) ? [] : [...listed, { name: 'system root', icon: 'ph-desktop-tower', kind: 'plain ext4', on: '–', size: '–', state: 'not encrypted', dot: 'off' }]);

  const columns = [
    { key: 'name', label: 'Volume' }, { key: 'kind', label: 'Kind' }, { key: 'on', label: 'On', optional: true },
    { key: 'size', label: 'Size', sort: 'num', value: (v) => sizeToBytes(v.size) }, { key: 'state', label: 'State' },
  ];
  const diskOf = (v) => v.kind === 'LUKS disk';
</script>

<PageHeader title="Encryption" crumb="Storage" sub="One passphrase unlocks every LUKS disk and encrypted pool. Locked is a normal state after a boot: the system disk is plain and always reachable over SSH." />

<Stack gap="4">
  <Card>
    <Row gap="4" wrap>
      <i class="ph {locked ? 'ph-lock' : 'ph-lock-open'}" style="font-size:30px;color:var(--{dot === 'bad' ? 'bad' : dot})"></i>
      <div style="flex:1 1 320px">
        <div style="font-size:18px;font-weight:600">{title}</div>
        <Muted as="div">
          {#if enc === 'none'}No disk or pool of this server is encrypted.
          {:else if locked}Pools, shares and instances stay down until the passphrase is entered. Nothing is wrong.
          {:else if known}Everything encrypted is open.
          {:else if status.error}The state could not be read.{/if}
        </Muted>
      </div>
      <StatusDot state={dot} label={locked ? 'locked' : enc === 'open' ? 'open' : enc === 'none' ? 'not encrypted' : 'unknown'} />
      {#if locked}<div style="flex:0 1 340px;min-width:260px"><UnlockForm /></div>{/if}
    </Row>
  </Card>

  <Card title="Encrypted storage">
    <div style="overflow-x:auto"><Table id="encryption" {columns} rows={vols} key="name" compact loading={!(status.loaded || deck?.loaded)} empty="No encrypted volumes.">
      {#snippet cell(v, col)}
        {#if col.key === 'name'}<Row gap="2"><i class="ph {v.icon}"></i>{#if diskOf(v)}<button class="link-btn" use:tip={'Open this disk'} onclick={() => go('/storage/disks')}>{v.name}</button>{:else}{v.name}{/if}</Row>
        {:else if col.key === 'kind'}<Muted>{v.kind}</Muted>
        {:else if col.key === 'on'}<code>{v.on}</code>
        {:else if col.key === 'size'}<Muted>{v.size}</Muted>
        {:else}<StatusDot state={v.dot} label={v.state} />{/if}
      {/snippet}
    </Table></div>
    <Muted as="p">{list.error ? 'The list could not be read.' : 'Only the encrypted disks of this server are listed; a LUKS disk it does not know is never opened or shown.'}</Muted>
    <Muted as="p">The secrets of the server's own services are in the <button class="link-btn" onclick={() => go('/storage/vault')}>Vault</button>.</Muted>
  </Card>
</Stack>
