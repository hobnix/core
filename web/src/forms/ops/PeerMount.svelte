<script>
  // Mount a share of another homeserver read only (hs sys peers plan|start add <peer> <host> <share> --user <login> [--domain <D>]).
  // The password of the login is one line on standard input: it never goes into the arguments or the job log.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput } from '../../ui/index.js';
  import { pools, loadPools, poolOfRole } from '../../pools.svelte.js';

  let { onclose, ondone } = $props();

  loadPools();
  const dataPool = $derived((pools.loaded ? poolOfRole('data') : '') || 'bulk');

  let peer = $state('');
  let host = $state('');
  let share = $state('');
  let user = $state('');
  let domain = $state('');
  let pass = $state('');

  const args = () => {
    const p = peer.trim(), h = host.trim(), s = share.trim(), u = user.trim();
    if (!p || !h || !s || !u) return null;
    const a = ['add', p, h, s, '--user', u];
    if (domain.trim()) a.push('--domain', domain.trim());
    return a;
  };
  const stdin = () => (pass ? pass : undefined);
</script>

<CreateDialog title="Mount a share from another server" kicker="Remote shares" area="peers" {args} {stdin} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Name for that server" id="pm-peer">
      <TextInput bind:value={peer} placeholder="cousin" maxlength={20} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Its address" id="pm-host">
      <TextInput bind:value={host} placeholder="homeserver2.local" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Share on that server" id="pm-share">
      <TextInput bind:value={share} placeholder="media" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Login it gave you" id="pm-user">
      <TextInput bind:value={user} placeholder="remote-yourserver" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Domain (optional)" id="pm-domain">
      <TextInput bind:value={domain} placeholder="HOME" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Password" id="pm-pass">
      <TextInput type="password" bind:value={pass} autocomplete="new-password" />
    </Field>
    <div class="hint">Read only. It is not part of /{dataPool}, the parity or the backup. The other server makes the login with “Give access…” on its Network page (or <code>hs remote offer</code>); the password is shown once.</div>
  {/snippet}
</CreateDialog>

<style>
  .hint { font-size: 12px; color: var(--color-neutral-500); }
</style>
