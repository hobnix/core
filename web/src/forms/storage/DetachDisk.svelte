<script>
  import { Field, Segmented, Row, Chip } from '../../ui/index.js';
  // Take a SnapRAID data disk out of /<pool> to work on it by hand, and put it back (hs sys disk plan|start <member> detach|attach).
  // While a disk is part of /<pool> its files and the pool's are the same files: copying from the disk into /<pool> (a file manager, mv, Midnight Commander) truncates them.
  // A detached disk is not in the pool, so copying from it is an ordinary copy. Its files are missing in /<pool> meanwhile; the health check complains after 2 hours.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poolOfRole } from '../../pools.svelte.js';

  let { pool = poolOfRole('data'), member } = $props();

  let choice = $state('detach');
  const args = () => [member, choice];
</script>

<CreateDialog title={choice === 'attach' ? 'Put a disk back into the pool' : 'Detach a disk'} kicker="Pool" area="disk" {args}>
  {#snippet form()}
    <Field label="Data disk" id="dt-disk"><Row gap="2" id="dt-disk"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    <Field label="What should happen"
           help={choice === 'detach' ? 'The disk leaves /' + pool + ', so you can copy from it with any tool: a detached disk is not part of the pool. Its files are missing in /' + pool + ' until you put it back. To move folders between disks use the move button, to empty a disk use Close with move.'
             : 'The disk is mounted into /' + pool + ' again and its files are shown there again. Refused while something still uses it.'}>
      <Segmented bind:value={choice} label="Choice" options={[{ value: 'detach', label: 'Take it out of /' + pool }, { value: 'attach', label: 'Put it back' }]} />
    </Field>
  {/snippet}
</CreateDialog>
