<script>
  // Tab "Access" of the page of one share: who sees the share in the network list (visibility) and who may do what (the permission entries).
  // Every change opens a plan (openPlan) and takes effect at the next connection.
  import { openPlan, openCreate } from '../../ui.svelte.js';
  import { Card, Muted, Row, Stack } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import AddAccess from '../../forms/shares/AddAccess.svelte';

  let { m, name, locked = false } = $props();
  const LEVELS = ['none', 'read', 'write', 'full'];
  const setLevel = (e, l) => l !== e.level && openPlan('shares', [name, 'perm', '--set', `${e.sid}=${l}`], `${e.name}: ${l} on ${name}`);
  const setVisible = (v) => v !== m.visibility && openPlan('shares', [name, 'visibility', '--to', v], `${name}: ${v}`);
</script>

<Card title="Visibility">
  <Muted as="p">Hidden shares can still be opened by typing the path. Visible shares are listed only for people with at least read access below.</Muted>
  <Row gap="0" role="group" aria-label="Visibility of {name}" style="margin-top:10px">
    {#each ['hidden', 'visible'] as v}
      <Button need="admin" size="sm" variant={v === m.visibility ? 'primary' : ''} aria-pressed={v === m.visibility} disabled={locked || !m.vis.loaded} tooltip={v === m.visibility ? 'The current setting' : `Make ${name} ${v}`} onclick={() => setVisible(v)}>{v === 'hidden' ? 'Hidden' : 'Visible'}</Button>
    {/each}
  </Row>
</Card>

<Card title="Permissions">
  {#snippet actions()}
    <Muted>apply at the next connection</Muted>
    <Button need="admin" size="sm" icon="plus" disabled={locked} tooltip={locked ? 'Storage is locked' : 'Give a user or group access to this share'} onclick={() => openCreate(AddAccess, { share: name, taken: m.entries.map((e) => e.sid) })}>Add</Button>
  {/snippet}
  <Stack gap="2">
    {#each m.entries as e (e.sid)}
      <Row gap="3" align="center" wrap style="justify-content:space-between">
        <span><i class="ph {e.type === 'group' ? 'ph-users-three' : 'ph-user'}" aria-hidden="true"></i> {e.name}</span>
        <Row gap="0" role="group" aria-label="Access of {e.name}">
          {#each LEVELS as l}
            <Button need="admin" size="sm" variant={l === e.level ? 'primary' : ''} aria-pressed={l === e.level} disabled={locked} tooltip={l === e.level ? 'The current level' : `Set ${e.name} to ${l}`} onclick={() => setLevel(e, l)}>{l}</Button>
          {/each}
        </Row>
      </Row>
    {:else}
      <Muted as="p">{m.acl.loaded ? 'No entries.' : 'Loading…'}</Muted>
    {/each}
  </Stack>
</Card>
