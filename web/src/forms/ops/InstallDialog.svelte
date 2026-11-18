<script>
  // ONE Install for every package (recipe, extension, capability): hs sys apps plan|start install <package> (scripts/apps-change.sh, ADR 0027,
  // docs/PLAN-app-lifecycle.md Q2). Screens: the plan (what it makes and needs), the questions (only when there are some), the review, then the
  // job: the steps as a stepper, a question that comes up while it runs, and the result with an Open button. All decisions are in installFlow.js
  // (tested without a browser: tests/web-install-flow.mjs); this file only draws them. Opened with { job } it goes straight to the run of that record.
  // Text and choice answers go as --set, the one secret as a line on standard input (never an argument, never shown). Closing keeps the job running.
  import { onMount } from 'svelte';
  import Button from '../../ui/Button.svelte';
  import Stepper from '../../ui/Stepper.svelte';
  import Banner from '../../ui/Banner.svelte';
  import Field from '../../ui/Field.svelte';
  import TextInput from '../../ui/TextInput.svelte';
  import Select from '../../ui/Select.svelte';
  import Checkbox from '../../ui/Checkbox.svelte';
  import { get, plan as askPlan, start } from '../../api.js';
  import { live } from '../../live.svelte.js';
  import { lang } from '../../lang.svelte.js';
  import { tr } from '../../i18n.js';
  import { ui, track } from '../../ui.svelte.js';
  import { isJobEvent } from '../../jobrecords.js';
  import { activeAsks, choicesOf } from './recipeSteps.js';
  import { isActive, pending, answerError, answerRequest, replyKind, questionLabel, errorLabel, recipeOf } from './recipeQuestions.js';
  import { questionTexts } from './recipeQuestionTexts.js';
  import { parsePlan, pagesOf, hasName, hasForm, progressOf, formIssue, answerIssue, planArgs, startArgs, stdinOf, busyKey, rowsOf, screenOf, stepper,
           lastOf, pkgOf, openUrl, resultRows, failedText, errorMessage } from './installFlow.js';

  let { pkg = '', repo = '', title = '', job = '', onclose = () => { ui.create = null; }, ondone = () => {} } = $props();

  let screen = $state(job ? 'run' : 'plan');   // plan | form | review | run
  let plan = $state(null);                      // the parsed plan
  let loadError = $state('');
  let values = $state({});
  let secret = $state('');
  let own = $state('');
  let askAgain = $state(false);
  let confirm = $state('');
  let runsTouched = $state(false);              // the default of RUNS depends on the container name; the server picks it again unless the person chose
  let tried = $state(false);
  let formError = $state('');                   // the reason a plan with the answers was refused
  let startError = $state('');
  let jobId = $state(job);
  let rec = $state(null);
  let recError = $state('');
  let value = $state('');                       // the answer to a waiting question
  let qTried = $state(false);
  let sendError = $state('');
  let answeredSeq = $state(0);                  // the question this dialog answered: not asked again while the record still shows it
  let lastSeq = 0;
  let last = '';                                // the last step of the job contract seen (a waiting or error step names none)

  const name = $derived(pkg || (rec ? pkgOf(rec, recipeOf) : ''));
  const heading = $derived(title || plan?.title || name);
  const pages = $derived(plan ? pagesOf(plan, tr('Settings')) : []);

  onMount(() => { if (!job) loadPlan(); });

  async function loadPlan() {
    try {
      const p = parsePlan(await askPlan('apps', planArgs(pkg, repo, [], {}, '', false)));
      plan = p;
      const v = {};
      for (const a of p.asks) if (a.kind !== 'secret') v[a.key] = a.def;
      values = v;
    } catch (e) { loadError = e.message || 'The plan could not be read.'; }
  }

  const prog = $derived(plan ? progressOf(plan, screen) : null);
  const issue = $derived(plan ? formIssue(pages, values, secret, own, plan, confirm) : '');
  const why = { required: 'Needed', control: 'No control characters', choice: 'Pick one of the choices', pattern: 'This does not look right', name: 'Lower-case letters, digits and dashes' };
  const errOf = (a) => (tried ? tr(why[answerIssue(a, values, secret)] ?? '') : '');

  function toForm() { screen = hasForm(plan) ? 'form' : 'review'; }
  async function toReview() {
    if (issue) { tried = true; return; }
    formError = '';
    try {
      const p = parsePlan(await askPlan('apps', [...planArgs(pkg, repo, pages, values, own, runsTouched), '--tag', plan.tag]));
      if (!p.ok) { formError = p.reason || 'The plan was refused.'; return; }
      if (p.tag && p.tag !== plan.tag) { formError = 'A newer release was verified meanwhile. Close this window and open it again.'; return; }
      screen = 'review';
    } catch (e) { formError = e.message || 'The plan could not be read.'; }
  }
  async function begin() {
    startError = '';
    try {
      const r = await start('apps', startArgs(plan, pkg, repo, pages, values, own, runsTouched, askAgain), plan.confirmName ? confirm : '', stdinOf(pages, values, secret));
      if (r.status === 'started' && r.job && r.job !== '-') {
        if (r.unit) track(r.unit, `${tr('Install')} ${pkg}`, busyKey(pkg));
        jobId = r.job;
        screen = 'run';
        ondone(r);
      } else if (r.status === 'started') {
        if (r.unit) track(r.unit, `${tr('Install')} ${pkg}`, busyKey(pkg));
        onclose();
        ondone(r);
      } else startError = r.reason || 'The server did not start it.';
    } catch (e) { startError = e.message || 'The server did not start it.'; }
  }

  // --- the run: follow the record (a job.* event; a 3 s timer only while the event stream is down) ---
  async function load() {
    try {
      rec = await get(`/api/sys/jobs/record/${encodeURIComponent(jobId)}`);
      recError = '';
    } catch (e) { recError = e.message || 'The job could not be read.'; }
  }
  $effect(() => { if (jobId) load(); });
  let lastEv = 0;
  $effect(() => {
    if (!jobId) return;
    const ev = live.events.findLast?.(isJobEvent) ?? [...live.events].reverse().find(isJobEvent);
    if (ev && ev.id !== lastEv) { lastEv = ev.id; load(); }
  });
  $effect(() => {
    if (!jobId || live.open) return;
    const t = setInterval(() => { if (!rec || isActive(rec)) load(); }, 3000);
    return () => clearInterval(t);
  });

  const rs = $derived(screenOf(rec, answeredSeq));
  const steps = $derived.by(() => { last = lastOf(rec, last); return stepper(rec, plan?.jobsteps, last); });
  const q = $derived(pending(rec));
  const label = $derived(q ? questionLabel(questionTexts, lang.code, name, q) : '');
  const errText = $derived(q ? errorLabel(questionTexts, lang.code, q) : '');
  $effect(() => { if (q && q.seq !== lastSeq) { lastSeq = q.seq; value = q.kind === 'choice' ? (q.choices.includes(q.def) ? q.def : (q.choices[0] ?? '')) : q.def; qTried = false; sendError = ''; } });
  const bad = $derived(q ? answerError(q, value) : '');
  const result = $derived(rec?.result ?? {});
  const url = $derived(openUrl(result.open));
  const failedStep = $derived(steps.find((s) => s.state === 'failed'));

  async function send() {
    if (!q) return;
    if (bad) { qTried = true; return; }
    const r = answerRequest(jobId, q, value);
    sendError = '';
    try {
      const reply = await start(r.area, r.args, '', r.stdin);
      const k = replyKind(reply);
      if (k === 'done') { answeredSeq = q.seq; value = ''; }
      else if (k === 'refused') sendError = reply.reason || 'The answer was not accepted.';
    } catch (e) { sendError = e.message || 'The answer could not be sent.'; }
    await load();
  }
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<div class="dialog-backdrop" role="presentation" style="z-index:50">
  <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="ind-t" style="width:min(560px,100%)">
    <div class="ind">
      <div>
        <div class="kicker">{tr('Apps')}</div>
        <div id="ind-t" class="dialog-title">{tr('Install')} {heading}</div>
      </div>
      {#if prog}<div class="pt">{tr('Step')} {prog.n} {tr('of')} {prog.of}</div>{/if}

      {#if screen === 'plan'}
        {#if loadError}
          <Banner tone="bad">{loadError}</Banner>
          <div class="nav"><span></span><Button onclick={onclose}>{tr('Close')}</Button></div>
        {:else if !plan}
          <div class="hint"><i class="ph ph-circle-notch spin" aria-hidden="true"></i> {tr('Loading…')}</div>
        {:else if !plan.ok}
          <Banner tone="bad">{plan.reason || tr('This cannot be installed now.')}</Banner>
          <div class="nav"><span></span><Button onclick={onclose}>{tr('Close')}</Button></div>
        {:else}
          <div class="hint">{plan.title || plan.pkg} {plan.version}{#if plan.repo} · {plan.repo}{/if}</div>
          {#if plan.description}<div>{plan.description}</div>{/if}
          {#each plan.dangers as t}<Banner tone="bad">{t}</Banner>{/each}
          {#each plan.warns as t}<Banner tone="warn">{t}</Banner>{/each}
          {#if plan.creates.length}
            <div class="sub">{tr('This creates')}</div>
            <ul class="list">{#each plan.creates as c}<li>{c}</li>{/each}</ul>
          {/if}
          {#if plan.needs.length}
            <div class="sub">{tr('It needs')}</div>
            <ul class="list">
              {#each plan.needs as n (n.name)}
                <li><strong>{n.name}</strong> ({tr(n.state === 'present' ? 'ready' : n.state === 'missing' ? 'missing' : 'is set up with it')}): {n.text}
                  {#if n.long}<Banner tone="warn">{tr('This takes a few minutes: the server is rebuilt.')}</Banner>{/if}</li>
              {/each}
            </ul>
          {/if}
          {#if plan.jobsteps.length}
            <div class="sub">{tr('The steps')}</div>
            <ol class="list">{#each plan.jobsteps as s (s.name)}<li>{s.text}</li>{/each}</ol>
          {/if}
          {#each plan.notes as t}<div class="hint">{t}</div>{/each}
          <div class="nav"><Button onclick={onclose}>{tr('Cancel')}</Button><Button variant="primary" onclick={toForm}>{hasForm(plan) ? tr('Next') : tr('Review')}</Button></div>
        {/if}

      {:else if screen === 'form'}
        {#each pages as p (p.id)}
          {#each activeAsks(p, values) as a (a.key)}
            <Field label={a.label} error={errOf(a)}>
              {#if a.kind === 'secret'}
                <TextInput type="password" bind:value={secret} autocomplete="new-password" spellcheck={false} />
              {:else if a.kind.startsWith('choice:')}
                <Select bind:value={values[a.key]} options={choicesOf(a)} onchange={() => { if (a.key === 'RUNS') runsTouched = true; }} />
              {:else}
                <TextInput bind:value={values[a.key]} placeholder={a.def} autocomplete="off" spellcheck={false} />
              {/if}
            </Field>
          {/each}
        {/each}
        {#if hasName(plan)}
          <Field label={tr('Container name (optional)')} help={tr('Leave the name empty for the usual container. A name of your own runs the recipe a second time, for example a second Jellyfin.')} error={tried && issue === 'name' ? tr(why.name) : ''}>
            <TextInput bind:value={own} placeholder={pkg} autocomplete="off" spellcheck={false} />
          </Field>
        {/if}
        {#if plan.asks.length}
          <Checkbox bind:checked={askAgain} label={tr('Ask every preference again')} hint={tr('Memory, port, share and so on: the setup asks them while it runs, also for an app that exists.')} />
          <div class="hint">{tr('An empty answer takes the default, or the setup asks it while it runs.')} {#if plan.asks.some((a) => a.kind === 'secret')}{tr('The secret goes only into the container, never into the log.')}{/if}</div>
        {/if}
        {#if plan.confirmName}
          <Banner tone="warn">{tr('This package comes from a repository somebody added. Type its name to go on:')} <code>{plan.confirmName}</code></Banner>
          <Field label={tr('Type the name')}><TextInput bind:value={confirm} placeholder={plan.confirmName} autocomplete="off" spellcheck={false} /></Field>
        {/if}
        {#if formError}<Banner tone="bad">{formError}</Banner>{/if}
        <div class="nav"><Button onclick={() => { tried = false; screen = 'plan'; }}><i class="ph ph-arrow-left"></i>{tr('Back')}</Button><Button variant="primary" onclick={toReview}>{tr('Review')}</Button></div>

      {:else if screen === 'review'}
        <div class="hint">{tr('Check your answers, then start. The setup runs as one job; you can close this window and it goes on.')}</div>
        <dl class="rev">
          {#each rowsOf(plan, pages, values, secret, own, pkg) as r (r.label + r.stepId)}
            <dt>{r.label}</dt>
            <dd>{#if r.secret}{r.value ? tr('set (not shown)') : tr('asked while it runs')}{:else}{r.value === '' ? '—' : r.value}{/if}</dd>
          {/each}
          {#if askAgain}<dt>{tr('Ask every preference again')}</dt><dd>{tr('Yes')}</dd>{/if}
        </dl>
        {#if plan.long}<Banner tone="warn">{tr('This takes a few minutes: the server is rebuilt.')}</Banner>{/if}
        {#if startError}<Banner tone="bad">{startError}</Banner>{/if}
        <div class="nav"><Button onclick={() => { screen = hasForm(plan) ? 'form' : 'plan'; }}><i class="ph ph-arrow-left"></i>{tr('Back')}</Button><Button variant="primary" onclick={begin}>{tr('Start')}</Button></div>

      {:else}
        {#if recError && !rec}
          <Banner tone="bad">{tr('The job could not be read.')} {recError}</Banner>
        {:else if !rec}
          <div class="hint"><i class="ph ph-circle-notch spin" aria-hidden="true"></i> {tr('Loading…')}</div>
        {/if}

        {#if rec && rs !== 'result'}
          <Stepper vertical steps={steps.map((s) => ({ label: s.text, state: s.state === 'pending' ? 'todo' : s.state, note: s.phase }))} />
        {/if}

        {#if rs === 'question' && q}
          <div class="sub"><i class="ph ph-hourglass-medium" aria-hidden="true"></i> {tr('Waiting for your answer')}</div>
          <Field label={label} error={errText && !qTried ? errText : qTried && bad ? tr(why[bad] ?? '') : sendError}>
            {#if q.kind === 'secret'}
              <TextInput type="password" bind:value autocomplete="new-password" spellcheck={false} />
            {:else if q.kind === 'choice'}
              <Select bind:value options={q.choices} />
            {:else}
              <TextInput bind:value autocomplete="off" spellcheck={false} placeholder={q.def} />
            {/if}
          </Field>
          <div class="hint">
            {#if q.kind === 'secret'}{tr('The secret goes only into the container, never into the log.')}{:else if q.def}{tr('Leave it empty to use')} <code>{q.def}</code>.{/if}
            {tr('Closing this window does not stop the install: it waits for your answer (the Jobs page opens it again).')}
          </div>
          <div class="nav"><Button onclick={onclose}>{tr('Close')}</Button><Button variant="primary" onclick={send}>{tr('Send')}</Button></div>
        {:else if rs === 'result'}
          <div class="done"><i class="ph ph-check-circle" aria-hidden="true"></i> {result.package && result.package !== '-' ? result.package : name} {result.version && result.version !== '-' ? result.version : ''} {tr('is installed')}</div>
          {#if resultRows(rec).length}
            <dl class="rev">{#each resultRows(rec) as [k, v] (k)}<dt>{tr(k)}</dt><dd>{v}</dd>{/each}</dl>
          {/if}
          <div class="nav">
            <Button onclick={onclose}>{tr('Close')}</Button>
            {#if url}<a class="btn btn-primary" href={url} target="_blank" rel="noopener"><i class="ph ph-arrow-square-out"></i>{tr('Open')}</a>{/if}
          </div>
        {:else if rs === 'failed'}
          <Banner tone="bad">{tr(failedText(rec))}{#if failedStep} {tr('It stopped at:')} {failedStep.text}.{/if}{#if errorMessage(rec)} {errorMessage(rec)}{/if}</Banner>
          <div class="hint">{tr('The Jobs page shows the log.')}</div>
          <!-- step 9 (retry of a failed install) puts its button here -->
          <div class="nav"><span></span><Button onclick={onclose}>{tr('Close')}</Button></div>
        {:else if rec}
          <div class="hint">{tr('A question appears here when the setup needs an answer. You can close this window; the install goes on.')}</div>
          <div class="nav"><span></span><Button onclick={onclose}>{tr('Close')}</Button></div>
        {/if}
      {/if}
    </div>
  </div>
</div>

<style>
  .ind { display: flex; flex-direction: column; gap: 14px; padding: 20px; }
  .hint { font-size: 12px; color: var(--fg-3); }
  .pt { font-size: 12px; color: var(--fg-3); }
  .sub { font-size: 13px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
  .list { margin: 0; padding-left: 18px; font-size: 13px; display: flex; flex-direction: column; gap: 4px; }
  .nav { display: flex; justify-content: space-between; gap: 8px; margin-top: auto; }
  .done { font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
  .rev { display: grid; grid-template-columns: max-content 1fr; gap: 6px 14px; margin: 0; font-size: 13px; }
  .rev dt { color: var(--fg-3); }
  .rev dd { margin: 0; overflow-wrap: anywhere; }
</style>
