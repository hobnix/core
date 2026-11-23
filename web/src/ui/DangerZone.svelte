<script>
  // The marked section at the bottom of an Object page: actions that destroy or cannot be undone. Each action opens a plan (the plan asks for the NAME of the
  // thing that changes, CLAUDE.md "Destructive commands"); this component never runs anything itself.
  //   <DangerZone actions={[{ label: 'Remove pool…', text: 'Frees the disks. The data on them is lost.', area: 'pool', args: ['destroy', name], title: 'Remove pool ' + name, need: 'admin' }]} />
  // An action: { label, text, area, args, title?, need?, disabled?, reason?, onclick? } (`reason` is why it is off, shown as its tooltip). `onclick` replaces the plan: a form that asks for the name itself.
  import Button from './Button.svelte';
  import { openPlan } from '../ui.svelte.js';
  let { actions = [], title = 'Danger zone' } = $props();
</script>

{#if actions.length}
  <section class="dz" aria-label={title}>
    <h3><i class="ph ph-warning" aria-hidden="true"></i> {title}</h3>
    {#each actions as a (a.label)}
      <div class="item">
        <p>{a.text}</p>
        <Button variant="danger" need={a.need ?? ''} disabled={a.disabled} tooltip={a.disabled ? (a.reason ?? '') : ''} onclick={() => (a.onclick ? a.onclick() : openPlan(a.area, a.args, a.title ?? a.label))}>{a.label}</Button>
      </div>
    {/each}
  </section>
{/if}

<style>
  .dz { display: flex; flex-direction: column; gap: var(--space-3); padding: var(--space-6); border: 1px solid color-mix(in oklab, var(--bad) 45%, var(--line)); border-radius: var(--r); background: color-mix(in oklab, var(--bad) 5%, var(--panel)); }
  h3 { margin: 0; display: flex; align-items: center; gap: var(--space-3); font-size: 14px; font-weight: 500; color: var(--bad); }
  .item { display: flex; align-items: center; gap: var(--space-6); justify-content: space-between; flex-wrap: wrap; padding-top: var(--space-3); border-top: 1px solid color-mix(in oklab, var(--bad) 25%, var(--line)); }
  .item p { margin: 0; flex: 1; min-width: 200px; font-size: 13px; color: var(--fg-2); }
</style>
