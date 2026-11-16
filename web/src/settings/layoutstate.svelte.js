// The Settings layout as the pages use it: layout.gen.json (the built-in parts) merged with what the capability packages installed on this machine bring
// (GET /api/settings-layout). No timer: it is read when a page starts and again when the list of parts that are on changes (an install or a removal ends
// in that), so a package's options show without a rebuild.
import core from './layout.gen.json';
import { mergeLayout } from './layout.js';
import { settingsLayout } from '../api.js';
import { ui } from '../ui.svelte.js';

let overlay = $state(null);

// Call once from a component's script (it starts an effect). Returns () => the merged layout.
export function useLayout() {
  $effect(() => {
    void JSON.stringify(ui.features.capabilities);   // read again when the parts that are on change
    settingsLayout().then((d) => { overlay = d; }, () => {});
  });
  return () => mergeLayout(core, overlay);
}
