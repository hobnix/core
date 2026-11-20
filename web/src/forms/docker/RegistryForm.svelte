<script>
  // Add a registry login: hs sys docker-registry plan|start add <host> --user <user>. The token is the one line on standard input: it never goes into
  // an argument or a log, and it is not shown again.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Muted } from '../../ui/index.js';

  let { onclose, ondone } = $props();

  let host = $state('ghcr.io');
  let user = $state('');
  let token = $state('');

  const HOST_RE = /^[a-z0-9.-]{1,100}(:[0-9]{1,5})?$/;
  const args = () => {
    const h = host.trim();
    const u = user.trim();
    if (!HOST_RE.test(h) || !u) return null;
    return ['add', h, '--user', u];
  };
  const stdin = () => token.trim() || undefined;
</script>

<CreateDialog title="New registry login" kicker="Registries" area="docker-registry" {args} {stdin} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Registry"><TextInput bind:value={host} placeholder="ghcr.io" autocomplete="off" spellcheck={false} /></Field>
    <Field label="User"><TextInput bind:value={user} placeholder="your-github-name" autocomplete="off" spellcheck={false} /></Field>
    <Field label="Token"><TextInput type="password" bind:value={token} autocomplete="new-password" spellcheck={false} /></Field>
    <Muted as="div">For GitHub use a classic token with <code>read:packages</code> only. The token is tested, then kept in the vault (root only); it is not shown again.</Muted>
  {/snippet}
</CreateDialog>
