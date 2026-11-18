<script>
  // Settings > Users and access. An admin gets the settings page; every other role gets the one card it may use, its own web sessions
  // (the server lists and ends only the person's own for a role below admin, scripts/web-serve.py /api/sessions).
  import { ui } from '../ui.svelte.js';
  import SettingsPage from './SettingsPage.svelte';
  import Sessions from './Sessions.svelte';
  let { deck } = $props();
</script>

{#if ui.role === 'admin'}<SettingsPage {deck} />{:else}<Sessions own />{/if}
