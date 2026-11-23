<script>
  // The Storage group page: pools, disks, shares and the encryption as state cards, and the capacity of each pool on top. It reads what those places
  // read (readsfor.js, P.storage); the pools come from the store the tree uses.
  import { poll, rows } from '../../data.svelte.js';
  import { pools as poolStore } from '../../pools.svelte.js';
  import { poolPath } from '../../paths.js';
  import { url } from '../../route.svelte.js';
  import GroupPage from '../GroupPage.svelte';
  import { storageState } from './state.js';
  import UsageBar from '../../shell/UsageBar.svelte';
  import Card from '../../ui/Card.svelte';
  import Grid from '../../ui/Grid.svelte';

  let { deck } = $props();    // the shared status document (Shell polls it)

  const mon = poll('/api/sys/monitor/disks', 30000, 'monitor-disks');
  const overview = poll('/api/sys/shares/overview', 30000, 'shares-overview');
  const locked = $derived(!!deck?.data?.locked);
  const sizes = $derived(deck?.data?.pools ?? {});
  const state = $derived(storageState({
    locked,
    pools: poolStore.rows,
    sizes,
    disks: mon.data ? rows(mon) : null,
    shares: overview.data ? rows(overview) : null,
  }));
  const bars = $derived(locked ? [] : poolStore.rows.filter((p) => sizes[p.name]?.size > 0));
</script>

<GroupPage title="Storage" group="storage" {state} sub="Pools, disks, shares and the encryption of this server.">
  {#if bars.length}
    <Grid>
      {#each bars as p (p.name)}
        <Card>
          <a href={url(poolPath(p.name))}>{p.name}</a>
          <UsageBar used={sizes[p.name].used} size={sizes[p.name].size} block />
        </Card>
      {/each}
    </Grid>
  {/if}
</GroupPage>
