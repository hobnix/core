// web/src/shell/planstart.js: what the plan dialog asks to be typed and sends with Start. Plain node.
import assert from 'node:assert/strict';
import { staysForRebuild, typedNames, allTyped, startRequest } from '../web/src/shell/planstart.js';

const rebuild = [['note', 'This takes effect with hs rebuild.']];
for (const area of ['system', 'blueprint', 'pkg/bundle']) assert.equal(staysForRebuild(area, rebuild), false, area + ' rebuilds itself');
assert.equal(staysForRebuild('config', rebuild), true);
assert.equal(staysForRebuild('config', [['note', 'This takes effect at once; no rebuild is needed.']]), false);

const p = { confirm_name: 'docker', confirm_names: ['media', 'docker'], tag: 'v1.0.0' };
assert.deepEqual(typedNames('blueprint', p), ['media', 'docker']);
assert.deepEqual(typedNames('pool/x', p), ['docker']);
assert.equal(allTyped(['media', 'docker'], ['media']), false);
assert.equal(allTyped(['media', 'docker'], ['docker', 'media']), false);
assert.equal(allTyped(['media', 'docker'], ['media', 'docker']), true);
assert.equal(allTyped([], []), true);
assert.deepEqual(startRequest('blueprint', ['apply', 'media'], p, ['media', 'docker']),
  { args: ['apply', 'media', '--tag', 'v1.0.0', '--confirm', 'docker'], confirm: 'media' });
// only what was typed is sent
assert.deepEqual(startRequest('blueprint', ['apply', 'media'], { tag: 'v1.0.0' }, []), { args: ['apply', 'media', '--tag', 'v1.0.0'], confirm: '' });
assert.deepEqual(startRequest('config', ['set'], { confirm_name: 'x', tag: 'v1.0.0' }, ['x']), { args: ['set'], confirm: 'x' });
