<script>
  // The base of the server-aware form fields (ShareField, DiskField, PoolField, InstanceField, UserField): a searchable Combobox over the things the
  // server has, with the states a plain dropdown hides. The fields do the reading and the parsing; this draws it.
  //   loading   a line "Loading ..." and a disabled box, never an empty list that looks like "nothing exists"
  //   error     a line that says the list could not be read; with `free` the name can still be typed
  //   empty     "No <things> yet." with a link to where one is made (`createHref`)
  //   no match  inside the list ("Nothing matches.")
  // props: options [{ value, label, detail?, group?, disabled? }], loaded, error (truthy), noun ('shares'), createHref, createLabel, free, value (bindable), wide, label, id, placeholder, disabled, onchange
  import { getContext } from 'svelte';
  import Combobox from './Combobox.svelte';
  import Muted from './Muted.svelte';
  import { url, go } from '../route.svelte.js';

  let { options = [], loaded = true, error = '', noun = 'items', createHref = '', createLabel = 'Create one', free = false, value = $bindable(''), wide = true, label = '', id = undefined,
        placeholder = 'Choose…', disabled = false, onchange = null } = $props();
  const f = getContext('field');
  const empty = $derived(loaded && !error && !options.length);
  const link = (e) => { if (!(e.metaKey || e.ctrlKey || e.shiftKey || e.button)) { e.preventDefault(); go(createHref); } };
</script>

<div class="sf">
  <Combobox {options} bind:value {wide} {label} id={id ?? f?.id} {onchange} search {free} placeholder={!loaded ? 'Loading…' : placeholder}
            disabled={disabled || (!free && (!loaded || !!error || empty))} />
  {#if !loaded}
    <Muted as="p" role="status">Loading {noun}…</Muted>
  {:else if error}
    <Muted as="p" role="alert">The {noun} could not be read.{free ? ' You can still type a name.' : ''}</Muted>
  {:else if empty}
    <Muted as="p" role="status">No {noun} yet.{#if createHref} <a href={url(createHref)} onclick={link}>{createLabel}</a>{/if}</Muted>
  {/if}
</div>

<style>
  .sf { display: flex; flex-direction: column; gap: 4px; }
</style>
