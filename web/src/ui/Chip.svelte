<script>
  // Small mono label; the one chip of the interface (the old `tag` class is gone). Colour never tells alone: trust and status chips carry an icon and a word.
  //   <Chip>zfs</Chip>   <Chip kind="out">outside</Chip>   <Chip kind="in">this server</Chip>   <Chip tone="accent">this browser</Chip>
  // kind: '' plain | strong (high contrast, over the halftone) | out / in (pill: outside this server / this server)
  //       trust  = who vouches for a package (#477), in words: `level` official ("Official, signed": the official repository as the core configures
  //                it, signed) | community ("Community": any other signed repository) | unsigned ("Community, unsigned"); `tested` = the day it last
  //                ran on a real server (YYYY-MM-DD, optional), drawn after the word; children replace the word
  //                (<Chip kind="trust" level="official" tested="2026-11-18" />)
  //       status = the state of an object (its header): `state` ok | warn | bad | info | off, an icon of its own shape and a word (children, else the
  //                generic word of the state)
  //       fit    = does an app fit this server (#793): `level` fits | note | no | unstated | unknown, an icon of its own shape and the words as
  //                children (<Chip kind="fit" level="no">Does not fit this server</Chip>)
  // tone: '' | accent | soft | warn | bad | info (state colour); title: tooltip
  import { tip } from './tooltip.svelte.js';
  import Icon from './Icon.svelte';
  let { kind = '', tone = '', style = undefined, level = 'community', tested = '', state = 'off', title = undefined, children } = $props();

  const TRUST = {
    official: { icon: 'seal-check', word: 'Official, signed', tip: 'From the official Hobnix repository; its signature was checked' },
    community: { icon: 'users-three', word: 'Community', tip: 'From a repository that was added on this server, not by the Hobnix project; its signature was checked' },
    unsigned: { icon: 'warning', word: 'Community, unsigned', tip: 'From a repository without signatures: nobody vouches that these are the files its author published' },
  };
  const STATUS = {
    ok: { icon: 'check-circle', word: 'healthy' }, warn: { icon: 'warning', word: 'warning' }, bad: { icon: 'warning-octagon', word: 'failed' },
    info: { icon: 'info', word: 'in progress' }, off: { icon: 'pause-circle', word: 'off' },
  };
  const FIT = { fits: 'check-circle', note: 'warning', no: 'prohibit', unstated: 'question', unknown: 'warning-circle' };
  const f = $derived(kind === 'fit' ? (Object.hasOwn(FIT, level) ? level : 'unknown') : '');
  const t = $derived(kind === 'trust' ? (TRUST[level] ?? TRUST.community) : null);
  const s = $derived(kind === 'status' ? (STATUS[state] ?? STATUS.off) : null);
  const cls = $derived(kind === 'trust' ? `trust-${level}` : kind === 'status' ? `st-${state}` : f ? `fit-${f}` : `${kind} ${tone}`);
  const tipText = $derived(title ?? (t ? `${t.tip}${level !== 'official' ? '' : tested ? `. Tested on a real server on ${tested}` : '. Not tested on a real server'}` : undefined));
</script>

<span class="chip {cls}" {style} use:tip={tipText}>
  {#if t}<Icon name={t.icon} />{#if children}{@render children()}{:else}{t.word}{/if}{#if tested} <span class="date">tested {tested}</span>{/if}
  {:else if f}<Icon name={FIT[f]} />{@render children?.()}
  {:else if s}<Icon name={s.icon} />{#if children}{@render children()}{:else}{s.word}{/if}
  {:else}{@render children?.()}{/if}
</span>

<style>
  .chip { display: inline-flex; align-items: center; gap: 4px; font: 500 10.5px var(--mono); text-transform: uppercase; letter-spacing: 0.06em; padding: 1px 6px; border: 1px solid var(--line-2); border-radius: var(--r); color: var(--fg-3); white-space: nowrap; }
  .date { text-transform: none; letter-spacing: 0; color: var(--fg-3); }
  /* readable on top of the halftone: full text colour on the panel, so the dots do not show through */
  .strong { color: var(--fg); background: var(--panel); border-color: var(--fg-3); }
  .out { border-color: color-mix(in oklch, var(--info) 55%, var(--line)); color: var(--info-ink); }
  .accent, .trust-official { border-color: color-mix(in oklch, var(--accent) 55%, var(--line)); color: var(--accent-ink); }
  .soft, .trust-community, .fit-unstated, .fit-unknown { color: var(--fg-2); }
  .trust-unsigned { border-color: color-mix(in oklch, var(--warn) 55%, var(--line)); color: var(--warn-ink); }
  .warn, .st-warn, .fit-note { border-color: color-mix(in oklch, var(--warn) 55%, var(--line)); color: var(--warn-ink); }
  .bad, .st-bad, .fit-no { border-color: color-mix(in oklch, var(--bad) 55%, var(--line)); color: var(--bad-ink, var(--bad)); }
  .info, .st-info { border-color: color-mix(in oklch, var(--info) 55%, var(--line)); color: var(--info-ink); }
  .st-ok, .fit-fits { border-color: color-mix(in oklch, var(--ok) 55%, var(--line)); color: var(--ok-ink, var(--ok)); }
</style>
