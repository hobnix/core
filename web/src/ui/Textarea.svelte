<script>
  import { getContext } from 'svelte';
  // Native textarea with the global .input look. Inside a <Field> it takes id, aria-describedby, aria-invalid and required from it;
  // on its own it needs `ariaLabel`.
  //   <Textarea bind:value={note} rows={4} />
  // props: value (bindable), rows, id, placeholder, disabled, required, spellcheck, autocomplete, maxlength, mono (monospace, resizes vertically), ariaLabel, onchange, oninput
  let { value = $bindable(''), rows = undefined, id = undefined, placeholder = undefined, disabled = false, required = false, spellcheck = undefined, autocomplete = undefined, maxlength = undefined, mono = false,
        ariaLabel = undefined, onchange = undefined, oninput = undefined } = $props();
  const f = getContext('field');
  const req = $derived(required || !!f?.required);
</script>

<textarea class="input" class:mono {autocomplete} {maxlength} id={id ?? f?.id} bind:value {rows} {placeholder} {disabled} required={req || undefined} aria-required={req || undefined}
          {spellcheck} aria-label={ariaLabel} aria-describedby={f?.describedby} aria-invalid={f?.invalid || undefined} {onchange} {oninput}></textarea>

<style>
  textarea.mono { font-family: var(--mono); font-size: 12px; resize: vertical; }
</style>
