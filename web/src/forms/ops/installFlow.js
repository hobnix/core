// The logic of the One Install dialog (InstallDialog.svelte, docs/PLAN-app-lifecycle.md Q2, step 8b), as plain functions so node can test it
// (tests/web-install-flow.mjs). The dialog only renders what these return. Backend: scripts/apps-change.sh (`hs sys apps plan|start install`).
//
// Screens: plan -> form (only when there is something to answer) -> review -> run -> result. The job record decides the last two (screenOf).
// The questions and answers reuse recipeSteps.js (pages, checks, --set arguments) and recipeQuestions.js (the waiting question of the record).
import { buildSteps, answerArgs, secretOf, reviewRows, askError, activeAsks, nameError } from './recipeSteps.js';
import { phase, pending } from './recipeQuestions.js';
import { jobKey } from '../../jobkey.js';

const dash = (v) => (v === '-' || v === undefined || v === null ? '' : String(v));

// one `ask` line of the plan (key, label, kind, choices, default, pattern, when; dash = none) -> the ask shape of recipeSteps.js
export function askOf(a) {
  const choices = dash(a[3]);
  const kind = a[2] === 'choice' ? `choice:${choices}` : a[2] === 'secret' ? 'secret' : 'text';
  return { key: a[0], label: a[1], kind, def: kind === 'secret' ? '' : dash(a[4]), pattern: dash(a[5]), when: dash(a[6]) };
}

// the plan answer of the web server (parse_change) -> what the dialog shows
export function parsePlan(p) {
  const lines = p?.steps ?? [];
  const of = (k) => lines.filter((x) => x[0] === k).map((x) => x[1]);
  return {
    ok: !!p && p.status !== 'refused',
    reason: p?.reason ?? '',
    heading: p?.heading ?? '',
    pkg: p?.package ?? '', kind: p?.kind ?? '', repo: p?.repo ?? '', version: p?.version ?? '', tag: p?.tag ?? '', title: p?.title ?? '', description: p?.description ?? '',
    creates: p?.creates ?? [],
    needs: (p?.needl ?? []).map((n) => ({ name: n[0], state: n[1], text: n[2], long: n[3] === 'yes' })),
    asks: (p?.asks ?? []).map(askOf),
    jobsteps: (p?.jobsteps ?? []).map((s) => ({ name: s[0], text: s[1] })),
    notes: of('note'), warns: of('warn'), dangers: of('danger'), infos: of('step'),
    confirmName: p?.confirm_name ?? '',
    long: !!p?.long || (p?.needl ?? []).some((n) => n[3] === 'yes'),
  };
}

// the questions of the plan as pages (one page: the questions all belong to the package); the container name is only for a recipe
export const pagesOf = (plan, label = 'Settings') => buildSteps(plan.asks, [], { label, help: '' });
export const hasName = (plan) => plan.kind === 'recipe';
export const hasForm = (plan) => plan.asks.length > 0 || hasName(plan) || plan.confirmName !== '';
// the screens of this plan in order; the result shows as the last one
export const screensOf = (plan) => ['plan', ...(hasForm(plan) ? ['form'] : []), 'review', 'run'];
export const progressOf = (plan, screen) => {
  const list = screensOf(plan);
  const i = Math.max(0, list.indexOf(screen === 'result' ? 'run' : screen));
  return { n: i + 1, of: list.length };
};

// '' when an answer may be sent: empty is fine (the job asks it again or takes the default), a given one is checked as recipeSteps.js does
export function answerIssue(a, values, secret) {
  if (a.kind === 'secret') return secret === '' ? '' : askError(a, values, secret);
  return (values[a.key] ?? '') === '' ? '' : askError(a, values, secret);
}
export const formIssue = (pages, values, secret, own, plan, confirm) => {
  if (pages.some((s) => activeAsks(s, values).some((a) => answerIssue(a, values, secret) !== ''))) return 'answer';
  if (hasName(plan) && nameError(own.trim()) !== '') return 'name';
  if (plan.confirmName && confirm !== plan.confirmName) return 'confirm';
  return '';
};

// the arguments of the plan (area apps): the questions answered so far go as --set, so the plan checks them
export function planArgs(pkg, repo, pages, values, own, runsTouched) {
  const a = ['install', pkg];
  if (repo) a.push('--repo', repo);
  const n = own.trim();
  if (n) a.push('--name', n);
  return a.concat(answerArgs(pages, values, n, runsTouched));
}
// the arguments of the start: the plan adds --tag (the release the plan showed); the one secret goes on stdin, never here
export function startArgs(plan, pkg, repo, pages, values, own, runsTouched, askAgain) {
  const a = ['install', pkg, '--tag', plan.tag];
  if (repo) a.push('--repo', repo);
  const n = own.trim();
  if (n) a.push('--name', n);
  a.push(...answerArgs(pages, values, n, runsTouched));
  if (askAgain) a.push('--ask');
  return a;
}
export const stdinOf = (pages, values, secret) => secretOf(pages, values, secret);
// the key a button uses to stay busy while the job runs (web/src/jobkey.js): the plan's area and arguments
export const busyKey = (pkg) => jobKey('apps', ['install', pkg]);

