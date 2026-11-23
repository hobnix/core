<script>
  // Tab "Config" of the page of one instance: its settings (read here, changed with "Settings…" in the header), the storage it sees (folders of pools and shares) and its
  // snapshots. Every change opens a plan (openPlan); a locked instance (owner set) keeps its storage and cannot be deleted.
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { go } from '../../route.svelte.js';
  import { Card, Chip, Kv, Muted, Row, Stack } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import BindStorage from '../../forms/instances/BindStorage.svelte';
  import { sharePath } from '../shares/path.js';
  import { boots, spaced } from './model.svelte.js';

  let { m } = $props();
  const ct = $derived(m.ct);
  const yes = (v) => (/^(yes|true|on)$/i.test((v ?? '').trim()) ? 'yes' : 'no');
</script>

<Card title="Settings">
  <Kv items={[
    { k: 'RAM limit', v: spaced(ct.ram) }, { k: 'CPU limit', v: ct.cpu }, { k: 'Disk', v: ct.disk },
    { k: 'Starts at boot', v: boots(ct) ? 'yes' : 'no' }, { k: 'Docker support', v: ct.docker && ct.docker !== '-' ? yes(ct.docker) : '' },
  ]} />
  <Muted as="p">Change them with Settings in the header; the plan shows what differs from today.</Muted>
</Card>

<Card title="Storage">
  {#snippet actions()}<Muted>disks and shares this instance sees</Muted>{/snippet}
  <Stack gap="3">
    {#each m.bindings as b (b.device)}
      <Stack gap="1">
        <Row gap="3" wrap align="center">
          <Chip>{b.kind}</Chip>
          {#if b.share && b.share !== '-'}<Button variant="ghost" size="sm" tooltip="Open the share" onclick={() => go(sharePath(b.share))}>{b.share}</Button>{:else}<code>{b.source}</code>{/if}
          <Muted>{b.mode}</Muted>
          <span style="flex:1"></span>
          {#if !ct.owner}<Button need="app-manager" variant="ghost" icon="x" label="Remove {b.device}" tooltip="Remove this binding" busy={rowstate.pending('ct', [ct.name, 'remove-storage', '--device', b.device])} onclick={() => openPlan('ct', [ct.name, 'remove-storage', '--device', b.device], `Remove ${b.device} from ${ct.name}`)} />{/if}
        </Row>
        <Muted as="div"><code>{b.source} → {b.inside}</code></Muted>
        {#if b.also && b.also !== '-'}<Muted as="div">Also mounted by {b.also}</Muted>{/if}
      </Stack>
    {:else}<Muted as="p">{m.bind.loaded ? 'No storage bindings.' : 'Loading…'}</Muted>{/each}
  </Stack>
  {#if !ct.owner}<Row><Button need="app-manager" size="sm" icon="plus" tooltip="Give this instance a folder of a pool or a share" onclick={() => openCreate(BindStorage, { ct: ct.name })}>Bind a share</Button></Row>{/if}
</Card>

<Card title="Snapshots">
  {#snippet actions()}<Muted>nightly at 02:00, kept 7 days</Muted>{/snippet}
  <Stack gap="2">
    {#each m.snaps as sn, i (sn.name)}
      <Row gap="3" align="center">
        <code style="flex:1">{sn.name}</code><Muted>{sn.created}</Muted>
        <Button need="app-manager" variant="ghost" icon="arrow-u-up-left" label="Restore {sn.name}" tooltip={i === 0 ? 'Go back to this snapshot' : 'Go back to this snapshot (the newer ones are deleted)'} busy={rowstate.pending('ct', [ct.name, 'restore', '--snapshot', sn.name])} onclick={() => openPlan('ct', [ct.name, 'restore', '--snapshot', sn.name], `Restore ${ct.name}`)} />
        <Button need="app-manager" variant="ghost" icon="trash" label="Delete {sn.name}" tooltip="Delete this snapshot (the plan asks for the instance name)" busy={rowstate.pending('ct', [ct.name, 'delete-snapshot', '--snapshot', sn.name])} onclick={() => openPlan('ct', [ct.name, 'delete-snapshot', '--snapshot', sn.name], `Delete snapshot ${sn.name}`)} />
      </Row>
    {:else}<Muted as="p">{m.snap.loaded ? (m.snap.error ? 'The snapshots could not be read.' : 'No snapshots yet.') : 'Loading…'}</Muted>{/each}
  </Stack>
  <Muted as="p">ZFS goes back to the newest snapshot only: restoring an older one deletes the newer ones first. Snapshot now is in the More menu.</Muted>
</Card>
