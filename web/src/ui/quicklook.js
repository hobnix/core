// The rules of the quick look that need no DOM to be tested (tests/web-object.mjs). QuickLook.svelte wires them to the document.
// An element is anything with `closest(selector)` and `contains(node)`; the tests pass fakes.

// Something else is open above the page: a modal dialog (plan, form), a menu, a native dialog. Escape and clicks then belong to that, not to the quick look.
export const OVERLAY = '[aria-modal="true"], [role="menu"], dialog[open]';
export const overlayOpen = (doc) => !!doc.querySelector(OVERLAY);

// Escape closes the quick look when the focus is anywhere in the page, nothing else is open, and nobody has used the key already.
export function closesOnKey(e, doc) {
  return e.key === 'Escape' && !e.defaultPrevented && !e.isComposing && !overlayOpen(doc);
}

// A press outside closes it, except: inside the quick look itself; on a row of the list (that replaces the content: the row's own handler does it); inside an
// overlay (a dialog opened from the quick look, a menu). `row` is the CSS selector of a list row.
export function closesOnPress(target, root, row, doc) {
  if (!target || !root) return false;
  if (root.contains(target)) return false;
  if (row && target.closest?.(row)) return false;
  if (target.closest?.(OVERLAY) || overlayOpen(doc)) return false;
  return true;
}

// The element that gets the focus back when the quick look closes: the row of the selected object if it is still there, else where the focus was when it opened.
export function returnTarget(doc, key, opener) {
  if (key != null && key !== '') {
    const row = doc.querySelector(`[data-k="${String(key).replace(/["\\]/g, '\\$&')}"]`);
    if (row) return row;
  }
  return opener && opener.isConnected ? opener : null;
}
