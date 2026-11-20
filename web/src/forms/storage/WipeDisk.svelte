<script>
  import { Field, Row, Chip } from '../../ui/index.js';
  // Format (erase) a disk that belongs to nothing (hs sys disk plan|start <disk> wipe). The plan is red and the server names the word to type (the disk).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { sizeTxt } from '../../pages/storage/pool.js';

  let { disk, model = '', size = 0 } = $props();

  const args = () => [disk, 'wipe'];
</script>

<CreateDialog title="Format a disk" kicker="Disks" area="disk" {args}>
  {#snippet form()}
    <Field label="Disk" id="wd-disk" help="Erases every filesystem and the partition table, so the disk is empty and can be added to a pool. A disk that is mounted, in a pool or an array, or one of this server's encrypted disks is refused.">
      <Row gap="2" id="wd-disk"><code>{disk}</code>{#if model || size}<Chip>{[model, size ? sizeTxt(size) : ''].filter(Boolean).join(' · ')}</Chip>{/if}</Row>
    </Field>
  {/snippet}
</CreateDialog>
