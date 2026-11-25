// The only place that talks to the backend. A change always sends the CSRF token of the session.
let csrf = '';

// How old each read was when it arrived (X-HS-Age: the server may show an answer it kept for a while; none = just read), by path.
const ages = new Map();
export const ageOf = (path) => {
  const a = ages.get(path);
  return a ? a.age + (Date.now() - a.at) / 1000 : null;
};

// The status of each read as the server reported it (X-HS-Status: fresh|stale|error|expired; absent = a read that has no live topic), with the topic, the
// error line and the time of the last good read in ms (null = unknown). Read by shell/Fresh.svelte; a page keeps its last data whatever the status is.
const states = new Map();
export const stateOf = (path) => states.get(path) ?? null;

// How long the browser waits for a plan or a start: the server gives a script CHANGE_LIMIT (60 s, scripts/web-serve.py), so a little more. A busy
// server (load average above the cores) may answer late or never; without this a toast or dialog would wait for ever (tests/web-plan-timeout.mjs).
export const CHANGE_WAIT_MS = 75000;

async function call(method, path, body, ageKey, signal, timeoutMs = 0) {
  let timedOut = false;
  if (timeoutMs > 0) {
    const ctl = new AbortController();
    const timer = setTimeout(() => { timedOut = true; ctl.abort(); }, timeoutMs);
    if (signal) { if (signal.aborted) ctl.abort(); else signal.addEventListener('abort', () => ctl.abort(), { once: true }); }
    signal = ctl.signal;
    try { return await call1(method, path, body, ageKey, signal); }
    catch (e) {
      if (timedOut && e.name === 'AbortError') {
        const t = new Error(`The server did not answer within ${Math.round(timeoutMs / 1000)} seconds. It may be busy: check Jobs for the change, then try again.`);
        t.status = 0; t.timeout = true;
        throw t;
      }
      throw e;
    } finally { clearTimeout(timer); }
  }
  return call1(method, path, body, ageKey, signal);
}

async function call1(method, path, body, ageKey, signal) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET' && csrf) headers['X-CSRF-Token'] = csrf;
  const r = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin', signal });
  if (method === 'GET' && r.ok) ages.set(ageKey ?? path, { age: Number(r.headers.get('X-HS-Age') ?? 0) || 0, at: Date.now() });
  if (method === 'GET' && r.ok) {
    const st = r.headers.get('X-HS-Status');
    const ok = Number(r.headers.get('X-HS-Last-Ok'));
    if (st) {
      states.set(ageKey ?? path, {
        status: st, topic: r.headers.get('X-HS-Topic') || '', error: r.headers.get('X-HS-Error') || '',
        lastOk: ok > 0 ? ok * 1000 : st === 'fresh' ? Date.now() : Date.now() - (Number(r.headers.get('X-HS-Age') ?? 0) || 0) * 1000,
      });
    } else states.delete(ageKey ?? path);
  }
  let data = null;
  try { data = await r.json(); } catch { /* no body */ }
  if (!r.ok) {
    const e = new Error((data && data.error) || `Request failed (${r.status})`);
    e.status = r.status;
    e.retryAfter = data && data.retry_after;
    throw e;
  }
  return data;
}

// a one-use ticket for the terminal WebSocket; target is 'host' or an instance name
export const terminalTicket = (target) => call('POST', '/api/terminal', { target });

// a one-use ticket for the graphical console WebSocket of a virtual machine (ADR 0019)
export const vmConsoleTicket = (target) => call('POST', '/api/vmconsole', { target });

// the last revision of the changelog this user has seen (What's new), kept on the server
export const settingsLayout = () => call('GET', '/api/settings-layout');
export const changesSeen = () => call('GET', '/api/changes/seen');
export const liveRefresh = (topic) => call('POST', '/api/live/refresh', { topic });
// the delay sample of the Live state page (#486): topic and milliseconds, nothing else
// one POST carries up to 20 samples ({samples: [{topic, ms}, ...]}); the single form {topic, ms} still works
export const liveSamples = (samples) => call('POST', '/api/live/sample', { samples });
export const liveSample = (topic, ms) => call('POST', '/api/live/sample', { topic, ms });
// D13: the topics of the open event stream `sid` (the answer carries the gens of the added topics)
export const subscribeTopics = (sid, topics) => call('POST', '/api/events/subscribe', { sid, topics });
export const markChangesSeen = (rev) => call('POST', '/api/changes/seen', { rev });

export const hello = () => call('GET', '/api/hello');

// the web sessions (Settings > Users and access): list, end one, end all but this one
export const sessions = () => call('GET', '/api/sessions');
export const endSession = (id) => call('POST', '/api/sessions/end', { id });
export const endOtherSessions = () => call('POST', '/api/sessions/end-others', {});

export async function session() {
  try {
    const s = await call('GET', '/api/session');
    csrf = s.csrf;
    return s;
  } catch (e) {
    if (e.status === 401) return null;
    throw e;
  }
}

export async function login(realm, user, password) {
  const s = await call('POST', '/api/login', { realm, user, password });
  forgetReads();
  csrf = s.csrf;
  return s;
}

export async function setup(token, password) {
  const s = await call('POST', '/api/setup', { token, password });
  forgetReads();
  csrf = s.csrf;
  return s;
}

export async function logout() {
  await call('POST', '/api/logout', {});
  forgetReads();
  csrf = '';
}

// A read: /api/sys/<words...>[?query]. 401 means the session ended (the app then shows the sign-in page).
let onAuthLost = () => {};
export const setAuthLostHandler = (fn) => { onAuthLost = fn; };

