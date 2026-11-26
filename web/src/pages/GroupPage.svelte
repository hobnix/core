<script>
  // The page of a group (Storage, Backup, System): one line of state at the top, then one StateCard per place that shows the place's STATE, not its
  // description. The page that uses it computes `state` with the functions of pages/groups/state.js from reads its places already do.
  // `group` (storage, backup, system ...) adds the cards of the package pages of that group that declare a `state`.
  //   <GroupPage title="Storage" state={storageState(...)}>{#snippet actions()}<Button>...</Button>{/snippet}</GroupPage>
  // `state` = { head: {state, label, line}, cards: [...] } (state.js); `actions`: one primary action at most, the rest belongs in the places;
  // children (bars, a banner) go between the line and the cards.
  import PageHeader from '../shell/PageHeader.svelte';
  import Card from '../ui/Card.svelte';
  import Grid from '../ui/Grid.svelte';
  import Muted from '../ui/Muted.svelte';
  import Row from '../ui/Row.svelte';
  import StateCard from '../ui/StateCard.svelte';
  import StatusDot from '../ui/StatusDot.svelte';
  import Stack from '../ui/Stack.svelte';
  import ExtCards from './ExtCards.svelte';

  let { title, sub = '', group = '', state, actions, children } = $props();
</script>

<Stack gap="6">
  <PageHeader {title} {sub} {actions} />
  <Card>
    <Row gap="3" wrap>
      <StatusDot state={state.head.state} label={state.head.label} large />
      <Muted>{state.head.line}</Muted>
    </Row>
  </Card>
  {@render children?.()}
  <Grid>
    {#each state.cards as c (c.key)}
      <StateCard title={c.title} state={c.state} label={c.label} line={c.line} href={c.href} linkText={c.linkText} />
    {/each}
  </Grid>
  {#if group}<ExtCards {group} />{/if}
</Stack>
