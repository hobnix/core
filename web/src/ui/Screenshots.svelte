<script>
  // The pictures of an app in one row that scrolls sideways; each one opens on its own in a new tab. `shots`: [{ src, alt }].
  // Only png and webp pictures come here (an svg is never a screenshot), and the asset endpoint checks the type against the bytes.
  //   <Screenshots shots={[{ src: '/api/pkg/asset/official/jellyfin/shots/a.webp', alt: 'jellyfin, picture 1' }]} />
  let { shots = [], label = 'Pictures' } = $props();
  let broken = $state(new Set());
</script>

{#if shots.some((s) => !broken.has(s.src))}
  <ul class="shots" aria-label={label}>
    {#each shots as s (s.src)}
      {#if !broken.has(s.src)}
        <li><a href={s.src} target="_blank" rel="noopener noreferrer"><img src={s.src} alt={s.alt} loading="lazy" decoding="async" referrerpolicy="no-referrer" onerror={() => (broken = new Set([...broken, s.src]))} /></a></li>
      {/if}
    {/each}
  </ul>
{/if}

<style>
  .shots { display: flex; gap: var(--space-3); margin: 0; padding: 0 0 var(--space-2); list-style: none; overflow-x: auto; scroll-snap-type: x mandatory; }
  li { flex: none; scroll-snap-align: start; }
  a { display: block; border: 1px solid var(--line); border-radius: var(--r); overflow: hidden; background: var(--panel-2); }
  img { display: block; height: 220px; width: auto; max-width: min(80vw, 520px); object-fit: contain; }
</style>
