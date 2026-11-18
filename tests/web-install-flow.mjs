// The One Install dialog logic (web/src/forms/ops/installFlow.js, step 8b): a plan as the web server gives it (parse_change of apps-change.sh),
// the form, the arguments, and a sequence of job records from the first step to the result. The dialog only draws what these functions return.
import * as f from '../web/src/forms/ops/installFlow.js';
import * as q from '../web/src/forms/ops/recipeQuestions.js';
let bad = 0;
const check = (n, c, x = '') => { if (c) console.log(`  ok    ${n}`); else { bad++; console.log(`  FAIL  ${n} ${x}`); } };
const eq = (n, a, b) => check(n, JSON.stringify(a) === JSON.stringify(b), `${JSON.stringify(a)} != ${JSON.stringify(b)}`);

// --- the plan ---
const raw = {
  status: 'ok', reason: '', heading: 'Install vpn', package: 'vpn', kind: 'recipe', repo: 'recipes', version: '1.4.0', tag: 'v1.4.0', title: 'VPN gateway', description: 'A VPN.',
  creates: ['a container vpn', 'a share'],
  needl: [['docker', 'present', 'the recipe docker is installed', 'no'], ['tailscale', 'missing', 'switch the part on', 'yes']],
  asks: [['PROVIDER', 'Provider', 'text', '-', 'proton', '-', '-'], ['KIND', 'Kind', 'choice', 'wg,ovpn', 'wg', '-', '-'],
         ['KEY', 'Private key', 'secret', '-', '-', '-', 'KIND=wg'], ['ADDR', 'Address', 'text', '-', '-', '[0-9./]+', '-']],
  jobsteps: [['read', 'Fetch the release'], ['needs', 'Check what it needs'], ['ask', 'Check the answers'], ['run', 'Set it up'], ['check', 'Check it works'], ['done', 'Done']],
  steps: [['note', 'a note'], ['warn', 'careful'], ['danger', 'really careful']], confirm_name: '', long: true, exit: 0,
};
const plan = f.parsePlan(raw);
check('plan: ok, fields', plan.ok && plan.pkg === 'vpn' && plan.tag === 'v1.4.0' && plan.version === '1.4.0' && plan.repo === 'recipes' && plan.title === 'VPN gateway');
eq('plan: creates and needs', [plan.creates, plan.needs.map((n) => [n.name, n.state, n.long])], [['a container vpn', 'a share'], [['docker', 'present', false], ['tailscale', 'missing', true]]]);
check('plan: a long need makes the plan long', plan.long === true && f.parsePlan({ ...raw, long: false }).long === true && f.parsePlan({ ...raw, long: false, needl: [] }).long === false);
eq('plan: notes, warns, dangers', [plan.notes, plan.warns, plan.dangers], [['a note'], ['careful'], ['really careful']]);
eq('plan: asks map to the ask shape', plan.asks.map((a) => [a.key, a.kind, a.def, a.pattern, a.when]),
   [['PROVIDER', 'text', 'proton', '', ''], ['KIND', 'choice:wg,ovpn', 'wg', '', ''], ['KEY', 'secret', '', '', 'KIND=wg'], ['ADDR', 'text', '', '[0-9./]+', '']]);
eq('plan: job steps', plan.jobsteps.map((s) => s.name), ['read', 'needs', 'ask', 'run', 'check', 'done']);
const refused = f.parsePlan({ status: 'refused', reason: 'no release', exit: 1 });
check('plan: a refusal keeps its reason', !refused.ok && refused.reason === 'no release' && refused.asks.length === 0);
check('plan: nothing at all is not ok', f.parsePlan(null).ok === false);

// --- screens, form, arguments ---
check('screens: recipe with asks has a form', f.hasForm(plan) && f.hasName(plan));
eq('screens: list', f.screensOf(plan), ['plan', 'form', 'review', 'run']);
eq('screens: progress of the form and of the result', [f.progressOf(plan, 'form'), f.progressOf(plan, 'result')], [{ n: 2, of: 4 }, { n: 4, of: 4 }]);
const ext = f.parsePlan({ status: 'ok', package: 'games', kind: 'extension', asks: [], jobsteps: [['read', 'x']] });
check('screens: an extension without questions skips the form', !f.hasForm(ext) && !f.hasName(ext) && f.screensOf(ext).join() === 'plan,review,run');
check('screens: a typed name makes a form', f.hasForm(f.parsePlan({ status: 'ok', kind: 'extension', confirm_name: 'games' })));

