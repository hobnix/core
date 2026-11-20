<script>
  // Draws the toasts of toast.svelte.js, bottom right (full width on a phone). Mount it once, in the shell. A toast is a live region: a screen reader
  // hears it without the focus moving; a job that asks for input is announced as an alert. Each toast has a close button and an optional link.
  import { toasts, dismissToast } from './toast.svelte.js';
  import Button from './Button.svelte';
</script>

<div class="toasts" aria-label="Notifications">
  {#each toasts.list as t (t.id)}
    <div class="toast {t.kind}" role={t.kind === 'ask' || t.kind === 'bad' ? 'alert' : 'status'}>
      {#if t.busy}<i class="ph ph-circle-notch spin" aria-hidden="true"></i>{:else}<i class="ph ph-{t.kind === 'ask' ? 'question' : t.kind === 'ok' ? 'check-circle' : t.kind === 'bad' ? 'warning-circle' : 'info'}" aria-hidden="true"></i>{/if}
      <div class="msg">
        <b>{t.title}</b>
        {#if t.text}<span>{t.text}</span>{/if}
        {#if t.action}<Button size="sm" onclick={() => { dismissToast(t.id); t.action(); }}>{t.actionLabel}</Button>{/if}
        {#if t.href}<a href={t.href} onclick={() => dismissToast(t.id)}>{t.linkLabel}</a>{/if}
      </div>
      <button type="button" class="x" aria-label="Dismiss" onclick={() => dismissToast(t.id)}><i class="ph ph-x"></i></button>
    </div>
  {/each}
</div>

<style>
  .toasts { position: fixed; right: 16px; bottom: 16px; z-index: 70; display: flex; flex-direction: column; gap: 8px; width: min(380px, calc(100vw - 32px)); pointer-events: none; }
  .toast { pointer-events: auto; display: flex; gap: 10px; align-items: flex-start; padding: 12px 12px 12px 14px; background: var(--panel); border: 1px solid var(--line-2); border-left: 3px solid var(--line-2); box-shadow: var(--shadow); }
  .toast.ask { border-left-color: var(--warn, var(--h1)); }
  .toast.ok { border-left-color: var(--ok); }
  .toast.bad { border-left-color: var(--bad); }
  .msg { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; font-size: 13px; color: var(--fg-2); }
  .msg b { color: var(--fg); font-weight: 600; overflow-wrap: anywhere; }
  .msg a { align-self: flex-start; color: var(--fg); text-decoration: underline; }
  .x { flex: none; border: 0; background: none; color: var(--fg-3); cursor: pointer; padding: 2px; }
  .x:hover { color: var(--fg); }
  @media (max-width: 860px) { .toasts { left: 16px; right: 16px; width: auto; bottom: 64px; } }
</style>
