// Stepper helpers (web/src/ui/stepper.js): states from an index, normalising, which steps may be opened again.
import { stepsAt, normalize, canSelect } from '../web/src/ui/stepper.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

console.log('-- stepsAt');
const s = stepsAt(['a', 'b', 'c'], 1);
check('done, current, todo', s.map((x) => x.state).join() === 'done,current,todo');
check('labels kept', s.map((x) => x.label).join('') === 'abc');
check('index 0: nothing done', stepsAt(['a', 'b'], 0).map((x) => x.state).join() === 'current,todo');
check('index past the end: all done', stepsAt(['a', 'b'], 2).every((x) => x.state === 'done'));
check('no labels, no steps', stepsAt(undefined, 0).length === 0);

console.log('-- normalize');
const n = normalize(['x', { label: 'y', state: 'failed', note: 'why' }, { label: 'z', state: 'weird' }, {}]);
check('strings become steps', n[0].label === 'x' && n[0].state === 'todo');
check('numbers are 1-based', n.map((x) => x.n).join() === '1,2,3,4');
check('known state and note kept', n[1].state === 'failed' && n[1].note === 'why');
check('unknown state is todo, missing label is empty', n[2].state === 'todo' && n[3].label === '');
check('no list, no steps', normalize(null).length === 0);

console.log('-- canSelect');
check('only a done step with a handler', canSelect({ state: 'done' }, () => {}) && !canSelect({ state: 'done' }, null) && !canSelect({ state: 'current' }, () => {}) && !canSelect({ state: 'failed' }, () => {}));

console.log(`\n${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
