// The pure logic of the `log` and `progress` blocks (web/src/shell/generic.js, #473). Run with node.
import { tailLines, apiPath, logClass, progressTone, progressOf } from '../web/src/shell/generic.js';

let ok = 0, bad = 0;
const eq = (name, got, want) => { if (JSON.stringify(got) === JSON.stringify(want)) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };

console.log('-- tailLines');
const many = Array.from({ length: 5000 }, (_, i) => `l${i}`);
eq('keeps the newest lines', tailLines(['a', 'b', 'c'], 2), ['b', 'c']);
eq('short logs are whole', tailLines(['a'], 5), ['a']);
eq('default is 200', tailLines(many).length, 200);
eq('never above 2000', tailLines(many, 99999).length, 2000);
eq('never below 1', tailLines(['a', 'b'], -5), ['b']);
eq('garbage gives the default', tailLines(many, 'x').length, 200);

console.log('-- apiPath');
eq('an api path passes', apiPath('/api/logs/stream/ct?target=web'), '/api/logs/stream/ct?target=web');
eq('another site is refused', apiPath('https://evil.example/api/x'), '');
eq('a path outside the api is refused', apiPath('/etc/passwd'), '');
eq('a parent step is refused', apiPath('/api/../x'), '');
eq('not a string', apiPath(null), '');

console.log('-- logClass');
eq('error', logClass('disk error on sda'), 'bad');
eq('warning', logClass('Warning: low space'), 'warn');
eq('plain', logClass('started'), '');

console.log('-- progressTone');
eq('ok', progressTone('ok'), 'ok');
eq('failed', progressTone('failed'), 'bad');
eq('waiting', progressTone('waiting'), 'warn');
eq('unknown is running', progressTone('whatever'), 'info');
eq('nothing is running', progressTone(undefined), 'info');

console.log('-- progressOf');
const blk = { read: '/r', value: 0, max: 1, labelCol: 2, state: 3 };
eq('from a row', progressOf(blk, ['420', '1000', 'Copying', 'running'], null), { value: 420, total: 1000, label: 'Copying', state: 'running', tone: 'info' });
eq('a dash is not a number', progressOf(blk, ['-', '-', '-', 'failed'], null), { value: null, total: null, label: '', state: 'failed', tone: 'bad' });
eq('the block label is the fallback', progressOf({ ...blk, label: 'Sync' }, ['1', '2', '-', 'ok'], null).label, 'Sync');
eq('no row, nothing', progressOf(blk, null, null), null);
const rec = { description: 'Backup', state: 'running', progress: { done: 3, total: 4 } };
eq('from a job', progressOf({ job: 'backup' }, null, rec), { value: 3, total: 4, label: 'Backup', state: 'running', tone: 'info' });
eq('a job without progress is a moving bar', progressOf({ job: 'b' }, null, { description: 'B', state: 'queued', progress: null }).total, null);
eq('no such job, nothing', progressOf({ job: 'b' }, null, null), null);

console.log(`${ok} passed, ${bad} failed`);
process.exit(bad ? 1 : 0);
