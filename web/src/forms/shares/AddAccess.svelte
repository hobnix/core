<script>
  // Give a user or group access: `hs sys shares plan|start <share> perm --set <sid>=<level>`; the principals come from /api/sys/shares/principals.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, Segmented, Muted, UserField } from '../../ui';

  // taken: the SIDs that already have an entry
  let { share, taken = [], onclose, ondone = () => {} } = $props();

  let sid = $state('');
  let level = $state('read');
  const args = () => (/^S-1-[0-9]+(-[0-9]+)+$/.test(sid) ? [share, 'perm', '--set', `${sid}=${level}`] : null);
</script>

<CreateDialog title="Add access to {share}" kicker="Permissions" area="shares" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="User or group">
      <UserField principals {taken} bind:value={sid} />
    </Field>
    <Field label="Access" id="aa-level">
      <Segmented bind:value={level} label="Access" options={['none', 'read', 'write', 'full']} />
    </Field>
    <Muted as="p">Permissions apply at the next connection.</Muted>
  {/snippet}
</CreateDialog>
