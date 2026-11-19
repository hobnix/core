// The sleep state on the Disks page (web/src/disk-sleep.js): field 13 of `sys monitor disks` and the lines of `sys disk power`. Plain node.
import assert from 'node:assert/strict';
import { sleepOf, sleepText, sleepDot, parsePower, powerText } from '../web/src/disk-sleep.js';

// a fixture of `sys monitor disks`: 14 fields, field 13 = power
const tsv = [
  'sda\t8001000000\tHDD\tbulk data-01\t31\tOK\t1200\t0\t0\t0\tWD Red WD-1\t500\tasleep\txfs',
  'sdb\t8001000000\tHDD\tbulk data-02\t35\tOK\t1300\t0\t0\t0\tWD Red WD-2\t500\tspinning\txfs',
  'nvme0n1\t500000000000\tSSD\tsystem\t40\tOK\t90\t0\t0\t0\tSamsung S-3\t-\t-\text4',
].map((l) => l.split('\t'));
assert.equal(tsv[0].length, 14);
assert.deepEqual(tsv.map(sleepOf), ['asleep', 'spinning', '']);
assert.equal(sleepText('asleep'), 'Asleep');
assert.equal(sleepText('spinning'), 'Spinning');
assert.equal(sleepText(''), '');
assert.equal(sleepDot('asleep'), 'ok');
assert.equal(sleepOf(['x']), '');
assert.equal(sleepOf(undefined), '');

const p = parsePower([
  ['disk', 'sda', 'asleep', '1700000000', '2'],
  ['disk', 'sdb', 'spinning', '1700000100', '0'],
  ['power', 'ups', 'whole server (UPS output)', '41'],
  ['power', 'rapl', 'CPU package (package-0)', '6.4'],
  ['power', 'ups', 'x', '-'],
]);
assert.deepEqual(p.disks.sda, { state: 'asleep', since: 1700000000, wakes: 2 });
assert.equal(p.power.length, 2);
assert.equal(powerText(p.power[0]), '41 W, whole server (UPS output), measured by UPS');
assert.match(powerText(p.power[1]), /measured by CPU package \(RAPL\)/);
assert.deepEqual(parsePower(null), { disks: {}, power: [] });
console.log('ok');
