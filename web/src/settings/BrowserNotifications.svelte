<script>
  // The "Browser notifications" block of the Settings page (General, #888): a switch that is off by default and kept in this browser only
  // (web/src/notify.svelte.js). Turning it on is the one place the browser's permission prompt is asked. The reason it cannot work (plain HTTP,
  // blocked, no support) is shown here. The watcher that raises them is in shell/Inbox.svelte. Mounted by settings/SettingsPage.svelte.
  import Switch from '../ui/Switch.svelte';
  import { nf, enableNotify, disableNotify } from '../notify.svelte.js';
  import { notifySupport } from '../shell/notify.js';

  let tries = $state(0);   // remounts the switch so it shows the real state after a refused prompt
  const support = $derived((tries, notifySupport()));
  async function change(v) {
    if (v) await enableNotify(); else disableNotify();
    tries += 1;
  }
</script>

<section class="card sec" id="browser-notifications" style="display:flex;flex-direction:column;gap:8px">
  <div class="st">Browser notifications</div>
  <div style="display:flex;align-items:center;gap:10px">
    {#key tries}
      <Switch checked={nf.on} disabled={!support.ok && !nf.on} reason={support.reason} label="Browser notifications" onchange={change} />
    {/key}
    <span>Show a notification when a new problem, warning or error appears while this page is open in the background</span>
  </div>
  {#if nf.reason || (!support.ok && !nf.on)}<p class="hp2" role="status">{nf.reason || support.reason}</p>{/if}
  <p class="hp2">Off by default and kept in this browser only. The browser asks for permission once, when you turn this on. Nothing is sent to another service.</p>
</section>
