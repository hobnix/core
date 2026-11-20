<script>
  // Acknowledge a health problem: hs sys health plan|start ack <id> [--for 1d|7d|30d] [--note <text>]
  // Without a time it stays silent until the problem clears. The server records who did it.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select, Muted } from '../../ui/index.js';

  let { id, text = '', onclose, ondone } = $props();

  let span = $state('-');
  let note = $state('');

  const SPANS = [['-', 'Until the problem clears'], ['1d', 'One day'], ['7d', 'One week'], ['30d', '30 days']];
  const args = () => ['ack', id, ...(span === '-' ? [] : ['--for', span]), ...(note.trim() ? ['--note', note.trim()] : [])];
</script>

<CreateDialog title="Acknowledge a problem" kicker="Health" area="health" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Problem"><code>{text || id}</code></Field>
    <Field label="Stay silent">
      <Select bind:value={span}>{#each SPANS as [v, l]}<option value={v}>{l}</option>{/each}</Select>
    </Field>
    <Field label="Why (optional)">
      <TextInput bind:value={note} placeholder="Disk swap on Friday" maxlength={200} autocomplete="off" />
    </Field>
    <Muted as="p">It is no longer sent or counted. It ends by itself when the time is over or the problem has cleared; a worse problem is reported anyway.</Muted>
  {/snippet}
</CreateDialog>
