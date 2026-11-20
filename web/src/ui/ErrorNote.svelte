<script>
  // The coded error (#488): the code, what happened, the likely reason and one next step, with a link to the guide section.
  // The same note for a refused plan, a failed job and a page that cannot read. A code the web does not know shows the English text it was given.
  //   <ErrorNote code="disk.full" what="Could not write to tank" />        <ErrorNote error={{ code, what, why, next, guide }} />
  // `next` is one command or one page; a command is shown as text to copy, never run from here. `lang` (en|de) picks the guide language; `ondismiss` adds a Dismiss button (a failed job stays on its row until then).
  import Banner from './Banner.svelte';
  import Button from './Button.svelte';
  import { resolveError, guideHref } from './errornote.js';
  let { error = null, code = '', what = '', why = '', next = '', guide = '', lang = 'en', ondismiss = null } = $props();
  const e = $derived(resolveError(error ?? { code, what, why, next, guide }));
  const href = $derived(guideHref(e.guide, lang));
</script>

<Banner tone="bad">
  <strong>{e.what}</strong>{#if e.code} <code class="text-muted">{e.code}</code>{/if}
  {#if e.why}<div>{e.why}</div>{/if}
  {#if e.next}<div><span class="text-muted">Next:</span> <code>{e.next}</code></div>{/if}
  {#if href}<div><a {href} target="_blank" rel="noopener">Read the guide</a></div>{/if}
  {#snippet action()}{#if ondismiss}<Button size="sm" onclick={ondismiss}>Dismiss</Button>{/if}{/snippet}
</Banner>