const pages = f.pagesOf(plan);
check('pages: one page with every ask', pages.length === 1 && pages[0].asks.length === 4);
const values = { PROVIDER: 'proton', KIND: 'wg', ADDR: '' };
check('form: empty answers are fine (the job asks them)', f.formIssue(pages, values, '', '', plan, '') === '');
check('form: a bad pattern is an issue', f.formIssue(pages, { ...values, ADDR: 'abc' }, '', '', plan, '') === 'answer');
check('form: a bad choice is an issue', f.formIssue(pages, { ...values, KIND: 'x' }, '', '', plan, '') === 'answer');
check('form: control characters in a secret are an issue', f.formIssue(pages, values, 'a\nb', '', plan, '') === 'answer');
check('form: a bad container name is an issue', f.formIssue(pages, values, '', 'Bad Name', plan, '') === 'name' && f.formIssue(pages, values, '', 'vpn2', plan, '') === '');
const typed = f.parsePlan({ ...raw, confirm_name: 'vpn' });
check('form: the typed name must equal', f.formIssue(pages, values, '', '', typed, 'vp') === 'confirm' && f.formIssue(pages, values, '', '', typed, 'vpn') === '');
check('form: an inactive secret ask is not checked', f.formIssue(pages, { ...values, KIND: 'ovpn' }, 'a\nb', '', plan, '') === '');

eq('planArgs: --set only for answers', f.planArgs('vpn', '', pages, values, '', false), ['install', 'vpn', '--set', 'PROVIDER=proton', '--set', 'KIND=wg']);
eq('planArgs: repo and name', f.planArgs('vpn', 'mine', pages, { KIND: 'wg' }, ' vpn2 ', true), ['install', 'vpn', '--repo', 'mine', '--name', 'vpn2', '--set', 'KIND=wg']);
eq('startArgs: tag of the plan, --ask', f.startArgs(plan, 'vpn', '', pages, values, '', false, true),
   ['install', 'vpn', '--tag', 'v1.4.0', '--set', 'PROVIDER=proton', '--set', 'KIND=wg', '--ask']);
check('startArgs: the secret is never an argument', !f.startArgs(plan, 'vpn', '', pages, values, '', false, false).join(' ').includes('sekret'));
check('stdin: the one active secret goes on stdin', f.stdinOf(pages, values, 'sekret') === 'sekret' && f.stdinOf(pages, { ...values, KIND: 'ovpn' }, 'sekret') === undefined && f.stdinOf(pages, values, '') === undefined);
const rows = f.rowsOf(plan, pages, values, 'sekret', '', 'vpn');
check('review: the secret is flagged, never shown', rows.some((r) => r.secret && r.value === 'set') && !JSON.stringify(rows).includes('sekret'));
check('review: no container row for an extension', !f.rowsOf(ext, [], {}, '', '', 'games').some((r) => r.stepId === 'name') && rows.some((r) => r.stepId === 'name'));
check('busy key is the one of the Marketplace button', f.busyKey('vpn') === 'apps install vpn');

// --- the job, record by record ---
const rec = (state, text, extra = {}) => ({ id: '20261116-100000-apps-install-vpn-abcd', slug: 'recipe-vpn', state, step: { n: 1, of: 6, text }, ...extra });
const js = plan.jobsteps;
const states = (r, last) => f.stepper(r, js, last).map((s) => s.state[0]).join('');   // d done, c current, p pending, f failed
check('record: none yet is loading', f.screenOf(null) === 'loading');
let last = '';
let r = rec('queued', 'read'); last = f.lastOf(r, last);
check('read: running, first step current', f.screenOf(r) === 'running' && states(r, last) === 'cppppp');
r = rec('running', 'needs'); last = f.lastOf(r, last);
check('needs: read done, needs current', states(r, last) === 'dcpppp');
const question = { seq: 3, key: 'ADDR', label: 'Address', kind: 'text', default: '10.0.0.2', pattern: '[0-9.]+', choices: [], error: '', attempt: 1 };
r = rec('waiting', 'waiting', { waiting: question });
check('waiting: the question shows, the stepper keeps the last step', f.screenOf(r) === 'question' && f.lastOf(r, last) === 'needs' && states(r, f.lastOf(r, last)) === 'dcpppp');
const ans = q.answerRequest(r.id, q.pending(r), '10.0.0.9');
eq('answer: request', ans, { area: 'jobs', args: ['answer', r.id, '--seq', '3', '--key', 'ADDR'], stdin: '10.0.0.9' });
check('answer: answeredSeq is honoured', f.screenOf(r, 3) === 'running' && f.screenOf(r, 2) === 'question' && f.screenOf({ ...r, waiting: { ...question, seq: 4 } }, 3) === 'question');
eq('waiting before any step: ask is current', f.stepper(r, js, '').map((s) => s.state), ['done', 'done', 'current', 'pending', 'pending', 'pending']);
r = rec('running', 'run:fetch'); last = f.lastOf(r, last);
const sr = f.stepper(r, js, last);
check('run:fetch: run current with its phase', sr[3].state === 'current' && sr[3].phase === 'fetch' && sr[2].state === 'done' && sr[4].state === 'pending');
r = rec('running', 'check'); last = f.lastOf(r, last);
check('check: run done, phase gone', states(r, last) === 'ddddcp' && f.stepper(r, js, last)[3].phase === '');
r = rec('running', 'done'); last = f.lastOf(r, last);
check('done: still running until the state says ok', f.screenOf(r) === 'running' && states(r, last) === 'ddddcp'.slice(0, 4) + 'dc');
r = rec('ok', 'done', { result: { package: 'vpn', kind: 'recipe', version: '1.4.0', tag: 'v1.4.0', instance: 'vpn', open: '192.168.1.20:8096', data: '/srv/vpn', backup: '-' } });
check('ok: result screen, everything done', f.screenOf(r) === 'result' && states(r, last) === 'dddddd');
eq('ok: result rows skip the dashes', f.resultRows(r), [['Container', 'vpn'], ['Data', '/srv/vpn']]);
check('ok: open url', f.openUrl(r.result.open) === 'http://192.168.1.20:8096');
check('open url: dash and anything odd is none', f.openUrl('-') === '' && f.openUrl('') === '' && f.openUrl(undefined) === '' && f.openUrl('host') === ''
  && f.openUrl('javascript:alert(1)') === '' && f.openUrl('a b:80') === '' && f.openUrl('h/x:80') === '' && f.openUrl('host:99999') === '' && f.openUrl('h:80/x') === ''
  && f.openUrl('evil.com:80@x') === '' && f.openUrl('my-server.local:8096') === 'http://my-server.local:8096');
