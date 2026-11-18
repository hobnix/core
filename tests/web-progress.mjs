// Progress and StepList helpers (web/src/ui/progress.js): percent, step states, steps from a job record.
import { pct, stepState, stepsFromRecord } from '../web/src/ui/progress.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

console.log('-- pct');
check('half', pct(5, 10) === 50);
check('clamped above and below', pct(15, 10) === 100 && pct(-1, 10) === 0);
check('unknown total is null', pct(5, null) === null && pct(5, 0) === null && pct(null, 10) === null && pct(undefined, 10) === null);
check('NaN is null', pct(NaN, 10) === null && pct(1, NaN) === null);

console.log('-- stepState');
check('before, at, after', stepState(0, 1) === 'done' && stepState(1, 1) === 'current' && stepState(2, 1) === 'todo');
check('failed marks the current step only', stepState(1, 1, { failed: true }) === 'failed' && stepState(0, 1, { failed: true }) === 'done');
check('finished: all done', [0, 1, 2].every((i) => stepState(i, 0, { finished: true }) === 'done'));

console.log('-- stepsFromRecord');
const s = stepsFromRecord({ n: 2, of: 3, text: 'Install' }, 'running');
check('three steps, second current with its text', s.length === 3 && s[0].state === 'done' && s[1].state === 'current' && s[1].label === 'Install' && s[2].state === 'todo');
check('failed job keeps the failed step', stepsFromRecord({ n: 2, of: 3, text: 'x' }, 'failed')[1].state === 'failed');
check('ok job: all done', stepsFromRecord({ n: 3, of: 3, text: 'x' }, 'ok').every((x) => x.state === 'done'));
check('no total, no steps', stepsFromRecord({ n: 1, of: null, text: 'x' }).length === 0 && stepsFromRecord(null).length === 0);

console.log(`\n${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
