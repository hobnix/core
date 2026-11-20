<script>
  // A page action of a declared page that asks for one value first (GenericPage.svelte, `input`): the field on the left, the live plan on the right.
  // The value goes into the plan arguments where the declaration has {input}; the server checks every argument against the package's changes.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput } from '../../ui/index.js';
  import { tpl, planArgs } from '../../shell/generic.js';

  let { action, suggest = '', onclose, ondone } = $props();

  const spec = $derived(action.input);
  let value = $state(suggest);
  const ok = $derived((() => { try { return !spec.pattern || new RegExp(spec.pattern).test(value.trim()); } catch { return true; } })());
  const args = () => (value.trim() && ok ? planArgs(action.plan, { input: value.trim() }) : null);
</script>

<CreateDialog title={tpl(action.planTitle ?? action.label, { input: value.trim() })} kicker="Change" area={action.plan[0]} {args} {onclose} {ondone}>
  {#snippet form()}
    <Field label={spec.label} id="in-value" error={value.trim() && !ok ? (spec.invalid ?? 'This does not look right.') : ''}>
      <TextInput bind:value placeholder={spec.placeholder ?? ''} maxlength={200} autocomplete="off" spellcheck={false} />
    </Field>
    {#if spec.hint}<div class="hint">{spec.hint}</div>{/if}
  {/snippet}
</CreateDialog>

<style>
  .hint { font-size: 12px; color: var(--color-neutral-500); }
</style>
