<script>
  import { tr } from '../i18n.js';
  // A short choice of two to four words as joined segments (native radios inside, so the arrow keys work). For a longer explained choice use ChoiceList.
  //   <Segmented bind:value={mode} label="What to add" options={[{ value: 'empty', label: 'Add empty disks' }, { value: 'adopt', label: 'Adopt disks' }]} />
  // props: value (bindable), options [{ value, label, icon?, count? }] (or plain strings), label (aria-label of the group), name (default unique), onchange(value)
  const uid = $props.id();
  let { value = $bindable(''), options = [], label = '', name = `seg-${uid}`, onchange = undefined } = $props();
  const opts = $derived(options.map((o) => (typeof o === 'string' ? { value: o, label: o } : o)));
</script>

<div class="seg" role="radiogroup" aria-label={label ? tr(label) : undefined}>
  {#each opts as o (o.value)}
    <label class="seg-opt"><input type="radio" {name} checked={value === o.value} onchange={() => { value = o.value; onchange?.(o.value); }} />{#if o.icon}<i class="ph ph-{o.icon}" aria-hidden="true"></i>{/if}{tr(o.label)}{#if o.count !== undefined}<span class="cnt">{o.count}</span>{/if}</label>
  {/each}
</div>

<style>
  .seg { max-width: 100%; overflow-x: auto; }
  .cnt { font: 500 10.5px var(--mono); color: var(--fg-3); }
</style>
