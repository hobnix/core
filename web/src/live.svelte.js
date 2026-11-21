// The live stream of the server (/api/events): `changed` says a topic has a new generation, so a poll with that topic reads again at once.
// While the stream is closed or the server says `down` (its state service is lost), live.open is false and the polls use their timers.
// `domain` is a row of the event log (id = log id; EventSource sends Last-Event-ID on a reconnect, the server replays the rows after it).
// `resync` says rows or changes may be lost (gap too big, queue full): every followed topic is read again.
// `open` = the stream is up. `follow` = the polls may rely on it for the live-state topics (the live-state topics change only while the collector runs; the polls keep their timers while the stream is down).
// The domain events (`events`) are served always (ADR 0005), so a page that reads them (the job records) uses `open` alone.
// EventSource reconnects by itself. `beat` (the server sends it when the stream is idle) feeds a watchdog (livewatch.js): a stream that went silent is reopened.
import { LiveWatch } from './livewatch.js';
import { TopicSet, streamQuery, newSid, createSubscriber } from './topicset.js';
import { subscribeTopics } from './api.js';

export const live = $state({ open: false, follow: false, gen: {}, topics: {}, events: [], lastId: 0, resyncs: 0 });
// Topics that only the browser knows: the domain events of the stream are their signal (served in every mode), so a poll with one of these
// has no timer while the stream is open, always (ADR 0026: no live-state mode). The page merges the rows `live.events` brings itself.
export const STREAM_TOPICS = new Set(['event-log']);
const KEEP = 100;   // domain events kept in live.events

// URL -> topic map from the session answer (features.topics): a poll without its own topic argument follows the stream through it.
export function setTopics(map) { live.topics = map && typeof map === 'object' ? map : {}; }

// D13: the stream carries only the topics the open page reads (`topics`), one stream per tab; a route change sends the new set (POST, short).
// `wantTopic(topic)` is the one place a read registers; it returns the release function. Domain events are never filtered.
export const topicSet = new TopicSet();
export const wantTopic = (topic) => { const off = topicSet.want(topic); subscriber.schedule(); return () => { off(); subscriber.schedule(); }; };
// a read that follows every topic (the Live state page)
export const wantAllTopics = () => wantTopic('*');
// a change that came between a read and the subscribe call: the server says the gen of each added topic; a gen the page already saw differently re-reads
const catchUp = (gens) => { for (const [t, g] of Object.entries(gens)) if (t in live.gen && live.gen[t] !== g) live.gen[t] = g; };
const subscriber = createSubscriber({ set: topicSet, send: (list) => subscribeTopics(sid, list), onGens: catchUp });

let es = null, watch = null, timer = null, needResync = false, sid = '', urlKey = '', broken = false;

// Reads every followed topic again: the polls read live.resyncs next to live.gen[topic], so a new value runs each of them once.
export function resyncAll() { live.resyncs += 1; }

function connect() {
  if (!sid) sid = newSid();
  const list = topicSet.list();
  urlKey = list.join(',');
  es = new EventSource('/api/events?' + streamQuery(list, sid));
  // EventSource reconnects with the URL it was made with, so after an error the server may hold an old set: send the current one again
  const opened = () => { subscriber.opened(urlKey, !broken); broken = false; };
  const seen = (name, fn) => es.addEventListener(name, (ev) => { watch?.frame(); fn(ev); });
  seen('open', () => { opened(); live.open = true; if (needResync) { needResync = false; resyncAll(); } });
  seen('up', () => { live.open = true; });
  seen('down', () => { live.open = false; });
  es.addEventListener('error', () => { live.open = false; broken = true; subscriber.closed(); });
  seen('beat', () => {});
  seen('changed', (ev) => {
    try {
      const m = JSON.parse(ev.data);
      if (m && m.topic) live.gen[m.topic] = m.gen;
    } catch { /* a broken frame is ignored */ }
  });
  seen('domain', (ev) => {
    try {
      const m = JSON.parse(ev.data);
      if (!m || !m.id || m.id <= live.lastId) return;
      live.lastId = m.id;
      live.events = [...live.events, m].slice(-KEEP);
    } catch { /* a broken frame is ignored */ }
  });
  seen('resync', () => { resyncAll(); });
}

function onVisible() { if (!document.hidden) watch?.check(); }

export function startLive() {
  if (es || typeof EventSource === 'undefined') return;
  watch = new LiveWatch({
    now: () => Date.now(),
    reconnect: (secs) => {
      console.warn(`live stream silent for ${secs} s: reconnecting`);
      if (es) es.close();
      live.open = false;
      needResync = true;
      subscriber.closed();
      connect();
    },
  });
  connect();
  timer = setInterval(() => watch?.check(), 15000);
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisible);
}

export function stopLive() {
  if (es) es.close();
  es = null;
  subscriber.closed();
  sid = '';
  broken = false;
  if (timer) clearInterval(timer);
  timer = null;
  watch = null;
  needResync = false;
  if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisible);
  live.open = false;
  live.gen = {};
  live.events = [];
  live.lastId = 0;
}
