<script>
  import Button from '../ui/Button.svelte';
  import TextInput from '../ui/TextInput.svelte';
  import { onMount } from 'svelte';
  import { plan as askPlan, start as doStart } from '../api.js';
  import { ui, starting, track, trackDone, showTab, openPlan } from '../ui.svelte.js';
  import { toast, dismissToast } from '../ui/toast.svelte.js';
  import { offersRebuild, effectOf } from './effect.js';
  import { jobKey } from '../jobkey.js';
  import { tr } from '../i18n.js';
  import PlanSteps from './PlanSteps.svelte';
  import Halftone from './Halftone.svelte';
  import Chip from '../ui/Chip.svelte';
  import Checkbox from '../ui/Checkbox.svelte';
  import Skeleton from '../ui/Skeleton.svelte';
  import Dialog from '../ui/Dialog.svelte';

  let { dialog } = $props();            // { area, args, title, option?: { label, args } } (option = a checkbox that adds its args and asks the plan again)

  let p = $state(null);                 // the plan, as the backend parsed it
  let loadError = $state(dialog.refused ?? '');   // refused: this role may not make the change (ui.svelte.js openPlan), nothing is asked
  let confirm = $state('');
  let busy = $state(false);
  let startError = $state('');
  let extra = $state(false);            // the option checkbox
  const args = $derived(extra && dialog.option ? [...dialog.args, ...dialog.option.args] : dialog.args);
  let saved = $state(!!dialog.saved);   // a change was written and waits for a rebuild: say so, offer "Rebuild now" (no plan is asked)

  const savedText = $derived(effectOf(p?.steps)?.text ?? 'This takes effect with hs rebuild.');
  const danger = $derived(!!p?.steps.some((s) => s[0] === 'danger'));
  const allowed = $derived(p?.status === 'ok');
  const canStart = $derived(allowed && !busy && (!p.confirm_name || confirm === p.confirm_name));
  const kicker = $derived(p && !allowed ? 'Plan · refused' : danger ? 'Plan · danger' : 'Plan');

  let asked = 0;                        // a newer question makes an older answer stale
  function load() {
    const n = ++asked;
    p = null; loadError = ''; startError = ''; confirm = '';
    askPlan(dialog.area, args, undefined, undefined, undefined, dialog.document)
      .then((r) => { if (n === asked) p = r; }, (e) => { if (n === asked) loadError = e.message; });
  }

  onMount(() => {
    if (saved || dialog.refused) return;
    let open = true;       // the answer may be one a button already asked for (prefetchPlan): it is not cancelled with the dialog
    askPlan(dialog.area, args, undefined, undefined, undefined, dialog.document)
      .then((r) => { if (open && asked === 0) p = r; }, (e) => { if (open && asked === 0) loadError = e.message; });
    return () => { open = false; };
  });

  function close() { ui.dialog = null; }

  // Start closes the dialog at once; a toast reports the change (pending, started, done, refused). The one exception is a change that is saved
  // and waits for a rebuild: that asks a question, so its dialog stays. A refusal has to travel with the toast, so "Show plan" opens the dialog again.
  async function go() {
    const { area, title: dtitle, document } = dialog;
    const name = dtitle || p.heading || 'Change';
    const ask = p.confirm_name ? confirm : '';
    const stay = area !== 'system' && offersRebuild(p.steps);
    const tkey = `start:${jobKey(area, args)}`;
    const steps = p.steps ?? [];
    const again = () => openPlan(area, args, dtitle);
    if (stay) { busy = true; startError = ''; } else { close(); }
    toast({ key: tkey, kind: 'info', title: `${name}…`, busy: true });
    const pk = jobKey(area, args);
    starting.keys.push(pk);
    try {
      const r = await doStart(area, args, ask, undefined, undefined, document);
      if (r.status === 'started' && r.unit) {
        track(r.unit, name, jobKey(area, args));
        toast({ key: tkey, kind: 'info', title: name, text: tr('Running in the background.'), action: () => showTab('tasks'), actionLabel: tr('Open Tasks') });
      } else if (r.status === 'done') {
        trackDone(name, steps);
        if (stay) { saved = true; dismissToast(tkey); }
        else toast({ key: tkey, kind: 'ok', title: `${name}: ${tr('done')}` });
      } else {
        const why = r.reason || tr('The server did not start it.');
        if (stay) { startError = why; dismissToast(tkey); }
        else toast({ key: tkey, kind: 'bad', title: `${name} ${tr('was refused')}`, text: why, action: again, actionLabel: tr('Show plan') });
      }
    } catch (e) {
      if (stay) { startError = e.message; dismissToast(tkey); }
      else toast({ key: tkey, kind: 'bad', title: `${name} ${tr('failed to start')}`, text: e.message, action: again, actionLabel: tr('Show plan') });
    } finally {
      const i = starting.keys.indexOf(pk);
      if (i >= 0) starting.keys.splice(i, 1);
      busy = false;
    }
  }
</script>

