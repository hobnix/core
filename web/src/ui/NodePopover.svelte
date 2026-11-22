<script>
  // Spike for issue 871: the detail popover of a map node, built on @ui-sdk/svelte (pinned in package.json), drawn with our tokens only (the `.np-*` rules are in base.css: no own style block, tests/web-ratchet.sh).
  // The SDK gives the behaviour (dialog role, focus in and back to the trigger, Escape, press outside, placement, collision); this file gives the look.
  // Props: label (trigger text), title, children (the body). Not used by a page yet: the map (issues 875, 876) is the first user. Docs: docs/adr/0030-ui-sdk-for-the-map.md.
  import { Popover, PopoverTrigger, PopoverContent, PopoverTitle, PopoverClose } from '@ui-sdk/svelte/popover';

  let { label, title, children } = $props();
</script>

<Popover>
  <PopoverTrigger class="np-trigger">{label}</PopoverTrigger>
  <PopoverContent class="np-content" side="bottom" align="start" sideOffset={6}>
    <PopoverTitle class="np-title">{title}</PopoverTitle>
    <div class="np-body">{@render children?.()}</div>
    <PopoverClose class="np-close" aria-label="Close">×</PopoverClose>
  </PopoverContent>
</Popover>
