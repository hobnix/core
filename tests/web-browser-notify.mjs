// Browser notifications (web/src/shell/notify.js), run with node: support and reasons, the text, and what the Watcher raises.
import { notifySupport, safeText, Watcher, notificationFor } from '../web/src/shell/notify.js';
let bad = 0;
const eq = (n, g, w) => { if (JSON.stringify(g) === JSON.stringify(w)) console.log(`  ok    ${n}`); else { bad++; console.log(`  FAIL  ${n}: got ${JSON.stringify(g)}, want ${JSON.stringify(w)}`); } };

// support: a fake window with a fake Notification
const N = (permission) => Object.assign(function Notification() {}, { permission });
eq('granted and secure is ok', notifySupport({ isSecureContext: true, Notification: N('granted') }).ok, true);
eq('default is ok (the prompt comes later, from the click)', notifySupport({ isSecureContext: true, Notification: N('default') }).ok, true);
const d = notifySupport({ isSecureContext: true, Notification: N('denied') });
eq('denied is not ok and says why', [d.ok, /blocked/.test(d.reason)], [false, true]);
const ins = notifySupport({ isSecureContext: false });
eq('plain HTTP is not ok and says HTTPS', [ins.ok, /HTTPS/.test(ins.reason)], [false, true]);
eq('no Notification object', [notifySupport({ isSecureContext: true }).ok, /no notification support/.test(notifySupport({ isSecureContext: true }).reason)], [false, true]);

// text
eq('the part after Details is dropped', safeText('SMART of sdb is failing. Details: serial X1'), 'SMART of sdb is failing.');
eq('an identifier with digits is hidden', safeText('Disk WD-WX12ABC3456 is failing'), 'Disk ... is failing');
eq('short words with digits stay', safeText('Disk sda2 is failing'), 'Disk sda2 is failing');
eq('long text is cut', safeText('a'.repeat(300)).length, 100);
eq('title and tag', notificationFor({ kind: 'notification', level: 'error', text: 'Job failed', tag: 'n:5' }), ['Hobnix: error', { body: 'Job failed', tag: 'n:5' }]);

// Watcher
const p = (id, acked = false) => ({ kind: 'problem', id, text: id, acked });
const n = (id, level = 'warn') => ({ kind: 'notification', id, level, text: `e${id}` });
const run = (focused = () => false) => { const got = []; const w = new Watcher({ raise: (i) => got.push(i.tag), focused }); return { w, got }; };

let { w, got } = run();
eq('not ready: nothing, no baseline', w.update([p('a')], [], false), []);
w.update([p('a')], [n(1)]);
eq('the first read is the baseline: nothing raised', got, []);
w.update([p('a'), p('b')], [n(1), n(2)]);
eq('a new problem and a new event are raised', got, ['p:b', 'n:2']);
w.update([p('a'), p('b')], [n(1), n(2)]);
eq('the same again is a duplicate: not raised', got, ['p:b', 'n:2']);
w.update([p('a'), p('b'), p('c', true)], [n(1), n(2)]);
eq('a new but acknowledged problem is not raised', got, ['p:b', 'n:2']);
w.update([p('a')], [n(1), n(2)]);
w.update([p('a'), p('b')], [n(1), n(2)]);
eq('a problem that went and came back is news again', got, ['p:b', 'n:2', 'p:b']);

({ w, got } = run(() => true));
w.update([], []);
w.update([p('a')], [n(1)]);
eq('while the page is focused nothing is raised', got, []);
let f = true; ({ w, got } = run(() => f));
w.update([], []); w.update([p('a')], []); f = false; w.update([p('a')], []);
eq('what arrived while focused is not raised later', got, []);
w.update([p('a'), p('z')], []);
eq('after the focus is gone a new one is raised', got, ['p:z']);
console.log(bad ? `${bad} failed` : 'all ok');
process.exit(bad ? 1 : 0);