// the review rows: the container name only for a recipe; a secret never shows its value
export function rowsOf(plan, pages, values, secret, own, pkg) {
  const rows = reviewRows(pages, values, secret, own.trim(), pkg).filter((r) => r.stepId !== 'name' || hasName(plan));
  return rows;
}

// --- the run -------------------------------------------------------------------------------------------------------------------------------

const REAL = ['read', 'needs', 'ask', 'run', 'check', 'done', 'on', 'rebuild'];
// the steps a job without a plan at hand (opened from the Jobs page) shows
export const DEFAULT_JOBSTEPS = [
  { name: 'read', text: 'Fetch the release' }, { name: 'needs', text: 'Check what it needs' }, { name: 'ask', text: 'Check the answers' },
  { name: 'run', text: 'Set it up' }, { name: 'check', text: 'Check that it works' }, { name: 'done', text: 'Done' },
];

// the step text of a record -> { name, phase } for a step of the contract, else null (`waiting`, `error`, nothing)
export function stepName(rec) {
  const t = String(rec?.step?.text ?? '');
  if (t.startsWith('run:')) return { name: 'run', phase: t.slice(4) };
  return REAL.includes(t) ? { name: t, phase: '' } : null;
}

// What the dialog shows for a record: 'loading' | 'running' | 'question' | 'result' | 'failed'.
// A question this dialog has answered (answeredSeq) is not shown again while the record still carries it.
export function screenOf(rec, answeredSeq = 0) {
  if (!rec) return 'loading';
  if (rec.state === 'ok') return 'result';
  if (['failed', 'cancelled', 'interrupted'].includes(rec.state)) return 'failed';
  const q = pending(rec);
  if (q && q.seq !== answeredSeq) return 'question';
  return 'running';
}

// The stepper: the plan's job steps with done | current | failed | pending. `last` is the last step of the contract seen (a `waiting` or
// `error` step text names none: the dialog keeps what it saw before). A finished job (ok) has every step done.
// Returns [{ name, text, state, phase }] (phase only on the run entry while it runs: the recipe phase).
export function stepper(rec, jobsteps, last = '') {
  const list = jobsteps && jobsteps.length ? jobsteps : DEFAULT_JOBSTEPS;
  const cur = stepName(rec);
  const name = cur ? cur.name : last;
  let at = list.findIndex((s) => s.name === name);
  if (at < 0 && rec && rec.state === 'waiting') at = Math.max(0, list.findIndex((s) => s.name === 'ask'));   // a question before any step was seen
  const finished = rec?.state === 'ok';
  const bad = !!rec && ['failed', 'cancelled', 'interrupted'].includes(rec.state);
  return list.map((s, i) => {
    let state = 'pending';
    if (finished) state = 'done';
    else if (at >= 0 && i < at) state = 'done';
    else if (at >= 0 && i === at) state = bad ? 'failed' : 'current';
    return { name: s.name, text: s.text, state, phase: s.name === 'run' && cur && cur.name === 'run' && state === 'current' ? cur.phase : '' };
  });
}
// the name of the last step of the contract a record showed, to feed stepper(): `last` stays when the record shows none
export const lastOf = (rec, last = '') => stepName(rec)?.name ?? last;

// the package of a record: the result names it, else the slug (recipe-<name>[-run])
export const pkgOf = (rec, recipeOf) => (rec?.result?.package && rec.result.package !== '-' ? rec.result.package : recipeOf(rec));

// the address of the Open button: host:port only (letters, digits, dots, dashes), never `-`; anything else gives ''
export function openUrl(open) {
  const v = String(open ?? '');
  return /^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?:[0-9]{1,5}$/.test(v) && Number(v.split(':').pop()) <= 65535 ? `http://${v}` : '';
}

// the result rows of an ok record: [[label, value]] without the dashes
export function resultRows(rec) {
  const r = rec?.result ?? {};
  return [['Container', r.instance], ['Data', r.data], ['Backup', r.backup]].filter(([, v]) => v !== undefined && v !== null && v !== '' && v !== '-');
}

// the sentence for a record that did not end well (the strings of the old question dialog), '' for the others
export function failedText(rec) {
  switch (phase(rec)) {
    case 'timeout': return 'Nobody answered in time, so the run was cancelled. Run it again.';
    case 'cancelled': return 'The run was stopped.';
    case 'interrupted': return 'The run was interrupted (the server restarted). Run it again.';
    case 'rejected': return 'The answers were refused too often. Run it again.';
    case 'failed': return 'The run failed. The Jobs page and the log show why.';
    default: return '';
  }
}
// the message the job itself gave (rec.error.message), as plain text
export const errorMessage = (rec) => String(rec?.error?.message ?? '');