<Dialog labelledby="pdt" width="540px" onclose={close}>
  <div class="pdlg" class:danger>
    {#if danger}<div class="stripe"></div>{/if}
    <div class="dh">
      <!-- halftone slot: the dialog header (not for a danger plan, whose header is tinted red) -->
      {#if !danger}<Halftone cell={3} focus={[1, 0]} reach={0.9} opacity={0.75} />{/if}
      <div class="dtop">
        <span class="eyebrow" class:bad={danger}>{kicker}</span>
        <span class="grow"></span>
        <Chip kind="strong">{ui.host}</Chip>
      </div>
      <h3 id="pdt">{saved ? 'Saved' : p?.heading || dialog.title || 'Plan'}</h3>
    </div>
    <div class="dbody">
      {#if saved}
        <PlanSteps steps={[['note', savedText]]} />
        <div class="lede">The server runs as before until it is rebuilt. Later changes queue up with this one: a banner on every page lists them, and one rebuild applies them all.</div>
      {:else if loadError}
        <div class="refused"><i class="ph ph-warning-circle"></i>{loadError}</div>
      {:else if !p}
        <Skeleton lines={3} />
        <div class="lede">Asking the server what would happen…</div>
      {:else if !allowed}
        <div class="refused"><i class="ph ph-prohibit"></i>{p.reason || 'The server refused this.'}</div>
        {#each p.fixes ?? [] as f}<div class="lede">To make it possible, run <code class="cmd">{f}</code></div>{/each}
        <div class="lede">Nothing has run.</div>
      {:else}
        <PlanSteps steps={p.steps} long={p.long} />
        {#if p.command}<code class="cmd">{p.command}</code>{/if}
      {/if}
      {#if dialog.option && !saved && !loadError}
        <Checkbox bind:checked={extra} label={dialog.option.label} onchange={load} />
      {/if}
      {#if startError}<div class="refused"><i class="ph ph-warning-circle"></i>{startError}</div>{/if}
    </div>
    {#if !saved && allowed && p.confirm_name}
      <div class="confirm">
        <label for="cf">Type <code>{p.confirm_name}</code> to confirm</label>
        <TextInput id="cf" bind:value={confirm} placeholder={p.confirm_name} autocomplete="off" spellcheck={false} />
      </div>
    {/if}
    {#if saved}
    <div class="dfoot">
      <span class="note"></span>
      <Button onclick={close}>Later</Button>
      <Button variant="primary" onclick={() => { close(); openPlan('system', ['rebuild'], 'Rebuild now'); }}><i class="ph ph-hammer"></i>Rebuild now…</Button>
    </div>
    {:else}
    <div class="dfoot">
      <span class="note">{allowed ? 'Nothing has run yet. The result appears under Jobs.' : ''}</span>
      <Button onclick={close}>{allowed ? 'Cancel' : 'Close'}</Button>
      {#if !allowed && (p?.reason?.includes('changed meanwhile') || startError.includes('changed meanwhile')) && dialog.onReload}
        <Button variant="primary" onclick={() => { const cb = dialog.onReload; close(); cb(); }}>Reload</Button>
      {/if}
      {#if allowed}
        <Button variant={danger ? 'danger' : 'primary'} tooltip={canStart ? '' : p.confirm_name && confirm !== p.confirm_name ? 'Type the name to confirm first' : busy ? 'Starting' : 'This change cannot be started now'} disabled={!canStart} onclick={() => { go(); }}>
          <i class="ph ph-play"></i>{busy ? 'Starting…' : 'Start job'}
        </Button>
      {/if}
    </div>
    {/if}
  </div>
</Dialog>

<style>
  .pdlg { display: flex; flex-direction: column; min-height: 0; flex: 1; }
  .stripe { position: absolute; left: 0; right: 0; top: 0; height: 3px; background: var(--bad); z-index: 2; }
  .dh { position: relative; flex: none; padding: 20px 22px 14px; border-bottom: 1px solid var(--line); overflow: hidden; }
  .pdlg.danger .dh { background: color-mix(in oklch, var(--bad) 10%, var(--panel)); }
  .dtop { position: relative; display: flex; align-items: center; gap: 8px; }
  .eyebrow.bad { color: var(--bad-ink); }
  h3 { position: relative; margin: 6px 0 0; font-size: 18px; font-weight: 600; letter-spacing: -0.02em; }
  .dbody { padding: 8px 22px 14px; overflow: auto; min-height: 0; display: flex; flex-direction: column; gap: 10px; }
  .lede { font-size: 12.5px; color: var(--fg-3); }
  .cmd { display: block; font-size: 12px; padding: 10px 12px; border: 1px solid var(--line); background: var(--panel-2); color: var(--fg-2); white-space: pre-wrap; overflow-wrap: anywhere; }
  .refused { display: flex; gap: 8px; align-items: flex-start; font-size: 13px; color: var(--bad-ink); padding-top: 8px; }
  .confirm { padding: 14px 22px; border-top: 1px solid var(--line); }
  .confirm label { display: block; margin-bottom: 6px; font: 500 11px var(--mono); letter-spacing: 0.08em; text-transform: uppercase; color: var(--fg-3); }
  .confirm code { color: var(--fg); text-transform: none; letter-spacing: 0; }
  .confirm :global(.input) { border-color: color-mix(in oklch, var(--bad) 55%, var(--line-2)); font-family: var(--mono); }
  .dfoot { flex: none; display: flex; align-items: center; gap: 8px; justify-content: flex-end; flex-wrap: wrap; padding: 14px 22px; background: var(--panel-2); border-top: 1px solid var(--line); }
  .note { flex: 1; min-width: 180px; color: var(--fg-3); font-size: 12.5px; }
</style>
