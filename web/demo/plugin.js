// Vite plugin of demo mode (`npm run demo` in web/): answers /api/* from the fixtures in web/demo/fixtures, nothing else runs.
// The fixture is chosen with ?fixture=<name> on any page (kept in a cookie); HS_DEMO_FIXTURE sets the default. Names: fixtures/*.json.
import { INDEX, page, search } from './docs.js';
import { answer, fixture, fixtureNames, DEFAULT_FIXTURE } from './engine.js';

const cookieOf = (req) => (/(?:^|;\s*)hs-demo=([a-z0-9-]+)/.exec(req.headers.cookie || '') || [])[1];

function readBody(req) {
  return new Promise((resolve) => {
    let s = '';
    req.on('data', (c) => { s += c; if (s.length > 1e6) req.destroy(); });
    req.on('end', () => { try { resolve(s ? JSON.parse(s) : {}); } catch { resolve({}); } });
  });
}

export default function demoPlugin() {
  const fallback = process.env.HS_DEMO_FIXTURE || DEFAULT_FIXTURE;
  return {
    name: 'hobnix-demo',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const url = new URL(req.url, 'http://demo.local');
        const asked = url.searchParams.get('fixture');
        if (asked && fixtureNames().includes(asked)) res.setHeader('Set-Cookie', `hs-demo=${asked}; Path=/; SameSite=Lax`);
        const fx = fixture(asked || cookieOf(req) || fallback);
        const stream = (first) => {
          res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
          res.write(first);
        };
        if (url.pathname === '/api/events') {          // the live stream: open, then a beat; nothing ever changes
          stream('event: open\ndata: {}\n\n');
          const t = setInterval(() => res.write('event: beat\ndata: {}\n\n'), 15000);
          req.on('close', () => clearInterval(t));
          return;
        }
        if (url.pathname.startsWith('/api/sys/jobs/stream/')) {      // no job ever runs, so there is nothing to follow
          stream('data: {"rows":[]}\n\n');
          res.end();
          return;
        }
        const ls = /^\/api\/logs\/stream\/(ct|docker|system|events)$/.exec(url.pathname);
        if (ls) {      // a log stream (D15): the fixture's log as the fill, then the stream stays open and quiet
          const target = encodeURIComponent(url.searchParams.get('target') || '');
          const read = { ct: `/api/sys/ct/logs/${target}`, docker: `/api/sys/docker/logs/${target}`, system: '/api/sys/logs/show', events: '/api/sys/state/events' }[ls[1]];
          const a = answer('GET', read, Object.fromEntries(url.searchParams), undefined, fx);
          const b = a.body || {};
          const lines = Array.isArray(b.rows) ? [...b.rows].reverse().map((r) => r.join('\t')) : String(b.text || '').split('\n').filter(Boolean);
          stream('retry: 3000\n\n' + (lines.length ? `data: ${JSON.stringify({ lines })}\n\n` : ': empty\n\n'));
          const t = setInterval(() => res.write(': ping\n\n'), 15000);
          req.on('close', () => clearInterval(t));
          return;
        }
        if (url.pathname === '/theme.css') {
          res.writeHead(200, { 'Content-Type': 'text/css' });
          res.end(':root{--color-accent:#9184d9}');
          return;
        }
        if (url.pathname.startsWith('/api/docs/')) {      // the guides: made-up ones (web/demo/docs.js)
          const m = /^\/api\/docs\/page\/[a-z]+\/([^/]+)$/.exec(url.pathname);
          const send = (code, type, text) => { res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' }); res.end(text); };
          if (url.pathname === '/api/docs/index') return send(200, 'application/json', JSON.stringify(INDEX));
          if (url.pathname === '/api/docs/search') return send(200, 'application/json', JSON.stringify(search(url.searchParams.get('q'))));
          const t = m && page(decodeURIComponent(m[1]));
          return t === null || !m ? send(404, 'application/json', '{"error":"no such guide"}') : send(200, 'text/markdown; charset=utf-8', t);
        }
        if (!url.pathname.startsWith('/api/')) return next();
        const body = req.method === 'POST' ? await readBody(req) : undefined;
        const a = answer(req.method, url.pathname, Object.fromEntries(url.searchParams), body, fx);
        res.writeHead(a.status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...a.headers });
        res.end(JSON.stringify(a.body));
      });
    },
  };
}
