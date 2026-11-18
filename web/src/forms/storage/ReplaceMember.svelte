<script>
  import { Field, TextInput, Select, Checkbox, Row, Chip } from '../../ui/index.js';
  // Replace a member of a pool with a free disk (hs sys pool plan|start <pool> replace --member <name> --disks <id> ...).
  // SnapRAID can format the new disk with another filesystem or LUKS; ZFS takes the disk as it is.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import DiskPicker from './DiskPicker.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { freeDisks, FS } from './disks.js';

  let { pool, member, snap = false } = $props();

  let picked = $state([]);
  let fs = $state('ext4');
  let encrypt = $state(false);
  let pass = $state('');

  const free = poll('/api/sys/pool/disks', 15000);
  const disks = $derived(freeDisks(rows(free)));

  const args = () => {
    if (!picked.length) return null;
    if (!snap) return [pool, 'replace', '--member', member, '--disks', picked[0]];
    if (encrypt && !pass) return null;
    return [pool, 'replace', '--member', member, '--disks', picked[0], '--fs', fs, ...(encrypt ? ['--encrypt'] : [])];
  };
  const stdin = () => (snap && encrypt && pass ? pass : undefined);
</script>

<CreateDialog title="Replace a disk" kicker="Pool" area="pool" {args} {stdin}>
  {#snippet form()}
    <Field label="Member to replace" id="rp-member"><Row gap="2" id="rp-member"><code>{member}</code><Chip>{pool}</Chip></Row></Field>
    <Field label="New disk (it is erased)" id="rp-disks">
      <div id="rp-disks"><DiskPicker {disks} loaded={free.loaded} bind:picked single /></div>
    </Field>
    {#if snap}
      <Field label="Filesystem of the new disk"><Select bind:value={fs} options={FS.map(([value, label]) => ({ value, label }))} /></Field>
      <Checkbox bind:checked={encrypt} label="Encrypt with LUKS" />
      {#if encrypt}
        <Field label="Passphrase (the one for all encrypted disks of this server)" help="It is sent to the server on its own and never appears in the command.">
          <TextInput type="password" bind:value={pass} autocomplete="new-password" spellcheck={false} />
        </Field>
      {/if}
    {/if}
  {/snippet}
</CreateDialog>
