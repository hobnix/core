<script>
  import { P } from './paths.js';
  import { onMount } from 'svelte';
  import { session, logout, setAuthLostHandler } from './api.js';
  import { initLang } from './lang.svelte.js';
  import { clearPollCache } from './data.svelte.js';
  import { live, startLive, stopLive, setTopics } from './live.svelte.js';
  import { startRowState } from './rowstate.svelte.js';
  import { ui } from './ui.svelte.js';
  import Shell from './shell/Shell.svelte';
  import Login from './Login.svelte';
  import Terminal from './shell/Terminal.svelte';
  import Tooltip from './ui/Tooltip.svelte';
  import Kiosk from './dashboard/Kiosk.svelte';
  import { go } from './route.svelte.js';

  let user = $state(null);
  let ready = $state(false);
  // a terminal popped out of the page: /?terminal=host|<instance>&title=...
  const pop = new URLSearchParams(location.search).get('terminal');
  const popTitle = new URLSearchParams(location.search).get('title') ?? '';

  // the full-screen dashboard: no sign-in, session() is not called
  const kiosk = location.pathname === '/dashboard';

  setAuthLostHandler(() => { stopLive(); clearPollCache(); user = null; ui.role = 'viewer'; });

  // the event stream runs while somebody is signed in (served always, ADR 0005 rule 5; `live.open` says it is up)
  $effect(() => { setTopics(ui.features.topics ?? {}); live.follow = !!ui.features.live; if (user) { startLive(); startRowState(); } else stopLive(); });

  onMount(async () => {
    if (kiosk) return;
    try { user = await session(); } catch { user = null; }
    ui.features = user?.features ?? { terminal: false, vps: false };
    ui.role = user?.role ?? 'viewer';
    initLang(ui.features.language);
    if (ui.features.setup_wizard) go(P.firstRun);
    ready = true;
  });

  async function signOut() {
    try { await logout(); } catch { /* the session is gone either way */ }
    stopLive();
    clearPollCache();
    user = null;
    ui.role = 'viewer';
  }
</script>

{#if kiosk}
  <Kiosk />
{:else if !ready}
  <div style="flex:1"></div>
{:else if !user}
  <Login onsignedin={(s) => { ui.features = s?.features ?? { terminal: false, vps: false }; ui.role = s?.role ?? 'viewer'; initLang(ui.features.language); user = s; if (ui.features.setup_wizard) go(P.firstRun); }} />
{:else if pop && ui.features.terminal}
  <Terminal target={pop} title={popTitle} page />
{:else}
  <Shell {user} onsignout={signOut} />
{/if}

<Tooltip />
