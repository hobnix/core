<script>
  import { Field, Select, Segmented, Row, Muted, Chip } from '../../ui/index.js';
  // Get deleted files back from a SnapRAID data disk (hs sys disk plan|start <member> recover [--to <member>] [--types media|all]) and give the disk back
  // to the pool afterwards (<member> recover-finish). The disk leaves /<pool>, is made read-only and searched by content (photorec), a long background job;
  // what is found goes onto another data disk (share "recovered"). Names and folders of deleted files cannot be recovered. The server names the word to type.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poolOfRole } from '../../pools.svelte.js';

  let { pool = poolOfRole('data'), member, members = [] } = $props();

  let choice = $state('recover');
  let to = $state('');
  let types = $state('media');

  const targets = $derived(members.filter((n) => n !== member));
  const args = () => (choice === 'finish' ? [member, 'recover-finish'] : [member, 'recover', ...(to ? ['--to', to] : []), '--types', types]);
</script>

<CreateDialog title={choice === 'finish' ? 'Give a disk back to the pool' : 'Recover deleted files'} kicker="Pool" area="disk" {args}>
  {#snippet form()}
    <Field label="Data disk" id="rc-disk"><Row gap="2" id="rc-disk"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    <Field label="What should happen">
      <Segmented bind:value={choice} label="Choice" options={[{ value: 'recover', label: 'Search for deleted files' }, { value: 'finish', label: 'Give the disk back to the pool' }]} />
    </Field>
    {#if choice === 'recover'}
      <Field label="Put what is found on">
        <Select bind:value={to}><option value="">The disk with the most free space</option>{#each targets as t}<option value={t}>{t}</option>{/each}</Select>
      </Field>
      <Field label="Look for" help={'The disk leaves /' + pool + ' (its files are not visible there meanwhile), is set read-only and is read completely: hours, a background job. Names and folders of deleted files are gone for good; files come back numbered, videos and music named by their tags. A file that was written in pieces can come back cut off. Nothing is ever written to this disk.'}>
        <Segmented bind:value={types} label="Types" options={[{ value: 'media', label: 'Photos, videos, music, documents' }, { value: 'all', label: 'Every kind (slow, many junk files)' }]} />
      </Field>
    {:else}
      <Muted as="p">The disk can be written to again and is mounted into /{pool}. What was recovered stays where it is. Refused while the search is still running.</Muted>
    {/if}
  {/snippet}
</CreateDialog>
