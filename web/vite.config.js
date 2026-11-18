import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import demoPlugin from './demo/plugin.js';

// `npm run dev` talks to a backend on the same machine:  HS_WEB_ROOT=/nonexistent python3 scripts/web-serve.py 8480
const backend = process.env.HS_WEB_DEV_BACKEND || 'http://127.0.0.1:8480';

// `npm run demo` (vite --mode demo): no backend, the API is answered from made-up fixtures (web/demo/, docs/dev-environment.md "Demo mode")
export default defineConfig(({ mode }) => ({
  plugins: mode === 'demo' ? [demoPlugin(), svelte()] : [svelte()],
  server: mode === 'demo' ? {} : {
    proxy: {
      '/api': { target: backend, changeOrigin: false },
      '/theme.css': { target: backend, changeOrigin: false },
    },
  },
}));
