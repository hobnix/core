<script>
  // The preset step: one preset or none (Skip keeps everything minimal). Single parts are the next step (PartsStep).
  import ChoiceList from '../ui/ChoiceList.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { openPlan } from '../ui.svelte.js';
  let { save = $bindable(null) } = $props();
  const list = poll('/api/sys/preset/list', 60000);
  // preset list: name, title, description, capabilities
  const presets = $derived(rows(list).map((r) => ({ id: r[0], label: r[1], text: r[2] === '-' ? '' : r[2] })));
  let picked = $state('');
  // true: nothing chosen, advance; false: a plan was opened
  save = () => {
    const p = presets.find((x) => x.id === picked);
    if (!p) return true;
    openPlan('preset', ['apply', p.id], 'Apply the preset ' + p.label);
    return false;
  };
</script>

<ChoiceList options={presets} value={picked} onpick={(id) => (picked = id)} label="Preset" />
