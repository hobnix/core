// The Storage step of the first-run wizard (web/src/setup/storage.js). Plain node.
import assert from 'node:assert/strict';
import { groups, poolNameOk, suggestName, nothingText, evenPair } from '../web/src/setup/storage.js';

const rows = [
  ['sys', '1', 'nvme', 'M', 'os', '-', 'system'],
  ['e1', '100', 'sata', 'A', 'empty', '-', 'free'],
  ['e2', '100', 'sata', 'B', 'empty', '-', 'free'],
  ['z1', '100', 'sata', 'C', 'zfs', 'tank', 'importable'],
  ['z2', '100', 'sata', 'D', 'zfs', 'tank', 'importable'],
  ['d1', '100', 'sata', 'E', 'zfs', 'old', 'importable'],
  ['d2', '100', 'sata', 'F', 'zfs', 'old', 'damaged'],
  ['i1', '100', 'sata', 'G', 'zfs', 'live', 'imported'],
  ['s1', '100', 'sata', 'H', 'snapraid', 'bulk-data-01', 'mounted'],
  ['b1', '100', 'usb', 'I', 'backup', 'backup', 'protected'],
  ['l1', '100', 'sata', 'J', 'luks', '-', 'locked'],
  ['f1', '100', 'sata', 'K', 'foreign', 'ntfs', 'has-data'],
];
const g = groups(rows);
assert.deepEqual(g.importable, [{ pool: 'tank', disks: ['z1', 'z2'] }]);
assert.deepEqual(g.empty.map((d) => d.id), ['e1', 'e2']);
assert.deepEqual(g.shown.map((d) => d.id), ['d1', 'd2', 'i1', 's1', 'b1', 'l1', 'f1']);
assert.ok(!g.shown.some((d) => d.kind === 'os'));
assert.ok(!g.importable.some((p) => p.pool === 'old'));

assert.ok(poolNameOk('data'));
assert.ok(poolNameOk('a1'));
assert.ok(poolNameOk('abcdefghijkl'));
for (const bad of ['Data', 'incus', '', '1a', 'abcdefghijklm', 'a-b', 'mirror']) assert.ok(!poolNameOk(bad), bad);

assert.equal(suggestName([]), 'data');
assert.equal(suggestName(['data']), 'data2');
assert.equal(suggestName(['data', 'data2']), 'data3');

assert.ok(evenPair(2) && evenPair(4));
assert.ok(!evenPair(0) && !evenPair(1) && !evenPair(3));

const none = groups([['sys', '1', 'nvme', 'M', 'os', '-', 'system']]);
assert.equal(nothingText(none, []), 'No storage pool yet; shares need one.');
assert.equal(nothingText(none, [{ name: 'x' }]), '');
assert.equal(nothingText(g, []), '');
