// Vite plugin of demo mode (`npm run demo` in web/): answers /api/* from the fixtures in web/demo/fixtures, nothing else runs.
// The fixture is chosen with ?fixture=<name> on any page (kept in a cookie); HS_DEMO_FIXTURE sets the default. Names: fixtures/*.json.
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
        if (url.pathname === '/theme.css') {
          res.writeHead(200, { 'Content-Type': 'text/css' });
          res.end(':root{--color-accent:#9184d9}');
          return;
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
