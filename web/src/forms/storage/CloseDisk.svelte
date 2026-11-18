<script>
  import { Field, Segmented, Row, Chip } from '../../ui/index.js';
  // Stop (or allow again) new files on a SnapRAID data disk (hs sys pool plan|start <pool> close|open --member <name> [--drain]).
  // A closed disk stays in /<pool> and keeps its files; mergerfs just never picks it for a new file. --drain also moves its files
  // onto the other disks (a long background job, the server names the word to type). Open and close without drain change a mark only.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poolOfRole } from '../../pools.svelte.js';

  let { pool = poolOfRole('data'), member, closed = false } = $props();

  let choice = $state(closed ? 'open' : 'close');

  const args = () => (choice === 'open' ? [pool, 'open', '--member', member] : [pool, 'close', '--member', member, ...(choice === 'drain' ? ['--drain'] : [])]);
</script>

<CreateDialog title={closed ? 'Closed disk' : 'No new files on a disk'} kicker="Pool" area="pool" {args}>
  {#snippet form()}
    <Field label="Data disk" id="cl-disk"><Row gap="2" id="cl-disk"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    <Field label="What should happen"
           help={choice === 'open' ? 'New files are spread over all disks again, this one included.'
             : choice === 'close' ? 'The disk stays in /' + pool + ' and keeps what it holds; only new files go to the other disks. Nothing moves, nothing is erased. A file that already lives there and grows is still written there.'
             : 'Its files move onto the other data disks (hours, a background job). Until a file is moved it is not visible in /' + pool + '. The disk stays in the pool, empty and closed. A good first step before removing it.'}>
      <Segmented bind:value={choice} label="Choice" options={[closed ? { value: 'open', label: 'Take new files again' } : { value: 'close', label: 'No new files' }, { value: 'drain', label: closed ? 'Move its files away' : 'No new files, and move its files away' }]} />
    </Field>
  {/snippet}
</CreateDialog>
