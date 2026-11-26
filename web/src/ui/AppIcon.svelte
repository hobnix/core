<script>
  // The square icon tile of an app or package: a Phosphor icon by name, or a picture (`src`, the package's own svg icon from the asset endpoint).
  // A picture that does not load falls back to the icon. The picture is an <img>: an svg drawn that way runs no script (the endpoint is sandboxed too).
  //   <AppIcon icon="film-strip" />   <AppIcon src="/api/pkg/asset/official/jellyfin/icon.svg" icon="package" size="lg" />
  // `icon` comes from package data, so only a plain Phosphor name is used (anything else is the package icon); `on` tints it with the accent.
  let { icon = 'package', src = '', size = 'md', on = false, label = '' } = $props();
  let broken = $state(false);
  $effect(() => { src; broken = false; });
  const name = $derived(/^[a-z0-9]+(-[a-z0-9]+)*$/.test(icon) ? icon : 'package');
</script>

<span class="aicon {size}" class:on role={label ? 'img' : undefined} aria-label={label || undefined} aria-hidden={label ? undefined : 'true'}>
  {#if src && !broken}<img {src} alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer" onerror={() => (broken = true)} />
  {:else}<i class="ph ph-{name}"></i>{/if}
</span>

<style>
  .aicon { display: inline-grid; place-items: center; flex: none; width: 40px; height: 40px; border: 1px solid var(--line); border-radius: var(--r); background: var(--panel-2); color: var(--fg-3); overflow: hidden; }
  .aicon i { font-size: 22px; }
  .aicon.lg { width: 64px; height: 64px; }
  .aicon.lg i { font-size: 34px; }
  .aicon.on { color: var(--accent-ink); }
  img { width: 72%; height: 72%; object-fit: contain; }
</style>
