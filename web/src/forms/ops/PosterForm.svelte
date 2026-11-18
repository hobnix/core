<script>
  // Draw a poster (hs sys ext posters plan|start generate --eyebrow <text> --title <text> [--color c] [--seed n] [--case keep]).
  // The picture is kept on the server and shown on the Posters page.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select, Checkbox } from '../../ui/index.js';

  let { onclose, ondone } = $props();

  const COLORS = ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'indigo', 'purple', 'pink'];
  let eyebrow = $state('');
  let title = $state('');
  let color = $state('');
  let seed = $state('');
  let keepCase = $state(false);

  const args = () => {
    const e = eyebrow.trim(), t = title.trim();
    if (!e || !t || e.length > 80 || t.length > 80) return null;
    if (seed && !/^[0-9]{1,9}$/.test(seed.trim())) return null;
    const a = ['generate', '--eyebrow', e, '--title', t];
    if (color) a.push('--color', color);
    if (seed.trim()) a.push('--seed', seed.trim());
    if (keepCase) a.push('--case', 'keep');
    return a;
  };
</script>

<CreateDialog title="New poster" kicker="Posters" area="ext/posters" {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label="Small line above the title" id="po-eyebrow">
      <TextInput bind:value={eyebrow} placeholder="Movie night" maxlength={80} autocomplete="off" />
    </Field>
    <Field label="Title" id="po-title">
      <TextInput bind:value={title} placeholder="Dune" maxlength={80} autocomplete="off" />
    </Field>
    <Field label="Colour" id="po-color">
      <Select bind:value={color}>
        <option value="">Made up from the seed</option>
        {#each COLORS as c}<option value={c}>{c}</option>{/each}
      </Select>
    </Field>
    <Field label="Seed (optional)" id="po-seed">
      <TextInput bind:value={seed} placeholder="a number: the same seed gives the same poster" inputmode="numeric" maxlength={9} autocomplete="off" />
    </Field>
    <Checkbox bind:checked={keepCase} label="Keep upper and lower case (the default is all capitals)" />
  {/snippet}
</CreateDialog>

<style>
</style>
