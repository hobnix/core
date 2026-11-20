import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  root: new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'),
  plugins: [svelte()],
  server: { port: 5199, strictPort: true, fs: { strict: false } },
});
