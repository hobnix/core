<script>
  import { Field, TextInput, Select, Checkbox, Row, Chip } from '../../ui/index.js';
  // Convert a SnapRAID data disk (hs sys pool plan|start <pool> convert --member <name> [--fs ext4|xfs|btrfs] [--encrypt]):
  // its files move onto the other data disks, the disk is erased and formatted again (another filesystem, or LUKS).
  // It is red and long (a background job); the server names the word to type (the disk). Only the data disks of a SnapRAID pool qualify.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { poolOfRole } from '../../pools.svelte.js';
  import { FS } from './disks.js';

  let { pool = poolOfRole('data'), member: member0 = '', members = [] } = $props();

  let member = $state(member0 || members[0] || '');
  let fs = $state('ext4');
  let encrypt = $state(false);
  let discard = $state(false);
  let pass = $state('');

  const args = () => {
    if (!member || (encrypt && !pass)) return null;
    return [pool, 'convert', '--member', member, '--fs', fs, ...(encrypt ? ['--encrypt'] : []), ...(discard ? ['--discard'] : [])];
  };
  const stdin = () => (encrypt && pass ? pass : undefined);
</script>

<CreateDialog title="Convert a disk" kicker="Pool" area="pool" {args} {stdin}>
  {#snippet form()}
    <Field label="Data disk" id="cv-member" help="Its files move onto the other data disks first (that can take hours, it runs as a background job), then the disk is erased and formatted again. The parity follows with the next sync.">
      {#if members.length > 1}
        <Select bind:value={member} options={members} />
      {:else}
        <Row gap="2" id="cv-member"><code>{member}</code><Chip>{pool}</Chip></Row>
      {/if}
    </Field>
    <Field label="New filesystem"><Select bind:value={fs} options={FS.map(([value, label]) => ({ value, label }))} /></Field>
    <Checkbox bind:checked={discard} label="Don't move the files, erase them with the disk"
              hint={discard ? 'Everything on the disk is lost for good, including files the file manager does not show. Use it only when the data is not needed any more.' : ''} />
    <Checkbox bind:checked={encrypt} label="Encrypt with LUKS" />
    {#if encrypt}
      <Field label="Passphrase (the one for all encrypted disks of this server; the first time it sets it)" help="It is sent to the server on its own and never appears in the command.">
          <TextInput type="password" bind:value={pass} autocomplete="new-password" spellcheck={false} />
        </Field>
    {/if}
  {/snippet}
</CreateDialog>
