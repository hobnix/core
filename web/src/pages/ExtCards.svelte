<script>
  // The cards of the package pages of one group that declare a `state` (Group page, Apps list). Nothing is drawn when there is none.
  //   <ExtCards group="apps" />
  import Grid from '../ui/Grid.svelte';
  import ExtStateCard from './ExtStateCard.svelte';
  import { ui } from '../ui.svelte.js';
  import { extGroup, EXT_GROUPS } from '../nav.js';

  let { group } = $props();
  const mine = $derived((ui.features.extensions ?? []).filter((e) => e.state && extGroup(e) === EXT_GROUPS[group]).sort((a, b) => String(a.title).localeCompare(String(b.title))));
</script>

{#if mine.length}
  <Grid>
    {#each mine as e (e.name)}<ExtStateCard ext={e} />{/each}
  </Grid>
{/if}
