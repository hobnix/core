// The poll timing of the live stream (web/src/polldelay.js): no timer while a topic read follows the stream, the plain interval otherwise.
import { nextDelay } from '../web/src/polldelay.js';
import { parseLiveRows, parseInspect } from '../web/src/livestatus.js';
import { poolTopic } from '../web/src/pages/storage/pool.js';

let ok = 0, bad = 0;
const check = (name, cond) => { if (cond) { ok++; console.log(`  ok    ${name}`); } else { bad++; console.log(`  FAIL  ${name}`); } };

check('topic and live open: no timer', nextDelay('status', true, 15000) === null);
check('topic, live closed: the interval', nextDelay('status', false, 15000) === 15000);
check('no topic, live open: the interval', nextDelay(undefined, true, 15000) === 15000);
check('503 with retry_after: that many seconds', nextDelay('status', true, 15000, { status: 503, retryAfter: 2 }) === 2000);
check('503 without retry_after: the interval', nextDelay('status', false, 15000, { status: 503 }) === 15000);
check('other error, live open: the interval', nextDelay('status', true, 15000, { status: 500 }) === 15000);
check('live topic and live open: no timer', nextDelay('live', true, 5000) === null);
check('live topic, live closed: the interval', nextDelay('live', false, 5000) === 5000);

// poll(): the explicit topic wins, else live.topics[path] (source check: poll needs Svelte runes, so the line is checked as text)
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../web/src/data.svelte.js', import.meta.url), 'utf8');
check('poll: explicit topic first, then live.topics[path]', /\(typeof topic === 'function' \? topic\(\) : topic\) \?\? live\.topics\[p\]/.test(src));

const now = 1000;
const rows = [
  ['status', '15', '7', '1', '0', '-', '-'],
  ['a', '5', '-1', '2', '0', '-', '-'],
  ['b', '5', '-1', '3', '1', 'boom', '995'],
  ['c', '5', '20', '4', '0', '-', '-'],
  ['d', '5', '10', '5', '2', 'boom', '995'],
  ['e', '5', '10', '6', '0', 'boom', '995'],
  ['f', '5', '10', '7', '0', 'boom', '980'],
];
const parsed = parseLiveRows(rows, now);
check('live rows: all seven fields parsed', parsed.length === 7 && parsed[0].topic === 'status' && parsed[0].every === 15 && parsed[0].age === 7 && parsed[0].gen === 1 && parsed[0].rc === 0 && parsed[0].err === null && parsed[0].tsErr === null);
check('live state pending vs never', parsed[1].state === 'pending' && parsed[2].state === 'never');
check('live state stale at boundary', parseLiveRows([['x', '5', '16', '1', '0', '-', '-']], now)[0].state === 'stale' && parseLiveRows([['x', '5', '15', '1', '0', '-', '-']], now)[0].state === 'fresh');
check('live state stale row', parsed[3].state === 'stale');
check('live state nonzero rc is failing', parsed[4].state === 'failing');
check('live state newer ts_err is failing', parsed[5].state === 'failing');
check('live state older ts_err is fresh', parsed[6].state === 'fresh');
const eight = parseLiveRows([['services-list', '30', '5', '2', '0', '-', '-', 'ct-list'], ['x', '5', '1', '1', '0', '-', '-', '-']], now);
check('live rows: eight fields parse needs', eight.length === 2 && eight[0].needs.length === 1 && eight[0].needs[0] === 'ct-list' && eight[1].needs.length === 0);
check('live rows: seven fields give no needs', parsed[0].needs.length === 0);
const ten = parseLiveRows([['x', '5', '1', '1', '0', '-', '-', '-', 'fresh', '4'], ['y', '5', '1', '1', '0', '-', '-', '-', 'fresh', '-']], now);
check('live rows: the tenth field is the heartbeat age, - is none', ten[0].beat === 4 && ten[1].beat === null && eight[0].beat === null);
check('live rows: malformed rows are dropped', parseLiveRows([['only', 'five', 'fields', 'here', 'x']], now).length === 0);
const ins = (o) => ({ topic: 't', words: ['a'], interval: 5, lock: 'run', origin: 'core', cap: null, cap_on: true, groups: [], age: 1, gen: 1, rc: 0, err: null, ts_err: null, bytes: 1, ...o });
const pi = (o, now = 1000) => parseInspect({ now, topics: [ins(o)] });
check('inspect: fresh', pi({}).rows[0].state === 'fresh');
check('inspect: never and pending', pi({ age: null, err: 'x' }).rows[0].state === 'never' && pi({ age: null }).rows[0].state === 'pending');
check('inspect: stale', pi({ age: 16 }).rows[0].state === 'stale');
check('inspect: failing by newer error', pi({ age: 10, err: 'x', ts_err: 995 }).rows[0].state === 'failing');
check('inspect: a good document with exit 1 is not failing', pi({ rc: 1 }).rows[0].state === 'fresh' && pi({ rc: 2, age: 10, err: 'old', ts_err: 980 }).rows[0].state === 'fresh');
check('inspect: capability off wins', pi({ cap_on: false, age: null }).rows[0].state === 'off');
check('inspect: doc status wins', pi({ status: 'error', cap_on: true }).rows[0].state === 'error');
check('inspect: has.needs only with the key', !pi({}).has.needs && pi({ needs: ['a', 'b'] }).has.needs && pi({ needs: ['a', 'b'] }).rows[0].needs.join(', ') === 'a, b');
check('inspect: has.status and has.ttl', pi({ status: 'ok', ttl: 45 }).has.status && pi({ ttl: 45 }).has.ttl && !pi({}).has.ttl && !pi({ ttl: null }).has.ttl);
check('inspect: a resting demand topic is idle, a watched or old one is stale', pi({ status: 'expired', idle: 300, demand: 'idle:300', age: 200 }).rows[0].state === 'idle'
  && pi({ status: 'expired', idle: 300, demand: 'idle:300', age: 200, lease: 1100 }).rows[0].state === 'expired'
  && pi({ status: 'expired', idle: 300, demand: 'idle:300', age: 2000 }).rows[0].state === 'expired' && pi({ demand: 'always' }).has.demand && !pi({}).has.demand);
