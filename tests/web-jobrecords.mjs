// The job record helpers of the Jobs panel (web/src/jobrecords.js), run with node.
import { parseRecord, stateDot, stateKnown, stepText, percent, progressText, duration, isJobEvent, lastJobEvent, latestOnly, jobChanged, askDiff } from '../web/src/jobrecords.js';
import { readFileSync } from 'node:fs';
let bad = 0;
const check = (n, ok) => { if (!ok) { bad++; console.log('FAIL: ' + n); } };
const run = parseRecord(['20261109-101010-update-abcd', 'update', 'Update', 'running', '-', '2026-11-09T10:10:10Z', '-', '-', '2', '5', 'Fetching', '30', '120', 'files']);
check('running record: step', stepText(run.step) === '2/5 Fetching');
check('running record: progress', run.progress.done === 30 && run.progress.total === 120 && percent(run.progress) === 25);
check('running record: no end, no exit', run.ended === null && run.exit === null);
const bare = parseRecord(['id', '-', '-', 'ok', '-', '-', '-', '0', '-', '-', '-', '-', '-', '-']);
check('record without step and progress', bare.step === null && bare.progress === null && bare.exit === 0 && bare.description === 'id');
check('state dots', stateDot('ok') === 'ok' && stateDot('failed') === 'bad' && stateDot('interrupted') === 'warn' && stateDot('running') === 'info');
check('unknown state is neutral text, not an error', stateDot('brand-new') === 'off' && !stateKnown('brand-new') && stateDot('waiting') === 'warn' && stateKnown('waiting') && stateKnown('cancelled'));
check('percent: no total', percent({ done: 3, total: null }) === null && percent(null) === null);
check('percent: capped', percent({ done: 9, total: 3 }) === 100);
check('progress text with unit', progressText({ done: 1, total: 4, unit: 'files' }) === '1 / 4 files');
check('progress text bytes', progressText({ done: 5, total: 10, unit: 'bytes' }, (n) => n + 'B') === '5B / 10B');
check('duration of an ended job', duration('2026-11-09T10:00:00Z', '2026-11-09T10:02:00Z') === '2 min');
check('duration of a running job', duration('2026-11-09T10:00:00Z', null, Date.parse('2026-11-09T10:00:30Z')) === '30 s');
// a row of the event log has source and kind apart (state-db.py emit splits "job.failed" at the dot); a bug test: the panel once tested kind.startsWith('job.')
check('job events: the real shape (source job, kind apart)', isJobEvent({ source: 'job', kind: 'failed' }) && isJobEvent({ source: 'job', kind: 'queued' }) && !isJobEvent({ source: 'disk', kind: 'removed' }) && !isJobEvent({ source: 'backup', kind: 'ok' }) && !isJobEvent(null));
check('job events: the joined spelling is still understood', isJobEvent({ kind: 'job.failed' }) && !isJobEvent({ kind: 'disk.removed' }));
check('step of an ok job is empty, of a running and a failed job shown', stepText({ n: 3, of: 3, text: 'Done' }, 'ok') === '' && stepText({ n: 3, of: 3, text: 'x' }, 'running') === '3/3 x' && stepText({ n: 2, of: 3, text: 'x' }, 'failed') === '2/3 x');
// a slow read of the running state that comes back after the read of the final state must not win
{
  let shown = null;
  const delays = [50, 5];
  let i = 0;
  const load = latestOnly(() => { const k = i++; return new Promise((r) => setTimeout(() => r(k === 0 ? 'running' : 'ok'), delays[k])); }, (v) => { shown = v; });
  await Promise.all([load(), load()]);
  check('an older read that returns late is dropped', shown === 'ok');
}
// the newest job event is the one the panel acts on; none before the first job of a page (the panel's baseline is then 0, so the first event reads)
{
  const evs = [{ id: 4, source: 'audit', kind: 'ok' }, { id: 5, source: 'job', kind: 'queued' }, { id: 6, source: 'job', kind: 'running' }, { id: 7, source: 'backup', kind: 'ok' }];
  check('lastJobEvent: the newest job row', lastJobEvent(evs)?.id === 6);
  check('lastJobEvent: none without a job row, and for an empty or missing log', lastJobEvent([{ id: 1, source: 'audit', kind: 'ok' }]) === null && lastJobEvent([]) === null && lastJobEvent(undefined) === null);
  check('lastJobEvent: a first job row on a page without any is found (id 5 differs from the baseline 0)', lastJobEvent([{ id: 5, source: 'job', kind: 'queued' }])?.id === 5);
}
// hobnix/server#972: a job that moves through three steps. A step writes no log row, it only counts `reads:jobs-records` up: that alone must read again.
{
  const evs = [{ id: 5, source: 'job', kind: 'running' }];
  let c = jobChanged(evs, 1, { ev: 5, gen: 1 });
  check('jobChanged: nothing new, nothing to read', !c.changed);
  c = jobChanged(evs, 2, c.seen);
  check('jobChanged: step 2 (gen bump, no event) reads again', c.changed && c.seen.gen === 2);
  c = jobChanged(evs, 2, c.seen);
  check('jobChanged: seen again is quiet', !c.changed);
  c = jobChanged(evs, 3, c.seen);
  check('jobChanged: step 3 (gen bump again) reads again', c.changed);
  c = jobChanged([...evs, { id: 6, source: 'job', kind: 'waiting' }], 3, c.seen);
  check('jobChanged: a job event reads again', c.changed && c.seen.ev === 6);
  check('jobChanged: no gen yet is 0, not a change after the baseline', !jobChanged([], undefined, { ev: 0, gen: 0 }).changed);
}
// a job that asks a question raises one toast; it goes when the question is answered or the job ends
{
  const rec = (id, state) => parseRecord([id, 'recipe-bazarr', 'Install bazarr', state, '-', '-', '-', '-', '-', '-', '-', '-', '-', '-']);
  const shown = new Set();
  let d = askDiff([rec('a', 'running')], shown);
  check('askDiff: a running job raises nothing', d.raise.length === 0 && d.dismiss.length === 0);
  d = askDiff([rec('a', 'waiting'), rec('b', 'ok')], shown);
  check('askDiff: a waiting job raises one toast for that job', d.raise.length === 1 && d.raise[0].id === 'a' && d.raise[0].description === 'Install bazarr');
  shown.add('a');
  d = askDiff([rec('a', 'waiting')], shown);
  check('askDiff: not raised twice', d.raise.length === 0 && d.dismiss.length === 0);
  d = askDiff([rec('a', 'running')], shown);
  check('askDiff: answered, the toast goes', d.dismiss.join() === 'a');
  d = askDiff([], shown);
  check('askDiff: a record that is gone dismisses too', d.dismiss.join() === 'a' && askDiff(undefined, new Set()).raise.length === 0);
}
// the layout of the Jobs panel (#973): the record beside the list on wide screens, QuickLook on a phone, never below the list
{

  const src = readFileSync(new URL('../web/src/shell/JobRecords.svelte', import.meta.url), 'utf8');
  check('jobs layout: 60/40 grid', /grid-template-columns:\s*minmax\(0, 3fr\) minmax\(0, 2fr\)/.test(src));
  check('jobs layout: phone uses the QuickLook', /import QuickLook/.test(src) && /<QuickLook[^>]*onclose=\{close\}/.test(src) && /max-width: 860px/.test(src));
  check('jobs layout: the record is not rendered below the table any more', !/<\/Table>\s*<\/div>\s*\{#if open\}\s*<div class="detail">/.test(src));
}
{
  check('skipped: neutral dot, known word', stateDot('skipped') === 'off' && stateKnown('skipped'));
  const jr = readFileSync(new URL('../web/src/shell/JobRecords.svelte', import.meta.url), 'utf8');
  check('Escape closes the record from anywhere (window key handler) and gives the focus back to the row', /<svelte:window onkeydown=\{onWindowKey\}/.test(jr) && /e\.key !== 'Escape'/.test(jr) && /\.focus\(\)/.test(jr));
  check('another part of the shell can select a job (ui.jobSel)', /ui\.jobSel/.test(jr));
}
if (bad) process.exit(1);
