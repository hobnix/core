<script>
  import { getContext } from 'svelte';
  // Native range slider: a hard-edged track filled with the accent up to the value, a square thumb. Inside a <Field> it takes id and
  // aria-describedby from it; on its own it needs `ariaLabel`. `oninput` fires while dragging (live preview), `onchange` when the thumb is released.
  //   <Slider bind:value={size} min={0} max={100} step={5} ariaLabel="Size" oninput={preview} />
  // props: value (bindable), min = 0, max = 100, step = 1, id, disabled, ariaLabel, oninput, onchange
  let { value = $bindable(0), min = 0, max = 100, step = 1, id = undefined, disabled = false, ariaLabel = undefined, oninput = undefined, onchange = undefined } = $props();
  const f = getContext('field');
  const pct = $derived(max > min ? ((Number(value) - min) / (max - min)) * 100 : 0);
</script>

<input class="slider" type="range" id={id ?? f?.id} bind:value {min} {max} {step} {disabled} aria-label={ariaLabel} aria-describedby={f?.describedby}
       aria-invalid={f?.invalid || undefined} style:--p={pct + '%'} {oninput} {onchange} />

<style>
  .slider { -webkit-appearance: none; appearance: none; width: 100%; height: 18px; margin: 0; background: transparent; cursor: pointer; }
  .slider:disabled { opacity: 0.5; cursor: not-allowed; }
  .slider::-webkit-slider-runnable-track { height: 6px; background: linear-gradient(to right, var(--accent) var(--p), var(--panel-3) var(--p)); border: 1px solid var(--line-2); border-radius: 0; }
  .slider::-moz-range-track { height: 6px; background: var(--panel-3); border: 1px solid var(--line-2); border-radius: 0; }
  .slider::-moz-range-progress { height: 6px; background: var(--accent); border-radius: 0; }
  .slider::-webkit-slider-thumb { -webkit-appearance: none; width: 12px; height: 18px; margin-top: -7px; background: var(--fg); border: 1px solid var(--bg); border-radius: 0; }
  .slider::-moz-range-thumb { width: 10px; height: 16px; background: var(--fg); border: 1px solid var(--bg); border-radius: 0; }
  .slider:hover::-webkit-slider-thumb { background: var(--accent-ink); }
  .slider:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
</style>
