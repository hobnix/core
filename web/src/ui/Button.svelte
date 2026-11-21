<script>
  import { tip } from './tooltip.svelte.js';
  import { ui, can } from '../ui.svelte.js';
  import { refusal } from '../roles.js';
  import Icon from './Icon.svelte';
  // The button. It knows when it is working: a spinner takes the place of the icon, the label may change (`busyLabel`), the width stays
  // and clicks are ignored (aria-busy, not `disabled`, so the tooltip and the keyboard focus stay).
  //   <Button variant="primary" icon="plus" onclick={add}>Add</Button>
  //   <Button icon="check-circle" busy={jobRunning('routes', ['apply'])} busyLabel="Applying…" onclick={...}>Apply</Button>
  // `busy` is for work the page follows itself (a running job); when onclick returns a promise the button is busy until it settles, so a
  // handler that awaits needs no flag of its own. `tooltip` is the text on hover; a disabled button shows its reason there.
  //   variant: primary | secondary (default) | ghost | danger     size: '' | sm     icon: a Phosphor name without `ph-`, or ''
  //   need: the least role that may use it (viewer | app-manager | admin); a button the role may not use is drawn disabled with the refusal sentence as its tooltip (design 4.9; the server refuses it too)
  //   label: makes it an icon-only button (square, `icon` required): the label is the screen-reader name and the tooltip (unless `tooltip` says more)
  //     <Button variant="ghost" icon="trash" label="Remove {name}" onclick={...} />
  //   reason: why a disabled button is disabled, in a sentence; shown as its tooltip and read by screen readers (a disabled button has no focus, so the
  //     reason is also in the accessible description). A role refusal (`need`) sets its own sentence; `reason` is for every other "not now".
  //   keys: the shortcut shown in the tooltip next to its text (`F5`, `Ctrl R`); the button does not bind it
  //   onbusyclick: called for a click while the button is busy (the click is otherwise ignored); a button of a running job uses it to show that job
  //   class: extra classes of the page (`btn-icon`, a layout class); aria-label, href-less attributes and event handlers go through to the <button>
  let { variant = 'secondary', size = '', icon = '', busy = false, busyLabel = '', disabled = false, tooltip = '', type = 'button', block = false,
        need = '', label = '', reason = '', keys = '', class: extra = '', onclick = null, onbusyclick = null, children, ...rest } = $props();

  const refused = $derived(!!need && !can(need));
  const off = $derived(disabled || refused);
  const why = $derived(refused ? refusal(ui.role, need) : off && reason ? reason : tooltip || label);
  const note = $derived(off ? (refused ? refusal(ui.role, need) : reason) : '');
  const rid = `btn-why-${Math.random().toString(36).slice(2, 8)}`;
  let pending = $state(false);
  const working = $derived(busy || pending);

  async function click(e) {
    if (working) { e.preventDefault(); onbusyclick?.(e); return; }       // a submit button must not submit the form again while it works
    if (off || !onclick) return;
    const r = onclick(e);
    if (r && typeof r.then === 'function') {
      pending = true;
      try { await r; } finally { pending = false; }
    }
  }
</script>

<button {...rest} {type} class="btn btn-{variant} {size} {extra}" class:btn-icon={!!label} class:btn-block={block} class:busy={working} disabled={off} data-refused={refused || undefined} aria-busy={working || undefined}
        aria-label={label || rest['aria-label']} aria-describedby={note ? rid : undefined} aria-disabled={working || undefined} use:tip={keys && why ? { text: why, keys } : why} onclick={click}>
  {#if working}<Icon name="circle-notch" spin />{:else if icon}<Icon name={icon} />{/if}
  {#if working && busyLabel}{busyLabel}{:else}{@render children?.()}{/if}
  {#if note}<span id={rid} class="sr">{note}</span>{/if}
</button>

<style>
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  /* a working button keeps its colours (it is not "disabled") and does not react to the pointer: no hover or press look, only the cursor */
  .busy { cursor: progress; }
  :global(.btn.busy:hover), :global(.btn.busy:active) { filter: none; }
  :global(.btn-secondary.busy:hover), :global(.btn-secondary.busy:active) { background: var(--panel); }
  :global(.btn-ghost.busy:hover), :global(.btn-ghost.busy:active) { background: none; color: var(--fg-2); }
  :global(.btn-primary.busy:hover), :global(.btn-primary.busy:active) { background: var(--accent); }
</style>
