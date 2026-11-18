<script>
  // Save a game PC: hs sys ext games plan|start <name> add --mac <mac> [--ip <ip>]
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput } from '../../ui/index.js';

  let { onclose, ondone } = $props();

  let name = $state('');
  let mac = $state('');
  let ip = $state('');

  // the plan answers "needs mac" while the MAC is empty, and refuses a MAC or an address the script does not accept
  const args = () => {
    const n = name.trim();
    if (!n) return null;
    const a = [n, 'add'];
    if (mac.trim()) a.push('--mac', mac.trim());
    if (ip.trim()) a.push('--ip', ip.trim());
    return a;
  };
</script>

<CreateDialog title="Add a game PC" kicker="Add" area="ext/games" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Name" id="pc-name">
      <TextInput bind:value={name} placeholder="gaming-pc" maxlength={41} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="MAC address of its network card" id="pc-mac">
      <TextInput bind:value={mac} placeholder="aa:bb:cc:dd:ee:ff" maxlength={17} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Address on the LAN (optional)" id="pc-ip">
      <TextInput bind:value={ip} placeholder="10.10.10.50" maxlength={15} autocomplete="off" spellcheck={false} />
    </Field>
    <div class="hint">The MAC address is what the Wake-on-LAN packet goes to. With an address the page can also see whether Sunshine on that PC answers. A name that is saved already gets the new values.</div>
  {/snippet}
</CreateDialog>

<style>
  .hint { font-size: 12px; color: var(--color-neutral-500); }
</style>
