<script>
  // The Optional parts step: capability packages of the signed repositories. The ticked ones are installed with what they require, switched on
  // and built in ONE job (area pkg/bundle, scripts/pkg-bundle.sh); nothing happens before the plan is confirmed. No rows (the repositories were
  // not read yet, or there is no network): the step says so and Next moves on.
  import Checkbox from '../ui/Checkbox.svelte';
  import Chip from '../ui/Chip.svelte';
  import Banner from '../ui/Banner.svelte';
  import Button from '../ui/Button.svelte';
  import { poll, rows } from '../data.svelte.js';
  import { openPlan } from '../ui.svelte.js';
  import { capRows, bundleArg } from './parts.js';
  let { save = $bindable(null) } = $props();
  const list = poll('/api/sys/pkg/capabilities', 60000, 'pkg-market');
  const caps = $derived(capRows(rows(list)));
  let picked = $state({});
  // true: nothing ticked, advance; false: a plan was opened
  save = () => {
    const arg = bundleArg(caps, picked);
    if (!arg) return true;
    openPlan('pkg/bundle', [arg], 'Install and switch on ' + arg.split(',').join(', '));
    return false;
  };
</script>

{#if !caps.length}
  <Banner tone="info">No optional parts are offered yet. Reading the signed repositories needs the network; you can add parts later with hs pkg install.</Banner>
  <div><Button tooltip="Read the package repositories again (needs the network)" onclick={() => openPlan('pkg', ['fetch'], 'Read the repositories')}>Read the repositories</Button></div>
{:else}
  {#each caps as c (c.name)}
    <Checkbox checked={!!picked[c.name]} disabled={c.installed} label={c.title} onchange={(e) => { picked[c.name] = e.target.checked; }}>
      <span>{c.title}{#if c.installed} <Chip>installed</Chip>{/if}{#each c.requires as r (r)} <Chip>needs {r}</Chip>{/each}</span>
    </Checkbox>
  {/each}
  <p class="muted">What a part needs is installed or switched on with it. The job ends with a rebuild of the server.</p>
{/if}
