<script>
  // Progress: one bar for a job or a transfer. Never colour alone: the percent or the text is always next to it.
  //   value, total   done and total in the same unit; no total (or 0) gives the moving "unknown" bar
  //   tone           info (default, running) | ok | warn | bad
  //   label          the accessible name ("Copying photos"), default "Progress"
  //   text           the words beside the bar; default "42 %" (nothing while unknown); text="" hides it
  //   size           md (10 px, default) | sm (6 px, for table cells)
  //   <Progress value={bytesDone} total={bytesTotal} label="Copying" text="1.2 GB of 4 GB" />
  import { tr } from '../i18n.js';
  import { pct } from './progress.js';
  let { value = null, total = null, tone = 'info', label = '', text = undefined, size = 'md' } = $props();
  const p = $derived(pct(value, total));
  const words = $derived(text !== undefined ? text : p === null ? '' : `${p} %`);
</script>

<span class="pg {size}">
  <span class="track {tone}" class:unknown={p === null} role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={p ?? undefined} aria-valuetext={p === null ? tr('in progress') : undefined} aria-label={label || tr('Progress')}>
    <span class="fill" style:width={p === null ? undefined : `${p}%`}></span>
  </span>
  {#if words}<span class="pc">{words}</span>{/if}
</span>

<style>
  .pg { display: inline-flex; align-items: center; gap: 10px; min-width: 0; }
  .track { flex: 1; position: relative; height: 10px; min-width: 60px; background: var(--panel-3); overflow: hidden; -webkit-mask-image: repeating-linear-gradient(90deg, #000 0 4px, transparent 4px 6px); mask-image: repeating-linear-gradient(90deg, #000 0 4px, transparent 4px 6px); }
  .sm .track { height: 6px; min-width: 50px; background: var(--line); -webkit-mask-image: none; mask-image: none; }
  .fill { position: absolute; left: 0; top: 0; bottom: 0; background: var(--info); transition: width 0.4s; }
  .ok .fill { background: var(--ok); }
  .warn .fill { background: var(--warn); }
  .bad .fill { background: var(--bad); }
  .unknown .fill { width: 30%; transition: none; animation: pg-move 1.4s ease-in-out infinite alternate; }
  @keyframes pg-move { from { left: 0; } to { left: 70%; } }
  @media (prefers-reduced-motion: reduce) { .unknown .fill { animation: none; width: 100%; opacity: 0.4; } .fill { transition: none; } }
  .pc { font: 12px var(--mono); color: var(--fg-2); white-space: nowrap; }
</style>
