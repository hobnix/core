<script>
  // Add something that runs out on a date: hs sys expiry plan|start add <name> --date YYYY-MM-DD [--renew <text>]
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Muted } from '../../ui';

  let { onclose, ondone } = $props();

  let name = $state('');
  let date = $state('');
  let renew = $state('');

  // the plan answers "needs date" while the date is empty, and refuses a name or a date the script does not accept
  const args = () => {
    const n = name.trim();
    if (!n) return null;
    const a = ['add', n];
    if (date) a.push('--date', date);
    if (renew.trim()) a.push('--renew', renew.trim());
    return a;
  };
</script>

<CreateDialog title="New expiry date" kicker="Add" area="expiry" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="What runs out">
      <TextInput bind:value={name} placeholder="Domain controller certificate" maxlength={61} autocomplete="off" spellcheck={false} />
    </Field>
    <Field label="Until when">
      <TextInput type="date" bind:value={date} />
    </Field>
    <Field label="How it is renewed (a hint for you, optional)">
      <TextInput bind:value={renew} placeholder="Cloudflare dashboard, Zero Trust, Tunnels" maxlength={120} autocomplete="off" />
    </Field>
    <Muted as="p">The health check warns 30 days and 7 days before the date. A name that is on the list already gets the new date.</Muted>
  {/snippet}
</CreateDialog>
