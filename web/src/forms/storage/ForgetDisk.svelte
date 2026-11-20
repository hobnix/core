<script>
  import { Field, Row, Chip } from '../../ui/index.js';
  // Remove a missing disk from the inventory for good (hs sys disk plan|start <serial> forget). The plan is red and the server names the word to type (the serial).
  import CreateDialog from '../../shell/CreateDialog.svelte';

  let { serial, model = '', dev = '' } = $props();

  const args = () => [serial, 'forget'];
</script>

<CreateDialog title="Forget a missing disk" kicker="Disks" area="disk" {args}>
  {#snippet form()}
    <Field label="Disk" id="fg-disk" help="Takes the disk off the list of disks this server has had, together with its SMART history and events. Only a disk that is not in the machine can be forgotten; if it comes back it is recorded as a new one.">
      <Row gap="2" id="fg-disk"><code>{serial}</code>{#if model || dev}<Chip>{[model, dev ? `was ${dev}` : ''].filter(Boolean).join(' · ')}</Chip>{/if}</Row>
    </Field>
  {/snippet}
</CreateDialog>
