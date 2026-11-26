<script>
  // The page of one package in the Marketplace (#474): /apps/marketplace/<repo>/<name>, also the target of "Open on my server" on the website
  // (/marketplace/<repo>/<name> redirects here, docs/PLAN-marketplace-stats.md). What it is, its pictures, what it needs and uses, version,
  // source and signature, read from its newest verified release (hs sys pkg show) without installing anything. The buttons are the ones of its
  // card (Install opens the install dialog with its plan; an installed app has Open and Manage); Turn on/off and Remove are in the menu.
  // Below them the versions the signed index lists (hs sys pkg history): day, change text, withdrawn. It installs no older version.
  // Everything shown comes from a repository and is drawn as text; the only links are http and https (market.js safeLink).
  import { P, appPath } from '../paths.js';
  import { poll, rows, refresh } from '../data.svelte.js';
  import { ui, can } from '../ui.svelte.js';
  import { route, go } from '../route.svelte.js';
  import { refusal } from '../roles.js';
  import { rowstate } from '../rowstate.svelte.js';
  import PageHeader from '../shell/PageHeader.svelte';
  import PageState from '../shell/PageState.svelte';
  import { Button, Card, Chip, Banner, Kv, Grid, Stack, Row, Muted, Menu, EmptyState, ErrorNote, AppIcon, Screenshots, Icon } from '../ui/index.js';
  import { parseStates, stageActions } from './states.js';
  import { parseCards, parseRepos, storeRows, parseShow, usesOf, categoryLabel, kindLabel, stateLine, cardActions, openHref, assetUrl, trustOf, testedText, parseFit, fitLabel, fitText, parseHistory } from './market.js';
  import { runAction, busyOf, failureOf, needOf } from './marketrun.js';

  // the two words of the address (the route only sends a path that matches routes.js PACKAGE_PAGE)
  const words = $derived(route.path.slice(P.marketplace.length + 1).split('/'));
  const repo = $derived(words[0] ?? '');
  const name = $derived(words[1] ?? '');

  const market = poll('/api/sys/pkg/market', 30000);
  const repoList = poll('/api/sys/pkg/repos', 30000);
  const stateList = poll('/api/sys/pkg/states', 30000);
  const cardList = poll('/api/sys/pkg/cards', 120000, 'pkg-market');
  const show = poll(() => (repo && name ? `/api/sys/pkg/show/${name}?repo=${repo}` : ''), 120000, 'pkg-market');
  const historyList = poll(() => (repo && name ? `/api/sys/pkg/history/${name}?repo=${repo}` : ''), 120000, 'pkg-market');
  const svcApp = poll('/api/sys/services/app', 60000);
  const tiles = poll('/api/sys/services/tiles', 60000);
  const PATHS = ['/api/sys/pkg/market', '/api/sys/pkg/repos', '/api/sys/pkg/states', '/api/sys/pkg/cards'];
  const FIT = '/api/sys/pkg/fit';

  const p = $derived(storeRows(rows(market), parseCards(rows(cardList))).find((x) => x.repo === repo && x.name === name) ?? null);
  const s = $derived(parseShow(rows(show)));
  const unread = $derived(!!show.error || s.refused);
  const stage = $derived(parseStates(rows(stateList)).get(name));
  // only an app that is not installed is compared with this server (an installed one already uses what it needs)
  const compared = $derived(!!p && p.kind === 'recipe' && !p.installed);
  const fitList = poll(() => (compared ? FIT : ''), 120000, 'pkg-market');   // read only where its card is shown
  const fit = $derived(compared ? parseFit(rows(fitList)).get(`${repo}/${name}`) : undefined);
  // what a refresh reads again
  const paths = () => (compared ? [...PATHS, FIT] : PATHS);
  const FIT_ICON = { ok: 'check-circle', note: 'warning', no: 'prohibit', unstated: 'question', unknown: 'warning-circle' };
  const FIT_WORD = { ok: 'Fine', note: 'Note', no: 'Does not fit', unstated: 'Not stated', unknown: 'Not checked' };
  const history = $derived(parseHistory(rows(historyList)));
  const repoRow = $derived(parseRepos(rows(repoList)).find((r) => r.name === repo) ?? null);
  const withPage = $derived(new Set((ui.features.extensions ?? []).filter((e) => e.kind === 'recipe').map((e) => e.name)));
  const open = $derived(p ? openHref(stage?.instances, rows(svcApp), rows(tiles)) || (withPage.has(name) ? appPath(name) : '') : '');
  const acts = $derived(p ? cardActions(p, open) : []);

  // the rest of what can be done with it, in the menu: Turn on/off (an add-on that is here), Remove (anything that is here and not needed by the core)
  const more = $derived.by(() => {
    if (!p || !p.installed) return [];
    const out = [];
    const off = can('admin') ? '' : refusal(ui.role, 'admin');
    const turn = stageActions(stage).turn;
    if (turn) out.push({ label: turn === 'enable' ? 'Turn on' : 'Turn off', icon: 'power', disabled: !!off, reason: off, onclick: () => runAction(turn, p) });
    out.push({ label: 'Remove', icon: 'trash', danger: true, disabled: !!off || p.core, reason: off || (p.core ? 'The server refers to this package by name: it stays' : ''), onclick: () => runAction('remove', p) });
    return out;
  });

  const shots = $derived(s.screenshots.map((f, i) => ({ src: assetUrl(repo, name, f), alt: `${name}, picture ${i + 1}` })).filter((x) => x.src));
  const uses = $derived(usesOf(s));
  const source = $derived([
    { k: 'Version', v: p?.avail || s.version },
    { k: 'Version of the app', v: s.app_version },
    { k: 'Installed', v: p?.inst || 'no' },
    { k: 'Repository', v: repo },
    { k: 'Release', v: s.tag },
    { k: 'Commit', v: s.commit ? s.commit.slice(0, 12) : '' },
    { k: 'Signature', v: !repoRow ? '' : repoRow.signed ? 'checked: only signed releases are used' : 'none: this repository is not signed' },
  ]);

  // what a change did shows when its job ends; no timer
  const busyNow = $derived(['pkg', 'apps', 'parts'].some((a) => rowstate.pending(a)));
  let wasBusy = false;
  $effect(() => {
    if (wasBusy && !busyNow) refresh([...paths(), `/api/sys/pkg/show/${name}?repo=${repo}`, `/api/sys/pkg/history/${name}?repo=${repo}`]);
    wasBusy = busyNow;
  });
  const failure = $derived(p ? failureOf(p) : null);
  // who vouches for it (#477): the words of the trust chip, said once more as a sentence, and what the tested day covers
  const trust = $derived(trustOf(repo, parseRepos(rows(repoList))));
  const vouch = $derived(trust === 'official' ? 'It comes from the official Hobnix repository, and its release is signed with the key of the project. The signature is checked before anything is installed.'
    : trust === 'community' ? `It comes from the repository ${repo}, which was added on this server, not by the Hobnix project. Its releases are signed with the key that repository was added with, and the signature is checked; the Hobnix project has not looked at it.`
    : trust === 'unsigned' ? `It comes from the repository ${repo}, which has no signatures: nobody vouches that these are the files its author published. Installing it asks you to type its name.`
    : '');
