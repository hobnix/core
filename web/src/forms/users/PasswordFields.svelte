<script>
  // Two password fields (the second must match, at least 8 characters). The password lives only in these inputs and in the form's state; the form hands it
  // to CreateDialog as `stdin`, so it travels in the request body and never in an argument, a URL or the page text.
  import { Field, TextInput } from '../../ui';
  let { pw = $bindable(''), pw2 = $bindable('') } = $props();
  const short = $derived(pw.length > 0 && pw.length < 8);
  const mismatch = $derived(pw2.length > 0 && pw !== pw2);
</script>

<Field label="Password" id="pw1" help="At least 8 characters. The domain's password rules (complexity) apply as well; the job says if it is refused." error={short ? 'At least 8 characters.' : ''}>
  <TextInput type="password" bind:value={pw} autocomplete="new-password" />
</Field>
<Field label="Repeat the password" id="pw2" error={mismatch ? 'The two passwords differ.' : ''}>
  <TextInput type="password" bind:value={pw2} autocomplete="new-password" />
</Field>
