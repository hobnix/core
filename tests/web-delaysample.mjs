// The browser half of the delay measure (web/src/delaysample.js, #486).
import { createSampler } from '../web/src/delaysample.js';
import { createBatcher } from '../web/src/samplebatch.js';
import { parseLiveRows, parseInspect } from '../web/src/livestatus.js';

let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

let t = 0;
const sent = [];
const s = createSampler((topic, ms) => sent.push([topic, ms]), { now: () => t, gap: 2000, expire: 60000 });
s.changed('apps', 1);                           // first sight: no change
s.changed('apps', 2); t = 100;
s.shown([{ topic: 'apps', gen: 1 }]);           // the page still shows the old gen
check('the old gen sends nothing', sent.length === 0);
t = 340; s.shown([{ topic: 'apps', gen: 2 }]);
check('the new gen sends the time since the event', sent.length === 1 && sent[0][0] === 'apps' && sent[0][1] === 340);
t = 400; s.shown([{ topic: 'apps', gen: 2 }]);
check('one change, one sample', sent.length === 1);
s.changed('apps', 3); t = 500; s.shown([{ topic: 'apps', gen: 3 }]);
check('a second change inside the gap is not sent', sent.length === 1);
t = 5000; s.changed('apps', 4); t = 5100; s.shown([{ topic: 'apps', gen: 4 }]);
check('after the gap it is sent again', sent.length === 2 && sent[1][1] === 100);
s.changed('pools', 1); s.changed('pools', 2); t = 100000; s.shown([{ topic: 'pools', gen: 2 }]);
check('a change never shown within the expiry is dropped', sent.length === 2);
s.changed('x', 'oops'); s.shown([{ topic: 'x', gen: 1 }]);
check('a broken gen is ignored', sent.length === 2);

const rows = parseLiveRows([['a', '5', '1', '1', '0', '-', '-', '-', 'fresh', '2', '40', '900', '-', '-'], ['b', '5', '1', '1', '0', '-', '-', '-', 'fresh', '2']], 0);
check('status rows: the delay columns, - is none', rows[0].delayLast === 40 && rows[0].delayWorst === 900 && rows[0].webLast === null && rows[1].delayLast === null);
const ins = parseInspect({ now: 10, topics: [{ topic: 'a', interval: 5, age: 1, gen: 1, delay_ms_last: 40 }, { topic: 'b', interval: 5, age: 1, gen: 1 }] });
check('inspect: has.delay only with a sample', ins.has.delay === true && parseInspect({ topics: [{ topic: 'b', interval: 5 }] }).has.delay === false);

// batches: one POST for many samples, at most `max` each, flushed by the timer or by flush()
{
  const posts = []; let fire = null;
  const b = createBatcher((x) => posts.push(x), { wait: 10000, max: 3, setTimer: (f) => { fire = f; return 1; }, clearTimer: () => { fire = null; } });
  b.add('a', 1); b.add('b', 2);
  check('batch: nothing is sent before the wait', posts.length === 0 && fire !== null);
  fire();
  check('batch: the timer sends both in one post', posts.length === 1 && posts[0].length === 2 && posts[0][1].topic === 'b');
  b.add('a', 1); b.add('a', 2); b.add('a', 3); b.add('a', 4);
  check('batch: a full batch goes at once, the rest waits', posts.length === 2 && posts[1].length === 3);
  b.flush();
  check('batch: flush sends the rest', posts.length === 3 && posts[2].length === 1);
}

console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
