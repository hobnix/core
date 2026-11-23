<script>
  // The declared form block (#473): a card that names the form; the button opens the dialog (forms/ops/GenFormDialog.svelte) with the fields and the live plan.
  // A form never changes anything by itself: the submit ends in the plan dialog of the package's own area.
  import Button from '../ui/Button.svelte';
  import Card from '../ui/Card.svelte';
  import Muted from '../ui/Muted.svelte';
  import { openCreate } from '../ui.svelte.js';
  import { areaRole } from '../roles.js';
  import GenFormDialog from '../forms/ops/GenFormDialog.svelte';

  let { block } = $props();
</script>

<Card title={block.title ?? ''}>
  {#if block.text}<Muted as="p">{block.text}</Muted>{/if}
  <div><Button variant="primary" need={areaRole(block.plan?.[0])} onclick={() => openCreate(GenFormDialog, { block })}>{block.submit ?? 'Fill in'}</Button></div>
</Card>