// a page of text (the guides are Markdown); an error answer is still JSON
export async function getText(path) {
  const r = await fetch(path, { credentials: 'same-origin' });
  if (r.status === 401) onAuthLost();
  if (!r.ok) {
    let data = null;
    try { data = await r.json(); } catch { /* no body */ }
    const e = new Error((data && data.error) || `Request failed (${r.status})`);
    e.status = r.status;
    throw e;
  }
  return r.text();
}

// One running GET per address: a later caller joins it instead of asking again (the early reads after unlock, a field and a page that want the same
// list). A request that is done, failed or aborted leaves at once, so the next caller asks anew. One older than JOIN_MS is not joined (it may never
// be answered). forgetReads() is for every moment after which a running answer may be too old: a change, a job that ended, an event of the live
// stream, another sign-in. Callers that wait already still get their answer.
export const JOIN_MS = 30000;
const reading = new Map();   // path -> { at, p }
export const forgetReads = () => reading.clear();

// fresh: the refresh button; the server runs the scripts now instead of answering from what it holds. It never joins an older request, and
// nobody joins the older one after it
export function get(path, fresh = false) {
  if (fresh) { reading.delete(path); return read(path, true); }
  const hit = reading.get(path);
  if (hit && Date.now() - hit.at < JOIN_MS) return hit.p;
  const entry = { at: Date.now(), p: null };
  entry.p = read(path, false).finally(() => { if (reading.get(path) === entry) reading.delete(path); });
  reading.set(path, entry);
  return entry.p;
}

async function read(path, fresh) {
  try {
    return await call('GET', fresh ? path + (path.includes('?') ? '&' : '?') + 'fresh=1' : path, undefined, path);
  } catch (e) {
    if (e.status === 401) { forgetReads(); onAuthLost(); }
    throw e;
  }
}

// A change is always a plan first, then a start (with the typed word when the plan has a confirm_name).
// selection: the file manager's list of item names (the server hands it to the script on stdin, NUL separated)
// document: the docker app-save body (the server serializes it as bytes on stdin)
const planCall = (area, args, stdin, selection, signal, document) => call('POST', '/api/plan', { area, args, ...(stdin ? { stdin } : {}), ...(selection ? { selection } : {}), ...(document !== undefined ? { document } : {}) }, undefined, signal, CHANGE_WAIT_MS);   // an aborted call rejects with e.name === 'AbortError'

// A plan only reads, so a button can ask for it when the pointer arrives (prefetchPlan, never more than PREFETCH_MAX at once) and the dialog that opens a moment later takes the
// answer that is already running or done. Never with stdin, a selection or a document (secrets, file lists); a start forgets everything.
const PLAN_KEEP_MS = 30000;
const PREFETCH_MAX = 2;          // plans a hover or focus may have running at once: a browser keeps 6 connections per server, the rest belongs to the click, the reads and the streams
const PREFETCH_WAIT_MS = 20000;  // a hover plan that is not answered by then is dropped (the click asks again): it must not hold a connection for the full minute
const planned = new Map();   // "area args" -> { at, p, speculative, done }
const planKey = (area, args) => [area, ...args].join(' ');
const running = () => { let n = 0; for (const e of planned.values()) if (e.speculative && !e.done) n++; return n; };

// speculative: a hover or focus asked it, nobody waits for it yet. It is skipped when PREFETCH_MAX are running (null), is never asked twice while the
// first one still runs (the 30 s count from the answer, not from the question), and is aborted after PREFETCH_WAIT_MS. Without these limits a slow
// server filled the browser's 6 connections with plans and the Start of the click never left the browser (no /api/start in the log, a toast that spun).
export function prefetchPlan(area, args, speculative = true) {
  const key = planKey(area, args);
  const hit = planned.get(key);
  if (hit && (!hit.done || Date.now() - hit.at < PLAN_KEEP_MS)) return hit.p;
  if (speculative && running() >= PREFETCH_MAX) return Promise.resolve(null);
  const ctl = new AbortController();
  const entry = { at: Date.now(), p: null, speculative, done: false, ctl };
  const timer = speculative ? setTimeout(() => { entry.timedOut = true; ctl.abort(); }, PREFETCH_WAIT_MS) : 0;
  entry.p = planCall(area, args, undefined, undefined, ctl.signal);
  planned.set(key, entry);
  entry.p.then(() => { entry.done = true; entry.at = Date.now(); }, () => { entry.done = true; if (planned.get(key) === entry) planned.delete(key); }).finally(() => clearTimeout(timer));   // a failure is asked again, not kept
  return entry.p;
}

// a call with a signal (the create dialog's live plan: a newer question cancels the older one) is never shared; a document bypasses prefetch.
// A click joins a hover plan that is running; when that one is dropped for being slow, the click asks once itself.
export const plan = (area, args, stdin, selection, signal, document) => {
  if (stdin || selection || signal || document !== undefined) return planCall(area, args, stdin, selection, signal, document);
  const key = planKey(area, args);
  const hit = planned.get(key);
  if (hit) hit.speculative = false;      // somebody waits for it now
  return prefetchPlan(area, args, false).catch((e) => {
    if (hit && hit.timedOut) return prefetchPlan(area, args, false);
    throw e;
  });
};
export const start = (area, args, confirm, stdin, selection, document) => {
  planned.clear();
  forgetReads();
  return call('POST', '/api/start', { area, args, ...(confirm ? { confirm } : {}), ...(stdin ? { stdin } : {}), ...(selection ? { selection } : {}), ...(document !== undefined ? { document } : {}) }, undefined, undefined, CHANGE_WAIT_MS)
    .finally(forgetReads);   // a read that began while the start was on its way may show the old state
};
