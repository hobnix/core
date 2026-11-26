<script>
  // Give an instance the mounted shares of a server, read only, or take them away again (hs sys peers plan|start attach|detach <peer> <instance>).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select } from '../../ui/index.js';

  let { peer, instances = [], onclose, ondone } = $props();

  let mode = $state('attach');
  let instance = $state('');
  let path = $state('');

  const args = () => {
    if (!instance) return null;
    const a = [mode, peer, instance];
    if (mode === 'attach' && path.trim()) a.push('--path', path.trim());
    return a;
  };
</script>

<CreateDialog title="Shares of {peer} in an instance" kicker="Remote shares" area="peers" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="What to do" id="pa-mode">
      <Select bind:value={mode}>
        <option value="attach">Give the instance the shares (read only)</option>
        <option value="detach">Take them away from the instance</option>
      </Select>
    </Field>
    <Field label="Instance" id="pa-ct">
      <Select bind:value={instance}>
        <option value="">Choose…</option>
        {#each instances as i}<option value={i}>{i}</option>{/each}
      </Select>
    </Field>
    {#if mode === 'attach'}
      <Field label="Folder inside the instance (optional)" id="pa-path">
        <TextInput bind:value={path} placeholder="/mnt/remote/{peer}" autocomplete="off" spellcheck={false} />
      </Field>
    {/if}
    <div class="hint">Useful for Jellyfin: the films of the other server show up without a copy. They are never in the backup or the parity.</div>
  {/snippet}
</CreateDialog>

<style>
  .hint { font-size: 12px; color: var(--color-neutral-500); }
</style>
