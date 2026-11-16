// The first-run wizard steps (web/src/setup/steps.js). Plain node.
import assert from 'node:assert/strict';
import { FIRST_RUN_STEPS, active, clampIndex } from '../web/src/setup/steps.js';
import { capRows, bundleArg } from '../web/src/setup/parts.js';

assert.deepEqual(FIRST_RUN_STEPS.map((s) => s.id), ['account', 'network', 'storage', 'preset', 'parts', 'done']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'preset', 'done']).map((s) => s.id), ['account', 'preset', 'done']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'network', 'preset', 'done']).map((s) => s.id), ['account', 'network', 'preset', 'done']);
assert.ok(FIRST_RUN_STEPS.every((s) => s.question && s.primary));
for (const s of FIRST_RUN_STEPS.filter((x) => x.slot)) assert.match(s.slot, /^#\d+$/);
assert.deepEqual(FIRST_RUN_STEPS.filter((s) => s.slot).map((s) => s.id), ['network']);
assert.deepEqual(active(FIRST_RUN_STEPS, ['account', 'storage', 'preset', 'parts', 'done']).map((s) => s.id), ['account', 'storage', 'preset', 'parts', 'done']);
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
