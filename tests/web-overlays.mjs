// Keyboard logic of the overlays: the focus trap's Tab wrap (ui/focus.js) and the arrow keys of a menu (ui/menu-nav.js).
import assert from 'node:assert/strict';
import { nextFocus } from '../web/src/ui/focus.js';
import { menuNext } from '../web/src/ui/menu-nav.js';

const [a, b, c] = [{}, {}, {}];
const items = [a, b, c];
assert.equal(nextFocus(items, c, false), a, 'Tab on the last wraps to the first');
assert.equal(nextFocus(items, a, true), c, 'Shift+Tab on the first wraps to the last');
assert.equal(nextFocus(items, b, false), null, 'inside the list the browser moves on');
assert.equal(nextFocus(items, {}, false), a, 'focus outside the dialog comes back to the first');
assert.equal(nextFocus(items, {}, true), c, 'focus outside, Shift+Tab: the last');
assert.equal(nextFocus([], a, false), null, 'nothing focusable: nothing to do');

const m = [{}, { disabled: true }, {}, {}];
assert.equal(menuNext(m, 0, 'ArrowDown'), 2, 'skips a disabled item');
assert.equal(menuNext(m, 3, 'ArrowDown'), 0, 'wraps down');
assert.equal(menuNext(m, 0, 'ArrowUp'), 3, 'wraps up');
assert.equal(menuNext(m, 2, 'ArrowUp'), 0, 'skips a disabled item upwards');
assert.equal(menuNext(m, 2, 'Home'), 0);
assert.equal(menuNext([{ disabled: true }, {}, { disabled: true }], 1, 'End'), 1);
assert.equal(menuNext([{ disabled: true }], -1, 'ArrowDown'), -1, 'all disabled');
assert.equal(menuNext(m, -1, 'ArrowDown'), 0, 'from nothing focused: the first');
console.log('ok');
