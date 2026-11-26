# Plan: Apps & VMs, and finding your way (milestone 0.13)

Status: designed 2026-11-25 from the owner's feedback on 0.12. Nothing here has run on a server. Not tested on hardware yet.

Issues: #1292 (breadcrumbs), #1293 (tree), #1295 (Docker app page), #1296 (one list), #1294 (data loading).
Builds on [PLAN-navigation.md](PLAN-navigation.md) and replaces two of its decisions: D2 (Instances and Apps as two groups) and, for Docker
apps, the note that they get no page yet.

## 1. Breadcrumbs (#1292)

Today every page passes its own `crumb` string to `PageHeader`. The strings use four separators and several name groups that are gone.

- The trail is **derived** from the tree: one function in `web/src/nav.js` returns `[{ label, path }]` for an inner path: the server, the groups,
  the lists and, on an object page, everything above the object. A page that has no place in the tree (`offTree`) gets the server and nothing
  more. A page of a remote node uses that node's name and tree.
- A new component `web/src/ui/Breadcrumbs.svelte` draws it: `<nav aria-label="Breadcrumb">` with an ordered list, every part a real link
  (middle click works). It shows the **parents** only; the title under it names the page. The pinned UI SDK has no breadcrumb part.
- `PageHeader` shows the derived trail by itself. The `crumb` strings are removed from the pages. The headings inside Docs and the path bar of
  the file manager are not breadcrumbs of the interface and stay.

## 2. The tree shows where you are (#1293)

| Row | Look |
| --- | --- |
| The open page | full highlight (as today), `aria-current="page"` |
| Its parent | accent icon and a faint accent tint |
| Every row above that | accent icon only |

Three tints were rejected: the weakest would not be visible, and it would look like hover.

- An object page (disk, share, user, instance, Docker app) adds a **temporary row** under its list, with the object's name and a full highlight.
  Its list row becomes the parent. The row goes away when the page is left. Tabs get no rows; a quick look gets none.
- Pools keep their permanent rows. A long name is cut with an ellipsis and has a tooltip.

## 3. Apps & VMs (#1295, #1296)

### What the data is

| Thing | Read today | Note |
| --- | --- | --- |
| Containers and VMs | `sys ct list` | Incus. `owner` marks a locked system instance. |
| Docker apps | `sys docker apps` | Compose projects, and containers started by hand (`unmanaged`). All of them run in the one locked container `docker`: `parent` is always `docker`. Docker inside another instance is not listed. No row while Docker is off or the container is stopped. |
| App catalog | `sys recipes list` | What can be installed and which instances it set up. One recipe sets up one instance, except `pelican` (two) and `matrix-hook` (none). An app that runs in Docker reports the instance `docker`. |

### The list

One page, **Apps & VMs**, at `/apps`. It replaces the pages Instances and Docker.

- Columns: Name, **Provider** (Incus, Docker), **Type** (Container, Virtual machine), State, App, Address (Docker: address and ports),
  then the optional instance columns of today (starts at boot, RAM, CPU, last snapshot, route), empty for a Docker app. A Docker app shows its
  running count with the state (`2/3`) and keeps the chips of today (changed files, unmanaged, failed).
- Above the table: **Provider** (All, Incus, Docker), **Type** (All, Containers, Virtual machines) and a **search** field over name, app,
  address and image. All three are in the address (`?provider=docker&type=vm&q=photo`), so Back and a copied link keep them. The provider filter
  shows only while the `docker` capability is on.
- **One level of nesting: what runs inside what.** The row `docker` (Incus, Container, locked) holds every Docker app under it. It is open at
  first, can be closed, and stays as left for the session. When a filter or the search matches a Docker app but not `docker`, the `docker` row
  stays as a dimmed context row, and a closed row opens. Sorting orders the top level and, separately, the children. While the container is
  stopped the row says that its apps show once it runs.
- **No grouping by app.** An earlier proposal grouped the instances of one app; only one recipe sets up two, so the column App (sortable,
  searchable) does the job. The App column is filled from `recipes list`: for an instance by the instance names of a recipe; for a Docker app
  managed by a recipe, by the recipe of the same name. A second copy under another name shows `-`: no read ties the two, and the shape of
  existing `sys` lines does not change.
- Actions keep today's plans. At most three buttons are visible on a row; the rest are in a menu. Header: **Create** (primary), **New Docker
  app**, and a menu with Guided Docker app and Update all. The Docker banners ("not complete", "Docker is off") move here.

### Object pages

| Kind | Address | Tabs |
| --- | --- | --- |
| Instance (container or VM) | `/apps/instance/<name>[/<tab>]` | Overview, Config, Network, Console (unchanged) |
| Docker app | `/apps/docker-app/<name>[/<tab>]` | Overview, Compose, Logs (unmanaged: Overview only) |

The kind is in the address because an instance and a Docker app may have the same name. The system container `docker` is an instance page. An
instance or Docker app that a recipe set up links to its row in the app catalog. Update, services and remove stay in the catalog in this step;
they move to the object page with #478.

### The tree

```
Apps & VMs            /apps            the list
  App catalog         /apps/installed  today's "Installed" page, renamed
  Marketplace
  Docker registries   (capability docker)
  ISO images          /apps/iso        (capability incus)
```

Network > Services stays where it is. A remote server keeps its read-only entry "Instances" (PLAN-navigation D8).

The catalog is the only place that installs an app, so it stays until the Marketplace takes that over (#474). #474 and #478 are to be built on
this structure.

### Old addresses

Rows in `web/src/redirects.js`:

| Old | New |
| --- | --- |
| `/instances` | `/apps` |
| `/instances/ct/<name>[/<tab>]` | `/apps/instance/<name>[/<tab>]` |
| `/instances/iso` | `/apps/iso` |
| `/apps/docker` | `/apps?provider=docker` |
| `/apps/docker/app/<name>` | `/apps/docker-app/<name>/compose` |

`/apps/docker/new`, `/apps/docker/wizard` and `/apps/docker/registries` keep their addresses. The older paths that the table already holds
point at the new places.

## 4. Data loads before it is needed (#1294)

The server-aware fields (share, disk, pool, instance, user) read on first use. `shares principals` is in no early load, and a second request
for a read that is still running starts another one.

- Right after unlock the reads of these fields are requested **first and in parallel**, only those the role may read. The existing idle loading
  of page data follows as today.
- The data layer keeps one running request per address and lets later callers join it. A forced refresh (`fresh`) never joins an older one.

This is browser work. The plan for 0.15 ([PLAN-core-daemon.md](PLAN-core-daemon.md)) does not cover it: the new web server comes in a later
step. The cause of the slow pickers has not been measured on a server.

## Steps

| Step | Issue | Content | Needs | Wave |
| --- | --- | --- | --- | --- |
| 1 | #1292, #1293 | trail function, Breadcrumbs, PageHeader, tree marks and temporary row | - | 1 |
| 2 | #1294 | early reads and shared requests | - | 1 |
| 3 | #1295 | object kind `docker-app` and its page | - | 1 |
| 4 | #1296 | the list, the new tree group, redirects | 1, 3 | 2 |
| 5 | - | release notes, `develop` into `0.13`, beta tag | 1 to 4 | 3 |

Every step: a pull request into `develop` with tests, a changelog entry for what a user sees, a look in the demo (`npm run demo` in `web/`) at
desktop and phone width, and its hardware test steps. No step adds or changes a `sys` row.
