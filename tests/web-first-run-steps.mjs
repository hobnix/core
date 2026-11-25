// The first-run wizard steps (web/src/setup/steps.js). Plain node.
import assert from 'node:assert/strict';
import { FIRST_RUN_STEPS, active, clampIndex } from '../web/src/setup/steps.js';
import { capRows, bundleArg } from '../web/src/setup/parts.js';
import { blueprintRows, setupOptions, blueprintOf } from '../web/src/setup/blueprints.js';

assert.deepEqual(FIRST_RUN_STEPS.map((s) => s.id), ['account', 'network', 'storage', 'blueprint', 'done']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'blueprint', 'done']).map((s) => s.id), ['account', 'blueprint', 'done']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'network', 'blueprint', 'done']).map((s) => s.id), ['account', 'network', 'blueprint', 'done']);
assert.ok(FIRST_RUN_STEPS.every((s) => s.question && s.primary));
for (const s of FIRST_RUN_STEPS.filter((x) => x.slot)) assert.match(s.slot, /^#\d+$/);
assert.deepEqual(FIRST_RUN_STEPS.filter((s) => s.slot).map((s) => s.id), ['network']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'storage', 'blueprint', 'done']).map((s) => s.id), ['account', 'storage', 'blueprint', 'done']);
assert.equal(clampIndex(-1, 3), 0);
assert.equal(clampIndex(9, 3), 2);
assert.equal(clampIndex(1, 3), 1);

// the Optional parts step: rows of hs sys pkg capabilities
const caps = capRows([['a', 'caps', '1.0.0', '-', 'new', 'b,c', 'feature', 'A part'], ['b', 'caps', '1.0.0', '1.0.0', 'current', '-', '-', '-']]);
assert.deepEqual(caps[0].requires, ['b', 'c']);
assert.deepEqual(caps[1].requires, []);
assert.equal(caps[0].installed, false);
assert.equal(caps[1].installed, true);
assert.equal(caps[0].title, 'A part');
assert.equal(caps[1].title, 'b');
assert.equal(bundleArg(caps, { a: true, b: true }), 'a');
assert.equal(bundleArg(caps, { a: false }), '');
assert.equal(bundleArg([], {}), '');

// the "What is this server for?" step: rows of hs sys blueprint list
const bps = blueprintRows([['media', 'official', '1.0.0', 'homeserver', 'storage,docker', 'new', 'Media server'], ['core', 'mine', '2.0.0', '-', '-', 'waits', '-']]);
assert.deepEqual(bps[0].packages, ['storage', 'docker']);
assert.deepEqual(bps[1].roles, []);
assert.equal(bps[1].title, 'core');
const opts = setupOptions(bps);
assert.deepEqual(opts.map((o) => o.id), ['core', 'blueprint:media', 'blueprint:core', 'parts']);
assert.match(opts[1].text, /Sets up: storage, docker\./);
assert.equal(opts[2].disabled, true);
assert.equal(blueprintOf(bps, 'blueprint:media').name, 'media');
assert.equal(blueprintOf(bps, 'blueprint:core'), undefined);   // waits for a newer core
assert.equal(blueprintOf(bps, 'core'), undefined);             // "core only", not the blueprint called core
assert.deepEqual(setupOptions([]).map((o) => o.id), ['core', 'parts']);
