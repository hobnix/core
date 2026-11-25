// web/src/shell/pkgbind.js: what Start of the plan dialog sends for a package update. Plain node.
import assert from 'node:assert/strict';
import { boundArgs } from '../web/src/shell/pkgbind.js';
import { startRequest, typedNames } from '../web/src/shell/planstart.js';

const seen = 'a'.repeat(32);
const plan = { tag: 'v1.2.0', seen, confirm_name: 'demo' };
const args = ['update', 'demo'];
assert.deepEqual(boundArgs('pkg', args, plan), ['update', 'demo', '--tag', 'v1.2.0', '--seen', seen]);
assert.deepEqual(args, ['update', 'demo'], 'the plan args (the job key) stay as they are');
// nothing to bind: the server then refuses an update with new permissions
assert.deepEqual(boundArgs('pkg', args, { tag: 'v1.2.0' }), args);
// no other change gets the words
for (const [area, a] of [['pkg', ['remove', 'demo']], ['pkg', ['install', 'demo']], ['apps', ['update', 'demo']], ['parts', ['update', 'demo']]]) {
  assert.deepEqual(boundArgs(area, a, plan), a);
}
// the dialog never sends an acceptance of its own
assert.ok(!boundArgs('pkg', args, plan).includes('--accept-permissions'));
// what the dialog sends: the bound args and the TYPED name, never the plan's own word
assert.deepEqual(typedNames('pkg', plan), ['demo']);
assert.deepEqual(startRequest('pkg', args, plan, ['demo']), { args: ['update', 'demo', '--tag', 'v1.2.0', '--seen', seen], confirm: 'demo' });
assert.equal(startRequest('pkg', args, plan, []).confirm, '');
assert.equal(startRequest('pkg', args, { tag: 'v1.2.0', seen }, ['demo']).confirm, '');
