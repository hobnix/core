<script>
  // Connect the router (UniFi): hs sys net plan|start setup --address <url>, the API key as the one line on standard input (never in an argument or a log).
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Muted } from '../../ui/index.js';

  let { onclose, ondone } = $props();

  let address = $state('');
  let key = $state('');

  const args = () => {
    const a = address.trim();
    if (!/^https?:\/\/[A-Za-z0-9._:-]{1,100}\/?$/.test(a) || !key) return null;
    return ['setup', '--address', a];
  };
  const stdin = () => (key ? key : undefined);
</script>

<CreateDialog title="Connect the router" kicker="Network" area="net" {args} {stdin} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Address of the UniFi router">
      <TextInput bind:value={address} placeholder="https://10.10.10.1" autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="API key">
      <TextInput type="password" bind:value={key} autocomplete="new-password" spellcheck={false} />
    </Field>
    <Muted as="div">
      Make the key in UniFi: Network, Settings, Control Plane, Integrations, Create API Key. The key cannot be narrowed there (it is full Network admin), so this server only
      reads the networks and writes fixed addresses inside the container network. It is stored root-only (in the vault when there is one) and never shown again.
    </Muted>
  {/snippet}
</CreateDialog>
