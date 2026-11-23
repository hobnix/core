<script>
  // The action slot on an Apps > Installed row: one main action as a button, the others under More (docs/PLAN-package-pages.md "Slots").
  // Each action opens the core's plan dialog for its own area; the server checks every argument against the package's [[web.changes]].
  import Button from '../ui/Button.svelte';
  import Menu from '../ui/Menu.svelte';
  import { openPlan, ui } from '../ui.svelte.js';
  import { roleOk } from '../roles.js';
  import { actionsOf, planOf, needOf } from './slots.js';

  let { name } = $props();
  const acts = $derived(actionsOf(ui.features.slots, name));
  const run = (a) => openPlan(...planOf(a));
  const items = $derived(acts.more.map((a) => ({ label: a.label, icon: a.icon, danger: !!a.danger, disabled: !roleOk(ui.role, needOf(a)), reason: `Needs the ${needOf(a)} role`, onclick: () => run(a) })));
</script>

{#if acts.main}
  <Button need={needOf(acts.main)} variant="secondary" size="sm" tooltip={acts.main.label} onclick={() => run(acts.main)}>{#if acts.main.icon}<i class="ph ph-{acts.main.icon}"></i>{/if}{acts.main.label}</Button>
  {#if items.length}<Menu {items} label="More actions of {name}" />{/if}
{/if}
