<script>
  // Give another homeserver read access to a share (hs sys peers plan|start offer <peer> <share> [--new-password]).
  // The answer of start holds the new password once (`secret`): ondone gets it and the page shows it in PeerOffered; it is never a job and never logged.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Checkbox } from '../../ui/index.js';

  let { onclose, ondone = () => {}, peer: peer0 = '', share: share0 = '', newpw: newpw0 = false } = $props();

  let peer = $state(peer0);
  let share = $state(share0);
  let newpw = $state(newpw0);

  const args = () => {
    const p = peer.trim(), s = share.trim();
    if (!/^[a-z0-9][a-z0-9-]{0,19}$/.test(p) || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(s)) return null;
    const a = ['offer', p, s];
    if (newpw) a.push('--new-password');
    return a;
  };
</script>

<CreateDialog title="Give access to a share" kicker="Remote shares" area="peers" {args} {onclose} ondone={(r) => ondone({ ...r, peer: peer.trim(), share: share.trim() })}>
  {#snippet form()}
    <Field label="Name for that server" id="po-peer">
      <TextInput bind:value={peer} placeholder="cousin" maxlength={20} autocomplete="off" spellcheck={false} readonly={!!peer0} />
    </Field>
    <Field label="Share it may read" id="po-share">
      <TextInput bind:value={share} placeholder="media" autocomplete="off" spellcheck={false} readonly={!!share0} />
    </Field>
    <Checkbox bind:checked={newpw} disabled={newpw0} label="Make a new password (the old one stops working)" />
    <div class="hint">The login <code>remote-{peer || 'name'}</code> can read this share and nothing else. The password is shown once, after this step.</div>
  {/snippet}
</CreateDialog>

<style>
  .hint { font-size: 12px; color: var(--color-neutral-500); }
</style>
