<script>
  // A menu behind one button: the More menu of a page header and the row actions of a table.
  //   <Menu label="More" items={[{ label: 'Rename', icon: 'pencil-simple', onclick: rename }, { sep: true }, { label: 'Delete', danger: true, onclick: del },
  //                              { label: 'Move', disabled: true, reason: 'Needs the admin role' }]} />
  // An item the user may not use stays in the list, disabled, with its reason as a tooltip (design 4.9). `icon` is a Phosphor name; `danger` colours it red.
  // The trigger is an icon button ("..." by default; `trigger` snippet to draw your own, it gets { open }). Keys: Enter, Space, ArrowDown open it; arrows, Home, End move;
  // Escape closes and returns the focus to the trigger; Tab closes it; a click outside closes it. The list is fixed-positioned so a table's overflow cannot cut it off.
  import { tip } from './tooltip.svelte.js';
  import { menuNext } from './menu-nav.js';
  let { items = [], label = 'More actions', icon = 'dots-three', align = 'end', trigger } = $props();
  let open = $state(false);
  let btn, list = $state(), pos = $state({ top: 0, left: 0, right: 0, up: false });
  const rows = $derived(items.filter((i) => !i.sep));
  const id = `mn-${Math.random().toString(36).slice(2, 9)}`;

  function place() {
    const r = btn.getBoundingClientRect();
    const up = r.bottom + 200 > window.innerHeight && r.top > window.innerHeight - r.bottom;
    pos = { top: up ? 0 : r.bottom + 4, bottom: up ? window.innerHeight - r.top + 4 : 0, left: r.left, right: window.innerWidth - r.right, up, end: align === 'end' };
  }
  function show(focusLast = false) {
    place(); open = true;
    queueMicrotask(() => { const b = [...list.querySelectorAll('[role=menuitem]')]; (focusLast ? b.findLast((x) => !x.disabled) : b.find((x) => !x.disabled))?.focus(); });
  }
  function hide(back = true) { open = false; if (back) btn?.focus(); }
  const buttons = () => [...list.querySelectorAll('[role=menuitem]')];
  function key(e) {
    if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); hide(); return; }
    if (e.key === 'Tab') { hide(false); return; }
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) return;
    e.preventDefault();
    const b = buttons();
    const to = menuNext(rows.map((r) => ({ disabled: r.disabled })), b.indexOf(document.activeElement), e.key);
    if (to >= 0) b[to].focus();
  }
  function pick(it) { if (it.disabled) return; hide(); it.onclick?.(); }
  $effect(() => {
    if (!open) return;
    const away = (e) => { if (!list?.contains(e.target) && !btn?.contains(e.target)) hide(false); };
    const move = () => hide(false);
    document.addEventListener('mousedown', away, true);
    window.addEventListener('resize', move);
    window.addEventListener('scroll', move, true);
    return () => { document.removeEventListener('mousedown', away, true); window.removeEventListener('resize', move); window.removeEventListener('scroll', move, true); };
  });
</script>

<button bind:this={btn} type="button" class="mn-btn" aria-haspopup="menu" aria-expanded={open} aria-controls={id} aria-label={label} use:tip={label}
  onclick={() => (open ? hide(false) : show())}
  onkeydown={(e) => { if (!open && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) { e.preventDefault(); show(e.key === 'ArrowUp'); } }}>
  {#if trigger}{@render trigger({ open })}{:else}<i class="ph ph-{icon}"></i>{/if}
</button>

{#if open}
  <div bind:this={list} {id} class="mn" role="menu" tabindex="-1" aria-label={label} onkeydown={key}
    style:top={pos.up ? null : `${pos.top}px`} style:bottom={pos.up ? `${pos.bottom}px` : null} style:right={pos.end ? `${pos.right}px` : null} style:left={pos.end ? null : `${pos.left}px`}>
    {#each items as it, n (n)}
      {#if it.sep}<div class="sep" role="separator"></div>
      {:else}
        <button type="button" role="menuitem" class="it" class:danger={it.danger} disabled={it.disabled} use:tip={it.disabled && it.reason ? it.reason : ''} onclick={() => pick(it)}>
          {#if it.icon}<i class="ph ph-{it.icon}"></i>{/if}<span>{it.label}</span>
        </button>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .mn-btn { display: inline-flex; align-items: center; justify-content: center; min-width: 30px; min-height: 30px; padding: 0 6px; border: 1px solid var(--line-2); background: transparent; color: var(--fg-2); cursor: pointer; }
  .mn-btn:hover, .mn-btn[aria-expanded='true'] { color: var(--fg); background: var(--panel-2); }
  .mn { position: fixed; z-index: 60; min-width: 190px; max-width: min(320px, calc(100vw - 16px)); padding: 4px 0; background: var(--panel); border: 1px solid var(--line-2); box-shadow: var(--shadow); outline: none; }
  .it { display: flex; align-items: center; gap: 10px; width: 100%; padding: 8px 14px; border: 0; background: none; color: var(--fg); font: inherit; text-align: left; cursor: pointer; }
  .it:hover:not(:disabled), .it:focus-visible { background: var(--panel-2); outline: none; }
  .it.danger { color: var(--bad-ink); }
  .it:disabled { color: var(--fg-3); cursor: default; }
  .sep { height: 1px; margin: 4px 0; background: var(--line); }
  @media (max-width: 860px) { .it { padding: 12px 16px; } }
</style>
