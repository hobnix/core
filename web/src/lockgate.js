// What happens when the storage locks or opens (shell/Shell.svelte). Each change runs its function once: onLock when it turns locked, onUnlock when
// it turns open, also the second time. `known` false = no answer yet, nothing runs. Plain JS: tests/web-session-reads.mjs runs it in node.
export function lockGate(onLock, onUnlock) {
  let last = null;
  return (known, locked) => {
    if (!known || locked === last) return;
    last = locked;
    if (locked) onLock();
    else onUnlock();
  };
}
