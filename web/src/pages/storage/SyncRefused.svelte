<script>
  // The table of the last refused parity sync (`hs sys share parity refused`): which shares are over their limit and where the removed files are, with
  // the button that syncs anyway (`hs sys system plan|start sync --force`; the plan names what becomes permanent). Shown only while there are rows.
  import { poll, rows } from '../../data.svelte.js';
  import { openPlan } from '../../ui.svelte.js';
  import { rowstate } from '../../rowstate.svelte.js';
  import { Banner, Muted } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import Table from '../../shell/Table.svelte';

  let { locked = false } = $props();

  const refused = poll('/api/sys/share/parity/refused', 15000, 'pool-state');
  // share<TAB>folder<TAB>removed<TAB>limit<TAB>share_total
  const list = $derived(rows(refused).map((r) => ({ share: r[0], folder: r[1] === '-' ? '(whole share)' : r[1], removed: r[2], limit: r[3], total: r[4], key: `${r[0]}/${r[1]}` })));
  const columns = [{ key: 'share', label: 'Share' }, { key: 'folder', label: 'Folder' }, { key: 'removed', label: 'Removed' }, { key: 'limit', label: 'Limit' }];
  const shares = $derived([...new Set(list.map((r) => r.share))]);
</script>

{#if list.length}
  <Banner tone="warn">
    The last parity sync stopped: {shares.length === 1 ? 'one share has' : `${shares.length} shares have`} more removed files than its limit. The files are still in the parity, so they can be restored.
    <Table id="sync-refused" {columns} rows={list} key="key" compact empty="" />
    <Muted as="p">Normal app work in a folder (downloads, unpacking)? Leave it out of the parity or raise the limit on the share's page. If the deletions are really expected, sync anyway.</Muted>
    <Button size="sm" variant="primary" icon="arrows-clockwise" busy={rowstate.pending('system', ['sync', '--force'])} disabled={locked} tooltip={'Shows the plan first: the removals become permanent in the parity'} onclick={() => openPlan('system', ['sync', '--force'], 'Sync parity, deletions expected')}>These deletions are expected, sync now</Button>
  </Banner>
{/if}
