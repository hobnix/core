<script>
  // The fields of a declared form block (shell/GenForm.svelte) on the left, the live plan of the package's own area on the right. The value of a secret
  // field leaves this form only as stdin (CreateDialog sends it in the request body); it is not in the plan arguments, the title or the key of any list.
  import CreateDialog from '../../shell/CreateDialog.svelte';
  import { Field, TextInput, Select, Switch } from '../../ui/index.js';
  import Muted from '../../ui/Muted.svelte';
  import { initialValues, fieldError, formArgs, formStdin, formTitle } from '../../shell/genform.js';

  let { block, onclose, ondone } = $props();

  const values = $state(initialValues(block));
  let touched = $state({});                         // a field shows its error once something was typed or it was left
  const args = () => formArgs(block, values);
  const stdin = () => formStdin(block, values);
  const err = (f) => (touched[f.key] || values[f.key] !== '' ? fieldError(f, values[f.key]) : '');
</script>

<CreateDialog title={formTitle(block, values)} kicker="Change" area={block.plan[0]} {args} {stdin} {onclose} {ondone}>
  {#snippet form()}
    {#if block.text}<Muted as="p">{block.text}</Muted>{/if}
    {#each block.fields as f (f.key)}
      {#if f.type === 'toggle'}
        <Field label={f.label} help={f.hint ?? ''} id={'gf-' + f.key}>
          <Switch checked={values[f.key] === 'on'} label={f.label} onchange={(on) => { values[f.key] = on ? 'on' : 'off'; }} />
        </Field>
      {:else if f.type === 'select'}
        <Field label={f.label} help={f.hint ?? ''} required={f.required} id={'gf-' + f.key}>
          <Select bind:value={values[f.key]} options={f.options} />
        </Field>
      {:else}
        <Field label={f.label} help={f.hint ?? ''} error={err(f)} required={f.required} id={'gf-' + f.key}>
          <TextInput bind:value={values[f.key]} type={f.type === 'secret' ? 'password' : f.type === 'number' ? 'number' : 'text'} placeholder={f.placeholder ?? ''}
                     autocomplete={f.type === 'secret' ? 'new-password' : 'off'} spellcheck={false} maxlength={f.type === 'number' ? undefined : 300}
                     onchange={() => { touched[f.key] = true; }} />
        </Field>
      {/if}
    {/each}
    {#if block.fields.some((f) => f.type === 'secret')}
      <Muted as="p">The secret goes to the server for this one change and is not shown again.</Muted>
    {/if}
  {/snippet}
</CreateDialog>
