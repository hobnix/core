<script>
  // Tab "Snapshots" of the page of one share: the ZFS snapshots (ZFS layout only) and the restore points of the nightly backup. The actions (Snapshot now,
  // Automatic on/off, Restore from backup, Roll back) are in the header, the menu and the danger section of the page.
  import { Banner, Card, Chip, Muted, Row, Stack } from '../../ui/index.js';

  let { m } = $props();
</script>

<Card title="Snapshots">
  {#snippet actions()}{#if m.zfs}<Muted>{m.auto ? 'automatic: hourly, kept 24 h / 7 d / 4 w' : 'automatic snapshots are off'}</Muted>{/if}{/snippet}
  {#if !m.zfs}
    <Banner tone="info">Snapshots exist on ZFS only. {m.snapraid ? 'This server keeps its shares on SnapRAID, so the restore points come from the backup (below).' : 'This share is not on a ZFS dataset.'}</Banner>
  {:else}
    <Stack gap="2">
      {#each [...m.snaps].reverse() as n (n.name)}
        <Row gap="3" align="center"><code style="flex:1">{n.name}</code><Muted>{n.created}</Muted><Chip>{n.how}</Chip></Row>
      {:else}<Muted as="p">{m.hist.loaded ? 'No snapshots yet.' : 'Loading…'}</Muted>{/each}
    </Stack>
    <Muted as="p">ZFS can only go back to the newest snapshot; newer ones are deleted by a roll-back.</Muted>
  {/if}
</Card>

<Card title="Restore points from the backup">
  {#snippet actions()}<Muted>newest first</Muted>{/snippet}
  <Stack gap="2">
    {#each m.points as p (p.id)}<Row gap="3"><code style="flex:1">{p.id}</code><Muted>{p.time}</Muted></Row>
    {:else}<Muted as="p">{m.backups.loaded ? 'The backup has no restore points for shares yet.' : 'Loading…'}</Muted>{/each}
  </Stack>
  <Muted as="p">A restore puts the files into the share <code>restored</code>; the original is not touched.</Muted>
</Card>