check('inspect: garbage gives no rows', parseInspect(null).rows.length === 0 && parseInspect({ topics: 5 }).rows.length === 0 && parseInspect({ topics: [null, {}, { topic: 3 }] }).rows.length === 0);
check('inspect: unknown keys are kept', pi({ extra: 1 }).rows[0].extra === 1);
const TOPICS = { '/api/sys/pool/info?pool=bulk': 'pool-info-bulk', '/api/sys/pool/members?pool=fast': 'pool-members-fast', '/api/sys/pool/state?pool=bulk': 'pool-state-bulk', '/api/sys/pool/info?pool=fast': 'pool-info-fast' };
check('poolTopic kinds', poolTopic('info', 'bulk', TOPICS) === 'pool-info-bulk' && poolTopic('members', 'fast', TOPICS) === 'pool-members-fast' && poolTopic('state', 'bulk', TOPICS) === 'pool-state-bulk');
check('poolTopic: a pool without a topic, a bad kind, no map', poolTopic('info', 'other', TOPICS) === undefined && poolTopic('disks', 'bulk', TOPICS) === undefined && poolTopic('info', 'bulk') === undefined);
check('storage topic, live open: no timer', nextDelay('shares-overview', true, 30000) === null);
check('storage topic, live closed: the interval', nextDelay('shares-overview', false, 30000) === 30000);
check('fixed-pool topic, live open: no timer', nextDelay(poolTopic('info', 'bulk', TOPICS), true, 15000) === null);
check('fixed-pool topic, live closed: the interval', nextDelay(poolTopic('state', 'bulk', TOPICS), false, 10000) === 10000);
check('direct pool read (no topic), live open: the interval', nextDelay(poolTopic('info', 'archive', TOPICS), true, 15000) === 15000);
// Watchdog (web/src/livewatch.js): a stream silent for 45 s is reopened, any frame resets the clock, never faster than every 10 s.
import { LiveWatch } from '../web/src/livewatch.js';
{
  let t = 0, n = 0, said = -1;
  const w = new LiveWatch({ now: () => t, reconnect: (s) => { n++; said = s; } });
  t = 40000; check('watch: 40 s of silence: no reconnect', !w.check() && n === 0);
  w.frame(); t = 80000; check('watch: a beat at 40 s resets the clock', !w.check() && n === 0);
  t = 86000; check('watch: 46 s of silence: reconnect', w.check() && n === 1 && said === 46);
  t = 100000; check('watch: the clock restarts after a reconnect', !w.check() && n === 1);
  const g = new LiveWatch({ now: () => t, silentMs: 1000, minGapMs: 10000, reconnect: () => { n++; } });
  t = 200000; n = 0; g.check(); t = 203000; g.check(); check('watch: back-off, one reconnect in 3 s', n === 1);
  t = 211000; g.check(); check('watch: after the gap the next one is allowed', n === 2);
  const v = new LiveWatch({ now: () => t, reconnect: () => { n++; } });
  t = 400000; n = 0; check('watch: a tab shown again after a long silence reconnects at once', v.check() && n === 1);
}
const live = readFileSync(new URL('../web/src/live.svelte.js', import.meta.url), 'utf8');
check('live: beat, watchdog, visibilitychange wired', /'beat'/.test(live) && /new LiveWatch/.test(live) && /visibilitychange/.test(live) && /resyncAll\(\); \}/.test(live));
// Refetch on the list's topic (D5 a): a read with a free argument follows the topic of the list it belongs to, no timer while live.
const refetch = [
  ['pages/Users.svelte', 'users/access', 'shares-overview'], ['pages/Users.svelte', 'users/details', 'users-list'],
  ['forms/users/EditUser.svelte', 'users/details', 'users-list'],
  ['pages/Groups.svelte', 'users/group-access', 'shares-overview'], ['pages/Groups.svelte', 'users/group-details', 'users-groups'],
  ['pages/identity/GroupShares.svelte', 'users/group-access', 'shares-overview'], ['forms/users/EditGroup.svelte', 'users/group-details', 'users-groups'],
  ['pages/Instances.svelte', 'ct/bindings', 'ct-list'],
  ['pages/docker/AppEditPage.svelte', 'ct/storage', 'ct-list'], ['pages/docker/AppEditPage.svelte', 'shares/list', 'shares-overview'],
  ['pages/docker/AppWizardPage.svelte', 'ct/storage', 'ct-list'], ['pages/docker/AppWizardPage.svelte', 'shares/list', 'shares-overview'],
  ['pages/nodes/NodeKey.svelte', 'node/keyline', 'node-list'],
  ['pages/Shares.svelte', 'shares/acl', 'shares-overview'], ['pages/Shares.svelte', 'shares/visible', 'shares-overview'],
  ['pages/Shares.svelte', 'shares/history', 'shares-overview'], ['pages/protection/ShareSnapRow.svelte', 'shares/history', 'shares-overview'],
];
const topicNames = new Set(readFileSync(new URL('../scripts/lib/live-topics.tsv', import.meta.url), 'utf8').split(String.fromCharCode(10)).filter((l) => l && l[0] !== '#').map((l) => l.split(String.fromCharCode(9))[0]));
for (const [f, path, topic] of refetch) {
  const src = readFileSync(new URL('../web/src/' + f, import.meta.url), 'utf8');
  const line = src.split(String.fromCharCode(10)).find((l) => l.includes('poll(') && l.includes('/api/sys/' + path)) || '';
  check(`refetch: ${f} ${path} follows ${topic}`, line.includes(`, '${topic}');`) && topicNames.has(topic));
}
// D13: the topics a page reads are the set of the stream (web/src/topicset.js); data.svelte.js registers every poll topic in one place
import { TopicSet, streamQuery, newSid, createSubscriber } from '../web/src/topicset.js';
{
  const set = new TopicSet(['base']);
  check('topic set: the always-on topics are in it', set.key() === 'base');
  const offA = set.want('apps-list'), offB = set.want('apps-list'), offC = set.want('status');
  check('topic set: sorted and without duplicates', set.key() === 'apps-list,base,status');
  offA();
  check('topic set: two reads of one topic, one gone: still there', set.list().includes('apps-list'));
  offA();
  check('topic set: a release counts once', set.list().includes('apps-list'));
  offB();
  check('topic set: the last release removes it', !set.list().includes('apps-list'));
  const off = set.want('x'); off(); const again = set.want('x');
  check('topic set: release then want (a re-run) leaves it in', set.list().includes('x')); again(); offC();
  check('topic set: no topic is a no-op', set.want(undefined)() === undefined && set.key() === 'base');
  const all = set.want('*');
  check('topic set: * swallows the rest', set.key() === '*'); all();
  check('stream query', streamQuery(['a', 'b:c'], 'sid1') === 'topics=a,b%3Ac&sid=sid1');
  check('empty set: topics= is empty, not missing', streamQuery([], 's') === 'topics=&s'.replace('&s', '&sid=s'));
  check('sid is 16 chars of [a-z0-9]', /^[a-z0-9]{16}$/.test(newSid()));

  // a route change: the page's reads release, the next page's register; one POST with the new set, none when the set did not change
  const sent = []; const timers = [];
  const sub = createSubscriber({ set, send: async (l) => { sent.push(l.join(',')); return { gens: {} }; }, setTimer: (f) => { timers.push(f); return timers.length; }, clearTimer: () => {} });
  const flush = async () => { while (timers.length) await timers.shift()(); };
  const p1 = set.want('apps-list');
  sub.schedule(); await flush();
  check('subscriber: nothing is sent before the stream is open', sent.length === 0);
  sub.opened('base'); await flush();
  check('subscriber: the first set is sent after open', sent.join('|') === 'apps-list,base');
  p1(); const p2 = set.want('apps-list'); sub.schedule(); await flush();
  check('subscriber: release + want of the same topic sends nothing', sent.length === 1);
  p2(); const p3 = set.want('shares-overview'); sub.schedule(); await flush();
  check('subscriber: a route change sends the new set', sent.length === 2 && sent[1] === 'base,shares-overview');
  sub.schedule(); sub.schedule(); await flush();
  check('subscriber: bursts are one call', timers.length === 0 && sent.length === 2);
  sub.closed(); p3(); sub.schedule(); await flush();
  check('subscriber: a closed stream sends nothing', sent.length === 2);
  sub.opened('base', false); await flush();
  check('subscriber: a reopened stream after an error sends the set again', sent.length === 3 && sent[2] === 'base');
}
{
  const dsrc = readFileSync(new URL('../web/src/data.svelte.js', import.meta.url), 'utf8');
  check('poll: registers its topic and gives it back', /const release = wantTopic\(t\)/.test(dsrc) && /release\(\);\s*\};/.test(dsrc));
  const lsrc = readFileSync(new URL('../web/src/live.svelte.js', import.meta.url), 'utf8');
  check('live: one EventSource, with the topics and the stream id', (lsrc.match(/new EventSource/g) || []).length === 1 && /streamQuery\(list, sid\)/.test(lsrc));
  const pages = [['pages/Files.svelte', "wantTopic('fm-locations')"], ['pages/LiveState.svelte', 'wantAllTopics()']];
  for (const [f, needle] of pages) check(`${f} subscribes to what it reads directly`, readFileSync(new URL('../web/src/' + f, import.meta.url), 'utf8').includes(needle));
}
console.log(`  -> ${ok} ok, ${bad} failed`);
process.exit(bad ? 1 : 0);