</script>

<PageHeader title={name} sub={p?.title || s.title || ''}>
  {#snippet actions()}
    {#if p}
      {#each acts as a (a.id)}
        <Button need={needOf(a.id)} variant={a.primary ? 'primary' : 'secondary'} icon={a.icon} disabled={!!a.reason} reason={a.reason}
                busy={busyOf(a.id, p)} onclick={() => runAction(a.id, p, open)}>{a.label}</Button>
      {/each}
      {#if more.length}<Menu label="More actions for {name}" items={more} />{/if}
    {/if}
  {/snippet}
</PageHeader>

<PageState loading={!market.loaded} error={market.error?.message} hasData={market.data != null} empty={market.loaded && !market.error && !p} retry={() => refresh(paths())}
           emptyIcon="storefront" emptyTitle="No such package" emptyText={`No repository offers ${name} as ${repo}. It may have been taken out, or the repository was removed.`}>
  {#snippet emptyAction()}<Button variant="primary" icon="arrow-left" onclick={() => go(P.marketplace)}>Back to the Marketplace</Button>{/snippet}
  {#if p}
    <Stack gap="4" style="margin-top:12px">
      <Card>
        <Row gap="4" align="start" wrap>
          <AppIcon icon={p.icon} src={p.src} on={p.installed} size="lg" label="Icon of {name}" />
          <Stack gap="2" style="flex:1;min-width:200px">
            <Row gap="2" wrap>
              <Chip>{kindLabel(p.kind)}</Chip>
              {#if p.category}<Chip>{categoryLabel(p.category)}</Chip>{/if}
              {#if trust}<Chip kind="trust" level={trust} title={`From the repository ${repo}`} />{/if}
            </Row>
            <span>{stateLine(p)}</span>
            {#if failure}<ErrorNote error={failure.error} ondismiss={() => rowstate.dismiss(failure.id)} />{/if}
          </Stack>
        </Row>
      </Card>

      <Card title="Who vouches for it">
        <Row gap="2" wrap>
          {#if trust}<Chip kind="trust" level={trust} />{/if}
          <b>{testedText(p.verified, trust)}</b>
        </Row>
        {#if vouch}<p style="margin:0;line-height:1.55">{vouch}</p>{/if}
        <Muted as="p">Tested means (the official repository only): a person installed this release on a real Hobnix server (not only in an automatic test), opened it, checked that it does its main job, and then wrote the day into the index of its repository. It does not cover every setting or every kind of hardware, a later release, or an update of the app itself. Packages run as root on this server.</Muted>
      </Card>

      {#if compared}
        <Card title="On this server">
          {#if fit}
            <Row gap="2" wrap><Chip kind="fit" level={fit.verdict}>{fitLabel(fit)}</Chip></Row>
            <Stack gap="2">
              {#each fit.checks as c, i (i)}
                <Row gap="2" align="start">
                  <Icon name={FIT_ICON[c.level]} label={FIT_WORD[c.level]} />
                  <span style="min-width:0;flex:1;line-height:1.45;overflow-wrap:anywhere">{fitText(c)}</span>
                </Row>
              {/each}
            </Stack>
            <Muted as="p">The figures are what the package says of itself, compared with this server as it is now, for this app alone. They do not promise that the install works.</Muted>
          {:else}
            <Muted as="p">{!fitList.loaded ? 'Comparing with this server…' : `Whether it fits this server could not be checked${fitList.error?.message ? `: ${fitList.error.message}` : '.'}`}</Muted>
          {/if}
        </Card>
      {/if}

      {#if unread}
        <Banner tone="warn">The details of this release could not be read{s.reason ? `: ${s.reason}` : show.error?.message ? `: ${show.error.message}` : ''}.</Banner>
      {/if}

      {#if shots.length}
        <Card title="Pictures"><Screenshots shots={shots} label="Pictures of {name}" /></Card>
      {/if}

      <Grid min="300" gap="4">
        <Card title="What it is">
          {#if s.description}<p style="margin:0;line-height:1.55;overflow-wrap:anywhere">{s.description}</p>
          {:else}<Muted as="p">{!show.loaded ? 'Reading the release…' : unread ? 'Could not be read.' : 'The package says nothing more about itself.'}</Muted>{/if}
          {#if s.upstream}<Muted as="p">Made by its own project: <a href={s.upstream} target="_blank" rel="noopener noreferrer nofollow">{s.upstream}</a></Muted>{/if}
        </Card>
        <Card title="What it needs and uses">
          {#if uses.length}<Kv items={uses} cols={1} />
          {:else}<Muted as="p">{!show.loaded ? 'Reading the release…' : unread ? 'Could not be read.' : 'The package states nothing.'}</Muted>{/if}
        </Card>
        <Card title="Version and source">
          <Kv items={source} cols={1} />
        </Card>
      </Grid>

      <Card title="Versions">
        {#if !historyList.loaded}
          <Muted as="p">Reading the version list…</Muted>
        {:else if history.source === 'none'}
          <Muted as="p">This repository has no signed index, so there is no version list here.</Muted>
        {:else if !history.versions.length}
          <Muted as="p">The version list could not be read{historyList.error?.message ? `: ${historyList.error.message}` : '.'}</Muted>
        {:else}
          <Stack gap="4">
            {#each history.versions as v (v.version)}
              <Stack gap="1">
                <Row gap="2" wrap>
                  <b>{v.version}</b>
                  <Muted>{v.date ? `first published ${v.date}` : 'no date given'}</Muted>
                  {#if v.current}<Chip>Newest</Chip>{/if}
                  {#if p.installed && p.inst === v.version}<Chip kind="status" state="ok">Installed</Chip>{/if}
                  {#if v.withdrawn}<Chip kind="status" state="bad">Withdrawn</Chip>{/if}
                </Row>
                {#if v.withdrawn}<span style="line-height:1.45;overflow-wrap:anywhere">{v.reason ? `Withdrawn by its repository: ${v.reason}` : 'Withdrawn by its repository, which gives no reason.'}</span>{/if}
                {#if v.changes}<span style="line-height:1.45;overflow-wrap:anywhere">{v.changes}</span>
                {:else}<Muted>No change text.</Muted>{/if}
              </Stack>
            {/each}
          </Stack>
          <Muted as="p">{history.versions.length === 1 ? 'The index of the repository lists no older version.' : 'These are the versions the index of the repository lists: the newest and at most 10 older ones.'} That need not be every version ever published. An older version cannot be installed from this page.</Muted>
        {/if}
      </Card>
    </Stack>
  {/if}
</PageState>
