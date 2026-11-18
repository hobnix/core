<script>
  import { getContext } from 'svelte';
  // Native text input with the global .input look. Inside a <Field> it takes id, aria-describedby, aria-invalid and required from it;
  // on its own it needs `ariaLabel`.
  //   <TextInput bind:value={name} placeholder="photos" autocomplete="off" spellcheck={false} />
  // any other attribute (role, aria-*, onfocus, onblur ...) goes to the input unchanged
  // props: value (bindable), type = 'text', id, placeholder, disabled, required, autocomplete, spellcheck, inputmode, ariaLabel, list (id of a <datalist>), maxlength, readonly, autocapitalize, mono (monospace), style, el (bindable: the input element, for focus), onchange, oninput, onkeydown
  let { value = $bindable(''), type = 'text', id = undefined, placeholder = undefined, disabled = false, required = false, autocomplete = undefined,
        spellcheck = undefined, inputmode = undefined, list = undefined, maxlength = undefined, readonly = false, ariaLabel = undefined, onchange = undefined, oninput = undefined,
        onkeydown = undefined, autocapitalize = undefined, mono = false, style = undefined, el = $bindable(), ...rest } = $props();
  const f = getContext('field');
  const req = $derived(required || !!f?.required);
</script>

<input class="input" class:mono bind:this={el} {style} {autocapitalize} {type} id={id ?? f?.id} bind:value {placeholder} {disabled} required={req || undefined} aria-required={req || undefined}
       {autocomplete} {spellcheck} {inputmode} {list} {maxlength} {readonly} aria-label={ariaLabel} aria-describedby={f?.describedby} aria-invalid={f?.invalid || undefined}
       {onchange} {oninput} {onkeydown} {...rest} />
