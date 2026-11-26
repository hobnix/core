<script>
  // Tab "Network" of the page of one instance: its address and what the reverse proxy publishes for it (the services whose target is this instance).
  import { go } from '../../route.svelte.js';
  import { setSelection } from '../../select.svelte.js';
  import { P } from '../../paths.js';
  import { Card, Chip, Kv, Muted, Row, Stack } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import { ipOf } from './ct.js';

  let { m } = $props();
  const ct = $derived(m.ct);
</script>

<Card title="Address">
  <Kv items={[{ k: 'Address', v: ct.address && ct.address !== '-' ? ct.address : '' }, { k: 'IPv4', v: ipOf(ct.address) }]} />
  <Muted as="p">A fixed address is set with Settings in the header (Fixed address); the instance takes it at its next start.</Muted>
</Card>

<Card title="Route">
  {#snippet actions()}<Muted>what the reverse proxy publishes for this instance</Muted>{/snippet}
  <Stack gap="3">
    {#each m.myServices as s (s.name)}
      <Stack gap="1">
        <Row gap="3" align="center">
          <Button variant="ghost" size="sm" tooltip="Open the Services page" onclick={() => go(P.services)}>{s.title && s.title !== '-' ? s.title : s.name}</Button>
          <Chip tone={s.exposure === 'public-ok' ? 'accent' : ''}>{s.exposure}</Chip>
        </Row>
        <Muted as="div">{s.names && s.names !== '-' ? s.names : 'no public name'} → {s.target}</Muted>
      </Stack>
    {:else}<Muted as="p">{m.svc.loaded ? 'No service describes this instance, so it has no route.' : 'Loading…'}</Muted>{/each}
  </Stack>
  {#if m.myRecipes.length}
    <Row gap="2" wrap align="center"><Muted>Set up by the recipe</Muted>{#each m.myRecipes as r (r.name)}<Button variant="ghost" size="sm" tooltip="Open the recipe in the app catalog" onclick={() => { setSelection('recipes', r.name); go(P.apps); }}>{r.name}</Button>{/each}</Row>
  {/if}
</Card>
