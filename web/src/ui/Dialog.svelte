<script>
  // The base of every modal overlay: backdrop, a panel with role="dialog", a focus trap, Escape and (optionally) a click on the backdrop.
  // The focus goes to the first [data-autofocus] element, else the first control, and returns to where it was when the dialog closes.
  //   <Dialog title="Delete share" width="540px" onclose={close}>
  //     ...your layout (header, body, footer) ... <input data-autofocus />
  //   </Dialog>
  // The dialog is named by `title` (aria-label) or, when the visible title has an id, by `labelledby`. `dismiss`: a click that starts and ends on the backdrop closes it. Leave it off for a dialog with input
  // or a plan to confirm (the rule in backdrop.js): only Escape and the dialog's own buttons close those.
  // A press on the backdrop never takes the focus out of the dialog, so Escape keeps working. An Escape is consumed by the topmost dialog only, so a dialog opened from a dialog closes first.
  import { backdropClose } from './backdrop.js';
  import { trapFocus } from './focus.js';
  let { title = '', labelledby = '', width = '540px', dismiss = false, panel = '', onclose = () => {}, children } = $props();
  const noop = () => {};
</script>

<div class="dialog-backdrop" role="presentation" onmousedown={(e) => e.target === e.currentTarget && e.preventDefault()} use:backdropClose={dismiss ? onclose : noop}>
  <div class="dlg {panel}" style:width="min({width}, 100%)" role="dialog" tabindex="-1" aria-modal="true" aria-label={title || undefined} aria-labelledby={labelledby || undefined}
    use:trapFocus onkeydown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); onclose(); } }}>
    {@render children?.()}
  </div>
</div>

<style>
  .dlg { position: relative; max-height: calc(100dvh - 32px); display: flex; flex-direction: column; overflow: hidden; background: var(--panel); border: 1px solid var(--line-2); border-radius: var(--r); box-shadow: 0 24px 64px oklch(0 0 0 / 0.5); outline: none; }
</style>
