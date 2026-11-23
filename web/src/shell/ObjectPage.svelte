<script>
  // The Object template (docs/PLAN-web-design.md 3.2): the page of ONE disk, pool, share, instance, user (0.11) and, in 0.12, package and app. Every object page is
  // this frame and fills in its content; it does not invent its own. The props are fixed in 0.11 step 1 (written down in PLAN-web-design 3.2); 0.12 reuses them.
  //   <ObjectPage crumb="Storage > Disks" title={name} chip="zfs" state="ok" stateLabel="healthy" {tabs} {tab} onpick={(id) => go(diskPath(name, id))}
  //               menu={[{ label: 'Long test', icon: 'pulse', need: 'admin', onclick }]} danger={[{ label: 'Format…', text, need: 'admin', onclick }]}
  //               links={[{ kind: 'Pool', name, href, state }]} jobs={(r) => r.description.includes(serial)} need="admin" loading={!mon.loaded} notFound={!disk} notFoundTitle="No such disk">
  //     {#snippet primary()}<Button variant="primary">Add to a pool…</Button>{/snippet}      (visible actions: ONE primary and at most ONE secondary, D4)
  //     {#snippet banners()}…{/snippet}                                                        (state banners: a running job, a failure)
  //     {#snippet children(tab)}…the body of the active tab…{/snippet}
  //   </ObjectPage>
  // Props: crumb, title, sub | chip, state, stateLabel (the status next to the name) | tabs [{id,label}] (at most 4, the first is Overview) and tab (the active id from the
  // address; unknown = Overview) and onpick(id) | menu (the More menu: items of ui/Menu, plus `need`: below the role it is greyed with the refusal) | danger (items of
  // ui/DangerZone, last on the page) | links (items of LinkedObjects, shown under the Overview) | jobs (match(record) of JobStrip; omit for no strip) and jobHref |
  // need (the role that may change the object: below it the page is read-only with a note, nothing is refused) | loading, error, notFound, notFoundTitle/notFoundText,
  // backTo/backLabel (an address of an object that does not exist is a sentence and a way back, never a blank page) | primary, banners, children snippets.
  import { go } from '../route.svelte.js';
  import { ui } from '../ui.svelte.js';
  import PageHeader from './PageHeader.svelte';
  import PageState from './PageState.svelte';
  import JobStrip from './JobStrip.svelte';
  import LinkedObjects from './LinkedObjects.svelte';
  import StatusDot from '../ui/StatusDot.svelte';
  import Chip from '../ui/Chip.svelte';
  import Banner from '../ui/Banner.svelte';
  import Button from '../ui/Button.svelte';
  import Menu from '../ui/Menu.svelte';
  import PageTabs from '../ui/PageTabs.svelte';
  import Stack from '../ui/Stack.svelte';
  import DangerZone from '../ui/DangerZone.svelte';
  import { frameTabs, activeTab, menuFor, readOnlyNote } from './objectpage.js';

  let {
    crumb = '', title = '', sub = '', chip = '', state = '', stateLabel = '', tabs = [], tab = '', onpick = null, menu = [], danger = [], links = [], jobs = null,
    jobHref = undefined, need = 'admin', loading = false, error = '', notFound = false, notFoundTitle = 'Not found', notFoundText = '', backTo = '', backLabel = 'Back to the list',
    primary, banners, children,
  } = $props();

  const list = $derived(frameTabs(tabs));
  const active = $derived(activeTab(list, tab));
  const items = $derived(menuFor(menu, ui.role));
  const note = $derived(readOnlyNote(ui.role, need));
</script>

<PageState {loading} {error} hasData={!loading && !notFound} empty={notFound} emptyIcon="warning-circle" emptyTitle={notFoundTitle} emptyText={notFoundText}>
  {#snippet emptyAction()}{#if backTo}<Button tooltip={backLabel} onclick={() => go(backTo)}>{backLabel}</Button>{/if}{/snippet}
  <Stack gap="6">
    <PageHeader {title} {crumb} {sub}>
      {#snippet actions()}
        {#if chip}<Chip>{chip}</Chip>{/if}
        {#if state}<StatusDot {state} label={stateLabel} />{/if}
        {@render primary?.()}
        {#if items.length}<Menu {items} label="More actions for {title}" />{/if}
      {/snippet}
    </PageHeader>
    {#if note}<Banner tone="info">{note}</Banner>{/if}
    {@render banners?.()}
    {#if jobs}<JobStrip match={jobs} {...(jobHref ? { href: jobHref } : {})} />{/if}
    {#if list.length > 1}<PageTabs tabs={list} tab={active} onpick={(id) => onpick?.(id)} />{/if}
    <Stack gap="6">{@render children?.(active)}</Stack>
    {#if active === 'overview' || list.length < 2}<LinkedObjects items={links} />{/if}
    <DangerZone actions={danger} />
  </Stack>
</PageState>
