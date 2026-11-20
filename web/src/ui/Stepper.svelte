<script>
  import { tr } from '../i18n.js';
  import { normalize, canSelect } from './stepper.js';
  // Stepper: the steps of a flow, each with its number or mark and its name. The state is a word for screen readers and a mark for the eye
  // (a check, a cross, a dot), never colour alone. It sits under Wizard (`<Wizard steps={[...]}>`) and stands alone where a list of steps is shown.
  //   steps       [{ label, state, note }] or just labels; state: done | current | todo | failed (default todo); note = a grey word after the label
  //   vertical    one step per line (a job's steps in a dialog, the incident steps); default is a row that wraps, and on a phone shows the
  //               current step only
  //   onselect(i) a done step becomes a button that goes back to it (0-based); without it the steps are plain text
  //   <Stepper steps={['Image', 'Ports', 'Folders']} ... />   <Stepper vertical steps={[{ label: 'Download', state: 'done' }, { label: 'Install', state: 'current' }]} />
  // To build the steps from "the current one is index i" use stepsAt(labels, i) in ./stepper.js.
  let { steps = [], vertical = false, onselect = null } = $props();
  const list = $derived(normalize(steps));
  const MARK = { done: 'check', failed: 'x' };
  const WORD = { done: 'done', current: 'current step', todo: 'not yet', failed: 'failed' };
</script>

<ol class="st" class:v={vertical}>
  {#each list as s, i (i)}
    <li class="{s.state}" aria-current={s.state === 'current' ? 'step' : undefined}>
      {#if canSelect(s, onselect)}
        <button type="button" class="it" onclick={() => onselect(i)}>
          <span class="mk"><i class="ph ph-{MARK.done}" aria-hidden="true"></i></span>
          <span class="lb">{s.label}</span><span class="sr">({tr(WORD[s.state])})</span>
        </button>
      {:else}
        <span class="it">
          <span class="mk">{#if MARK[s.state]}<i class="ph ph-{MARK[s.state]}" aria-hidden="true"></i>{:else}{s.n}{/if}</span>
          <span class="lb">{s.label}</span><span class="sr">({tr(WORD[s.state])})</span>
        </span>
      {/if}
      {#if s.note}<span class="note">· {s.note}</span>{/if}
    </li>
  {/each}
</ol>

<style>
  .st { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 6px 18px; font-size: 13px; }
  .st.v { flex-direction: column; flex-wrap: nowrap; gap: 6px; }
  li { display: flex; align-items: center; gap: 6px; color: var(--fg-3); min-width: 0; }
  .it { display: inline-flex; align-items: center; gap: 8px; min-width: 0; color: inherit; font: inherit; padding: 0; border: 0; background: none; }
  button.it { cursor: pointer; }
  button.it:hover .lb { text-decoration: underline; }
  .mk { flex: none; width: 20px; height: 20px; display: inline-grid; place-items: center; border: 1px solid var(--line-2); font-size: 11px; font-variant-numeric: tabular-nums; }
  .done { color: var(--fg-2); }
  .done .mk { border-color: var(--ok); color: var(--ok); }
  .current { color: var(--fg); font-weight: 600; }
  .current .mk { border-color: var(--accent); background: var(--accent); color: var(--bg); }
  .failed { color: var(--bad); font-weight: 600; }
  .failed .mk { border-color: var(--bad); color: var(--bad); }
  .note { font-size: 12px; font-weight: 400; color: var(--fg-3); }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  @media (max-width: 860px) { .st:not(.v) li:not(.current) { display: none; } }
</style>
