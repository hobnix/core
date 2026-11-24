<script>
  // Use a share of another server by its code (hs sys peers plan|start add-code [--server <name|host>] [--reconnect <server>]).
  // The code is ONE LINE on standard input: it never goes into the arguments, the plan cache or a log. With `reconnect` the row of that server gets a new
  // login from a new code (D8). "Enter a login by hand" is the fallback: the old form with a login and a password (RemoteMount).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, ServerField, Muted } from '../../ui/index.js';
  import Button from '../../ui/Button.svelte';
  import { poll, rows } from '../../data.svelte.js';
  import { openCreate } from '../../ui.svelte.js';
  import RemoteMount from './RemoteMount.svelte';
  import { serverOptions, splitCode } from './remotecode.js';

  let { onclose, ondone, reconnect = '' } = $props();

  const nodes = poll('/api/sys/node/list', 15000);
  const options = $derived(serverOptions(rows(nodes)));
  let code = $state('');
  let server = $state('');

  const c = $derived(splitCode(code));
  // the code alone needs a server; CODE@host carries its address
  const args = () => {
    if (!c.ok || (!c.host && !server.trim() && !reconnect)) return null;
    const a = ['add-code'];
    if (server.trim()) a.push('--server', server.trim());
    if (reconnect) a.push('--reconnect', reconnect);
    return a;
  };
  const stdin = () => (c.ok ? (c.host ? `${c.code}@${c.host}` : c.code) : undefined);
  const byHand = () => { onclose(); openCreate(RemoteMount, { ondone }); };
</script>

<CreateDialog title={reconnect ? `Reconnect to ${reconnect}` : 'Add a remote share'} kicker="Remote shares" area="peers" {args} {stdin} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Code from the other server" id="ra-code" help="Like K7QX-9M2D-T4PW-3HNC@alpha.local. The other server makes it with Give access.">
      <TextInput bind:value={code} placeholder="K7QX-9M2D-T4PW-3HNC@alpha.local" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label={c.host ? 'Server (optional)' : 'Server'} id="ra-server" help="A server you know, or its address. Not needed when the code carries the address.">
      <ServerField {options} loaded={nodes.loaded} error={nodes.error} noun="servers" free bind:value={server} placeholder="Choose a server or type an address" />
    </Field>
    <Muted>The code works once and for a few minutes. Read only: the share is not part of the pool, the parity or the backup.</Muted>
    {#if !reconnect}<div><Button variant="ghost" size="sm" tooltip={'Use a login and password the other server gave you'} onclick={byHand}>Enter a login by hand</Button></div>{/if}
  {/snippet}
</CreateDialog>
