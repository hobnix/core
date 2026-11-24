<script>
  // Let another server read a share of this one (hs sys peers plan|start code <share> [--peer <name>] [--minutes N]).
  // The answer of start holds the code once (`secret` lines: code, address, expires_in): ondone gets it and the page shows it in RemoteCode. It is never
  // a job and never logged. `New code…` on a row opens this with the server and share fixed (a code bound to that server; the old password stops working).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, ShareField, Muted } from '../../ui/index.js';

  let { onclose, ondone = () => {}, peer: peer0 = '', share: share0 = '' } = $props();

  let share = $state(share0);
  let peer = $state(peer0);

  const args = () => {
    const p = peer.trim();
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(share) || (p && !/^[a-z0-9][a-z0-9-]{0,19}$/.test(p))) return null;
    const a = ['code', share];
    if (p) a.push('--peer', p);
    return a;
  };
</script>

<CreateDialog title={peer0 ? `New code for ${peer0}` : 'Give access to a share'} kicker="Remote shares" area="peers" {args} {onclose} ondone={(r) => ondone({ ...r, peer: peer.trim(), share })}>
  {#snippet form()}
    <Field label="Share it may read" id="rg-share">
      <ShareField bind:value={share} disabled={!!share0} />
    </Field>
    <Field label="Name for that server (optional)" id="rg-peer" help="Leave it empty: the other server then names itself.">
      <TextInput bind:value={peer} placeholder="cousin" maxlength={20} autocomplete="off" spellcheck={false} readonly={!!peer0} />
    </Field>
    <Muted>Make a code shows it once. The other server types it within a few minutes; it works once and can read this share and nothing else.</Muted>
  {/snippet}
</CreateDialog>
