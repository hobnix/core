// The action slot (web/src/shell/slots.js): one main action plus More, the header actions of a page, the role an action needs.
import { actionsOf, planOf, needOf, withActions } from '../web/src/shell/slots.js';
let bad = 0;
const check = (n, c, x = '') => { if (c) console.log(`  ok    ${n}`); else { bad++; console.log(`  FAIL  ${n} ${x}`); } };
const eq = (n, a, b) => check(n, JSON.stringify(a) === JSON.stringify(b), `${JSON.stringify(a)} != ${JSON.stringify(b)}`);

const slots = [{ name: 'combinarr', title: 'Combinarr', actions: [
  { id: 'sync', label: 'Start sync', plan: ['ext/combinarr', 'sync'], role: 'app-manager', main: true },
  { id: 'prune', label: 'Prune', plan: ['ext/combinarr', 'prune', '--all'], danger: true },
] }, { name: 'other', title: 'Other', actions: [{ id: 'a', label: 'A', plan: ['ext/other', 'a'] }, { id: 'b', label: 'B', plan: ['ext/other', 'b'] }] }];

eq('the main action is the one marked main', actionsOf(slots, 'combinarr').main.id, 'sync');
eq('the others go under More', actionsOf(slots, 'combinarr').more.map((a) => a.id), ['prune']);
eq('without main the first action is the main one', actionsOf(slots, 'other').main.id, 'a');
eq('a package without slots has no action', actionsOf(slots, 'none'), { main: null, more: [] });
eq('no slot list at all is fine', actionsOf(undefined, 'x'), { main: null, more: [] });
eq('the plan dialog gets the area and the arguments', planOf(slots[0].actions[1]), ['ext/combinarr', ['prune', '--all'], 'Prune']);
eq('an action without a role needs admin', needOf(slots[0].actions[1]), 'admin');
eq('an action role below its area does not lower it', needOf({ plan: ['ext/x'], role: 'viewer' }), 'admin');
eq('the page header gets the actions after its own', withActions({ name: 'combinarr', actions: [{ label: 'Own' }] }, slots).actions.map((a) => a.label), ['Own', 'Start sync', 'Prune']);
eq('a page of a package without slots stays as it is', withActions({ name: 'none' }, slots), { name: 'none' });
process.exit(bad ? 1 : 0);
