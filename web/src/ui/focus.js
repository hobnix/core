// Keyboard behaviour of an overlay, kept free of Svelte so it can be tested: which element Tab goes to next, and the use:trapFocus action.
const SEL = 'a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

// Tab inside a list of focusable elements wraps around: from the last to the first (and Shift+Tab the other way).
// `items` are the focusable elements in order, `active` the one that has the focus (or null when it is outside the list).
// Returns the element to focus, or null when the browser may do its normal thing.
export function nextFocus(items, active, shift) {
  if (!items.length) return null;
  const first = items[0], last = items[items.length - 1];
  const i = items.indexOf(active);
  if (i < 0) return shift ? last : first;
  if (shift && active === first) return last;
  if (!shift && active === last) return first;
  return null;
}

export function focusables(root) {
  return [...root.querySelectorAll(SEL)].filter((el) => !el.hidden && el.getClientRects().length > 0);
}

// <div use:trapFocus>: on mount the focus goes to the first element marked [data-autofocus] (else the first focusable one, else the node itself);
// Tab and Shift+Tab stay inside; on destroy the focus returns to what had it before.
export function trapFocus(node) {
  const before = document.activeElement;
  if (!node.hasAttribute('tabindex')) node.setAttribute('tabindex', '-1');
  const start = node.querySelector('[data-autofocus]') ?? focusables(node)[0] ?? node;
  start.focus({ preventScroll: true });
  const key = (e) => {
    if (e.key !== 'Tab') return;
    const to = nextFocus(focusables(node), document.activeElement, e.shiftKey);
    if (to) { e.preventDefault(); to.focus(); }
  };
  node.addEventListener('keydown', key);
  return {
    destroy() {
      node.removeEventListener('keydown', key);
      if (before && before.isConnected && typeof before.focus === 'function') before.focus({ preventScroll: true });
    },
  };
}
