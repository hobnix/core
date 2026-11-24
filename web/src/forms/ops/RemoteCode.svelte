<script>
  // The code of "Give access" / "New code…": shown once, in this browser tab only. Nothing is stored; closing the dialog forgets the code.
  // It turns into "<server> connected, key SHA256:..." when the event remote.claimed of this share arrives (the live stream; the countdown is a display tick
  // only, it asks the server nothing).
  import Dialog from '../../ui/Dialog.svelte';
  import Button from '../../ui/Button.svelte';
  import { Muted } from '../../ui/index.js';
  import { live } from '../../live.svelte.js';
  import { codeAnswer, shown, countdown, claimsOf, claimState } from './remotecode.js';

  let { offer, onclose } = $props();

  const a = codeAnswer(offer);
  const fromId = live.lastId;               // only events after the dialog opened count
  const until = Date.now() / 1000 + (a?.seconds ?? 0) + 5;   // epoch seconds; a claim later than this is not of this code (5 s for clocks)
  let left = $state(a?.seconds ?? 0);
  let copied = $state(false);
  const claimed = $derived(claimState(claimsOf(live.events, { fromId, until, share: offer.share, server: offer.peer }), !!offer.peer));

  $effect(() => {
    if (claimed || left <= 0) return;
    const t = setInterval(() => { left -= 1; }, 1000);
    return () => clearInterval(t);
  });

  async function copy() {
    try { await navigator.clipboard.writeText(shown(a)); copied = true; } catch { copied = false; }
  }
</script>

<Dialog labelledby="rct" panel="dialog" width="560px" onclose={onclose}>
  <div style="display:flex;flex-direction:column;gap:14px">
    <span class="kicker">Remote shares</span>
    {#if claimed?.kind === 'ambiguous'}
      <div id="rct" class="dialog-title">A server used a code for {offer.share}</div>
      <div class="lede">Several servers took {offer.share} just now, so this window cannot tell which one used this code:</div>
      <ul>{#each claimed.claims as c}<li>{c.server || 'a server'}, key <code>{c.fingerprint}</code></li>{/each}</ul>
      <Muted>The list of shares you give shows who can read it. Take back… on a row removes one.</Muted>
      <div class="dialog-actions"><span style="flex:1"></span><Button variant="primary" onclick={onclose}>Close</Button></div>
    {:else if claimed}
      <div id="rct" class="dialog-title"><i class="ph ph-check-circle"></i> {claimed.server} connected</div>
      <div class="lede">{claimed.server} can now read {offer.share}.{#if claimed.fingerprint} Its key is <code>{claimed.fingerprint}</code>. Check that it is the key of that server.{/if}</div>
      <div class="dialog-actions"><span style="flex:1"></span><Button variant="primary" onclick={onclose}>Close</Button></div>
    {:else if a}
      <div id="rct" class="dialog-title">{offer.peer ? `Code for ${offer.peer}` : 'Code for another server'}</div>
      <div class="lede">Type this code on the other server under Shares, Add remote share. <b>It is shown only now</b> and is not kept anywhere.</div>
      <pre style="margin:0;padding:8px 10px;font-size:14px;white-space:pre-wrap;word-break:break-all;user-select:all">{shown(a)}</pre>
      <Muted>{left > 0 ? `Works once, for ${countdown(left)} more.` : 'This code has run out. Make a new one.'} Take the access away again with Take back… on the row.</Muted>
      <div class="dialog-actions">
        <Button variant="ghost" disabled={left <= 0} tooltip={'Copy the code to the clipboard'} onclick={copy}><i class="ph ph-copy"></i>{copied ? 'Copied' : 'Copy code'}</Button>
        <span style="flex:1"></span>
        <Button variant="primary" onclick={onclose}>Close</Button>
      </div>
    {:else}
      <div id="rct" class="dialog-title">No code</div>
      <div class="lede">The server did not return a code. Try again.</div>
      <div class="dialog-actions"><span style="flex:1"></span><Button variant="primary" onclick={onclose}>Close</Button></div>
    {/if}
  </div>
</Dialog>
