<script>
  // What the server is for: one step with three choices, only the core, one blueprint (hs sys blueprint) or single parts (PartsStep). A blueprint is
  // shown as a plan first and applied as one background job; it only fills what is not set yet. Blueprint texts come from a package repository:
  // they are shown as plain text only.
  import ChoiceList from '../ui/ChoiceList.svelte';
  import Banner from '../ui/Banner.svelte';
  import PartsStep from './PartsStep.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { openPlan } from '../ui.svelte.js';
  import { blueprintRows, setupOptions, blueprintOf } from './blueprints.js';
  let { save = $bindable(null) } = $props();
  const list = poll('/api/sys/blueprint/list', 60000, 'blueprint-list');
  const blueprints = $derived(blueprintRows(rows(list)));
  const options = $derived(setupOptions(blueprints));
  let picked = $state('');
  let partsSave = $state(null);
  // true: nothing to do, advance; false: a plan was opened
  save = () => {
    if (picked === 'parts') return partsSave ? partsSave() : true;
    const b = blueprintOf(blueprints, picked);
    if (!b) return true;
    openPlan('blueprint', ['apply', b.name], 'Apply the blueprint ' + b.title);
    return false;
  };
</script>

<ChoiceList {options} value={picked} onpick={(id) => (picked = id)} label="What is this server for?" />
{#if !blueprints.length}
  <Banner tone="info">The repositories offer no blueprint yet. Take only the core, or choose parts.</Banner>
{/if}
{#if picked === 'parts'}<PartsStep bind:save={partsSave} />{/if}
