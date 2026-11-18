<script>
  import StatusDot from './StatusDot.svelte';
  // StepList: the steps of a job, one line each, with the state as a word (not colour alone).
  //   steps    [{ label, state, note }]  state: done | current | todo | failed | skipped (default todo); note = a grey line under the label
  //   compact  one line: only the current step as "2/4 Copying files" (table cells, the job strip)
  //   <StepList steps={[{ label: 'Download', state: 'done' }, { label: 'Install', state: 'current' }, { label: 'Start' }]} />
  // From a job record without step names use stepsFromRecord(step, state) in ./progress.js.
  import { tr } from '../i18n.js';
  let { steps = [], compact = false } = $props();
  const DOT = { done: 'ok', current: 'info', todo: 'off', failed: 'bad', skipped: 'off' };
  const WORD = { done: 'done', current: 'in progress', todo: 'waiting', failed: 'failed', skipped: 'skipped' };
  const st = (s) => (DOT[s.state] ? s.state : 'todo');
  const at = $derived(steps.findIndex((s) => st(s) === 'current' || st(s) === 'failed'));
</script>

{#if compact}
  {#if at >= 0}<span class="one">{at + 1}/{steps.length}{steps[at].label ? ` ${steps[at].label}` : ''}</span>{/if}
{:else}
  <ol class="sl">
    {#each steps as s, i (i)}
      <li class={st(s)} aria-current={st(s) === 'current' ? 'step' : undefined}>
        <StatusDot state={DOT[st(s)]} label={tr(WORD[st(s)])} bare />
        <span class="t">
          <span class="l">{s.label || `${tr('Step')} ${i + 1}`}</span>
          {#if s.note}<span class="n">{s.note}</span>{/if}
        </span>
      </li>
    {/each}
  </ol>
{/if}

<style>
  .sl { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }
  li { display: flex; gap: 10px; align-items: flex-start; }
  li :global(.sd) { margin-top: 4px; }
  .t { display: flex; flex-direction: column; min-width: 0; }
  .todo .l, .skipped .l { color: var(--fg-3); }
  .current .l { font-weight: 600; }
  .failed .l { color: var(--bad); }
  .skipped .l { text-decoration: line-through; }
  .n { font-size: 12px; color: var(--fg-3); }
  .one { font-size: 12px; color: var(--fg-2); }
</style>