check('ok: package of a record', f.pkgOf(r, q.recipeOf) === 'vpn' && f.pkgOf(rec('running', 'read'), q.recipeOf) === 'vpn' && f.pkgOf({ ...r, result: { package: '-' } }, q.recipeOf) === 'vpn');

// failures
const bad1 = rec('failed', 'error', { error: { category: 'step_failed', message: 'check failed' } });
check('failed: screen, text, the failing step is the last one seen', f.screenOf(bad1) === 'failed' && f.failedText(bad1).startsWith('The run failed') && states(bad1, 'check') === 'ddddfp'
  && f.errorMessage(bad1) === 'check failed' && f.stepper(bad1, js, 'check').find((s) => s.state === 'failed').name === 'check');
const canc = rec('cancelled', 'error', { error: { category: 'cancelled' } });
const tout = rec('cancelled', 'error', { error: { category: 'input_timeout' } });
const intr = rec('interrupted', 'error');
const rej = rec('failed', 'error', { error: { category: 'input_rejected' } });
check('failed: cancelled / timeout / interrupted / rejected texts', f.failedText(canc) === 'The run was stopped.' && f.failedText(tout).startsWith('Nobody answered')
  && f.failedText(intr).includes('interrupted') && f.failedText(rej).includes('refused too often') && [canc, tout, intr, rej].every((x) => f.screenOf(x) === 'failed'));
check('failed text is empty for a good record', f.failedText(r) === '' && f.failedText(rec('running', 'read')) === '');
check('failed with no step ever seen marks nothing failed', !f.stepper(intr, js, '').some((s) => s.state === 'failed'));

// a job opened without the plan (from the Jobs page) uses the default steps
const dflt = f.stepper(rec('running', 'run:fetch'), [], '');
check('default steps when there is no plan', dflt.length === f.DEFAULT_JOBSTEPS.length && dflt.find((s) => s.name === 'run').state === 'current' && dflt[0].state === 'done');
// a step the plan does not list (rebuild of a recipe): the last listed step stays current
check('an unlisted step keeps the last listed one current', f.stepper(rec('running', 'rebuild'), js, 'check').filter((s) => s.state === 'current').length === 0
  || f.stepper(rec('running', 'rebuild'), js, 'check').find((s) => s.state === 'current')?.name === 'check');

// refusal path: the plan with answers is refused -> the dialog shows the reason and goes back to the form
const again = f.parsePlan({ status: 'refused', reason: 'ADDR is not an address', exit: 1 });
check('refusal of the plan with answers: reason, not ok', !again.ok && again.reason === 'ADDR is not an address');
check('a refused answer or start reply is not done', q.replyKind({ status: 'refused', reason: 'x' }) === 'refused' && q.replyKind({ status: 'done' }) === 'done');

if (bad) { console.log(`${bad} failed`); process.exit(1); }
