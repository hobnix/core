// Demo mode: answers of the web API from made-up fixtures, no server and nothing changed. Used by plugin.js (vite) and tests/web-demo.mjs.
// A read is answered from fixtures/<name>.json laid over fixtures/base.json; a plan is a generic plan with a note; a start is always refused.
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'fixtures');
export const DEFAULT_FIXTURE = 'healthy';
export const DEMO_NOTE = 'Demo mode: this interface shows made-up data. Nothing was changed.';
const CAPABILITIES = ['ad', 'backup', 'dashboard', 'docker', 'docs', 'gateway', 'incus', 'live-state', 'metrics', 'network', 'notifications', 'reverse-proxy', 'samba', 'storage', 'tailscale'];

const load = (name) => JSON.parse(readFileSync(join(dir, name + '.json'), 'utf8'));
export const fixtureNames = () => readdirSync(dir).filter((f) => f.endsWith('.json') && f !== 'base.json').map((f) => f.slice(0, -5)).sort();
export const baseReads = () => load('base').reads;

// fixture name -> { name, title, locked, reads } (base laid under the fixture's own reads); an unknown name is the default
export function fixture(name) {
  const n = fixtureNames().includes(name) ? name : DEFAULT_FIXTURE;
  const f = load(n);
  return { name: n, title: f.title || n, locked: !!f.locked, reads: { ...baseReads(), ...f.reads } };
}

const json = (status, body, headers = {}) => ({ status, body, headers });

// the keys a read may have in a fixture, most specific first: words + query ("pool/info?pool=bulk"), words, then fewer words (ct/bindings/<name>)
function readKeys(path, query) {
  const words = path.replace(/^\/api\/sys\//, '').split('/').filter(Boolean).map(decodeURIComponent);
  const q = Object.keys(query).filter((k) => k !== 'fresh').sort().map((k) => `${k}=${query[k]}`).join('&');
  const keys = [];
  for (let n = words.length; n >= 1; n--) {
    const k = words.slice(0, n).join('/');
    if (q) keys.push(`${k}?${q}`);
    keys.push(k);
  }
  return keys;
}

export function read(fx, path, query = {}) {
  for (const k of readKeys(path, query)) {
    if (!(k in fx.reads)) continue;
    const v = fx.reads[k];
    if (Array.isArray(v)) return json(200, { rows: v, rc: 0 }, { 'X-HS-Age': '0' });
    if (typeof v === 'string') return json(200, { text: v, rc: 0 }, { 'X-HS-Age': '0' });
    if (k === 'deck') {      // the counters move on every read, so the graphs of the Overview are not flat
      const t = Math.floor(Date.now() / 1000);
      const busy = (t * 7) % 40;
      return json(200, { ...v, time: t, net: { rx: t * 40000, tx: t * 9000 }, cpu: { total: t * 800, idle: t * 800 - busy * 20 - t * 80 } }, { 'X-HS-Age': '0' });
    }
    return json(200, v, { 'X-HS-Age': '0' });
  }
  return json(404, { error: 'Demo mode has no made-up answer for this read.' });
}

export function plan(body) {
  const words = [body.area, ...(body.args || [])].filter(Boolean).join(' ').replace(/\//g, ' ');
  return json(200, {
    exit: 0, status: 'ok', reason: '', heading: `Demo: ${words}`, command: `hs ${words}`, confirm_name: '', long: false, unit: '',
    needs: [], options: [], fixes: [], steps: [['step', 'On a real server this lists what would happen.'], ['note', DEMO_NOTE]],
  });
}

export const start = () => json(200, { exit: 1, status: 'refused', reason: DEMO_NOTE, heading: '', command: '', confirm_name: '', long: false, unit: '', needs: [], options: [], steps: [], fixes: [] });

// Everything under /api/ except the event streams. -> { status, body, headers }, or null when this is not an API path
export function answer(method, path, query, body, fx) {
  if (!path.startsWith('/api/')) return null;
  if (method === 'GET') {
    if (path === '/api/hello') return json(200, { locked: fx.locked, domain: null, local_user: 'admin', setup: { open: false }, facts: {} });
    if (path === '/api/session') {
      return json(200, {
        user: 'demo', realm: 'local', role: 'admin', csrf: 'demo',
        features: { setup_wizard: false, terminal: false, vps: false, capabilities: CAPABILITIES, extensions: [], host: 'demo', language: '', dashboard: '', live: false, topics: {}, demo: fx.name },
      });
    }
    if (path === '/api/settings-layout') return json(200, {});
    if (path === '/api/sessions') return json(200, { sessions: [] });
    if (path === '/api/changes/seen') return json(200, { rev: null });
    if (path === '/api/proxy/status') return json(200, { state: 'none' });
    if (path.startsWith('/api/sys/')) return read(fx, path, query);
    return json(404, { error: 'Demo mode has no made-up answer for this.' });
  }
  if (path === '/api/plan') return plan(body || {});
  if (path === '/api/start') return start();
  if (path === '/api/logout' || path === '/api/changes/seen' || path === '/api/live/refresh') return json(200, {});
  if (path === '/api/login') return json(200, { user: 'demo', realm: 'local', role: 'admin', csrf: 'demo' });
  return json(403, { error: DEMO_NOTE });
}
