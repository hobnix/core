// The row button of the Apps page (web/src/pages/apps.js).
import { appAction } from '../web/src/pages/apps.js';
import { parseStates, stageActions } from '../web/src/pages/states.js';

let ok = 0, bad = 0;
const check = (name, cond, extra = '') => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name} ${extra}`); } };

const parked = appAction({ state: 'parked', vstate: 'unknown', applied: '-', avail: '-' });
check('parked: Install, tip parked, not primary', parked.label === 'Install' && parked.tip === 'This recipe is parked' && !parked.primary);
const fresh = appAction({ state: 'not installed', vstate: 'unknown', applied: '-', avail: '1.0.0' });
check('not installed: Install, primary', fresh.label === 'Install' && fresh.primary && fresh.tip === 'Set this app up');
const partly = appAction({ state: 'partly', vstate: 'current', applied: '1.0.0', avail: '1.0.0' });
check('partly: Install', partly.label === 'Install' && partly.primary);
const cur = appAction({ state: 'installed', vstate: 'current', applied: '1.2.0', avail: '1.2.0' });
check('installed and current: Repair', cur.label === 'Repair' && cur.icon === 'wrench' && !cur.primary);
check('current tip says Up to date and the version', cur.tip.includes('Up to date') && cur.tip.includes('1.2.0'));
const upd = appAction({ state: 'installed', vstate: 'update', applied: '1.0.0', avail: '1.2.0' });
check('installed and update: Update', upd.label === 'Update' && upd.icon === 'arrows-clockwise' && !upd.primary);
check('update tip names both versions', upd.tip.includes('1.0.0') && upd.tip.includes('1.2.0'));
const unk = appAction({ state: 'installed', vstate: 'unknown', applied: '-', avail: '1.2.0' });
check('installed and unknown: Update with the old tip', unk.label === 'Update' && unk.tip === 'Run again: repairs or updates the setup');
check('never a disabled field', [parked, fresh, partly, cur, upd, unk].every((x) => !('disabled' in x)));

// the lifecycle words (ADR 0027)
const st = parseStates([
  ['a', 'recipe', 'running', 'update', 'r', '1', '1', 'a,a2', 't'], ['b', 'recipe', 'available', '-', 'r', '1', '-', '-', 't'],
  ['c', 'extension', 'installed', '-', 'r', '1', '1', '-', 't'], ['d', 'capability', 'on', 'pending', 'r', '1', '1', '-', 't'],
]);
check('states: flags and instances are split', st.get('a').flags[0] === 'update' && st.get('a').instances.length === 2 && st.get('b').flags.length === 0);
check('available: Install only', stageActions(st.get('b')).install === true && stageActions(st.get('b')).remove === false);
check('update flag: Update and Remove, Start/Stop for the instances', stageActions(st.get('a')).update && stageActions(st.get('a')).remove && stageActions(st.get('a')).instances.length === 2);
check('extension installed: Turn on', stageActions(st.get('c')).turn === 'enable');
check('capability on: Turn off, no instances', stageActions(st.get('d')).turn === 'disable' && stageActions(st.get('d')).instances.length === 0);
check('an unknown package has no actions', Object.keys(stageActions(undefined)).length === 0);

console.log(`${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
