# Hobnix 0.13.0 release notes

Release notes of "0.13 Package Registry", built from the entries of `docs/changelog/` dated 2026-11-24 to 2026-11-26 and from the closed
issues of milestone 0.13. Betas: `v0.13.0-beta.1` and `v0.13.0-beta.2`.

**Read this first.** The two betas ran on one real server, and only a small part of this release was checked there:

- **Seen:** installing and updating packages from the official index; the program of the Media Hub service running as an unprivileged user and
  restarting by itself when the address of an app changed; the owner found the web interface of beta.2 much faster.
- **Not tested on hardware yet:** everything else in these notes. The tracker issue [Hardware test: 0.13](https://github.com/hobnix/core/issues/1137)
  lists the boxes to check on a server. None of its boxes is ticked: what is listed as seen above covers parts of boxes, not a whole one. An
  unticked box is postponed and never blocks the release.

What changes for you as a server owner:

- **Packages come from one repository, `hobnix/official`, through a signed index** (`packages.hobnix.dev`). `hs pkg` checks the signature, refuses an
  older index than the one it has, takes the version of a package from the index (one version per package) and checks the files against the hash in
  the index before installing.
- **Blueprints** are a new kind of package: an ordered list of packages plus settings. The installer, `hs first-run` and the setup wizard ask what
  the server is for. Only the blueprint `minimal` exists in this release.
- **The web interface can accept the new permissions of a package update** (Marketplace, Update button). Not tested in a browser yet.
- **Extension services no longer run as root.** Each runs as its own unprivileged user and writes only its own folder. State moves from
  `/var/lib/hs/<name>` to `/var/lib/hs-ext/<name>` at the first start. The host backup includes `/var/lib/hs-ext`.
- **Refused changes carry an error code**, and the catalogue has a German text for every code. The web does not show the German texts yet.
- **Update from v0.12:** a v0.12 server keeps its old recipes and extensions repository rows until it runs `hs update`, which moves them to official.
  The first update may not refresh the index: the daily timer does that, so run `hs pkg refresh` if the index looks old.

## Changes since beta.1

### Less CPU use on an idle server

Beta.1 kept a server busy with nobody using it: about 6.6 of 8 cores were busy on the server where it was seen. With beta.2 the same server had
2.06 busy cores in an 8 minute sample, **with a web page open** (about 33 requests a minute). The two programs the fixes are about went from 4.93
to 1.38 cores (`hs-live` 2.85 to 1.01, `hs-web` 2.08 to 0.37). Not all of the drop of the total comes from the fixes: a container that used about
0.96 cores in the first sample was stopped during the second. A sample with every page closed was not taken. The behaviour with no page open,
described below, is therefore not tested on hardware yet.

- **Every `hs` command starts much faster.** Beta.1 built the command list with hundreds of programs on every call. Measured with the new code on
  a real server with 667 commands, without installing it: 0.12 CPU seconds instead of 2.79 for this one step
  ([#1331](https://github.com/hobnix/core/pull/1331)).
- **Status that only a page shows is read when a page is open.** With no page open it is read when something changes, and otherwise every 5 to
  10 minutes. A page that you open can show a value that old for a moment. Reads that can send an event or a notification keep their timing, and
  so does the health check. A read that starts to fail with no page open is noticed up to about 10 minutes later, so a warning about it can miss
  one health check.
- **A client with an API token** does not count as an open page: its answers can be about 10 minutes old. Add `?fresh=1` for a new read.
- The web server no longer reads in advance with nobody there, and the display status is read every 60 seconds instead of every 20.
- Live reads of packages are read on demand too. No package of the official or community repository declares one today.

### Apps that talk to each other

- **A service such as Media Hub gets the real address of an app** instead of `{host}`, so it can reach recipe apps
  ([#1327](https://github.com/hobnix/core/pull/1327)).
- **It follows the app:** when an app stops, restarts or gets another address, or has none yet at boot, the service restarts with the new rows.
  A stopped app can keep its old address for about 12 seconds. A change that Incus does not report is found within 30 minutes, later when a check
  fails; a failed check changes nothing. The address is what the app's container reports about itself
  ([#1344](https://github.com/hobnix/core/pull/1344)).

### Web interface

Design: [PLAN-workloads](PLAN-workloads.md). Before the beta these screens were seen only in the demo in a browser, and not every page. Which of
them were looked at on the real server was not recorded. Not tested on hardware yet.

- **Apps & VMs** is one list of containers, virtual machines and Docker apps. It replaces the pages Instances and Docker. It has the columns
  Provider (Incus, Docker) and Type (Container, Virtual machine), filters for both and a search. The system container `docker` holds the Docker apps
  under it. Today's page "Installed" is now **App catalog** and is still where apps are installed.
- **Every Docker app has its own page** with Overview, Compose (the editor) and Logs. The quick look of the Docker page is gone; delete is in the
  row menu and on the app page. The columns Images and Managed are on the app page.
- **Breadcrumbs are links** and come from the tree on the left. The tree marks the parents of the open page and shows a temporary row for an open
  disk, share, user, instance or Docker app.
- **Pickers fill sooner:** after unlock the lists behind the share, user, disk and instance fields are read first, and a read that is already
  running is not started again. The speed on a server was not measured.
- Fixed: after sign-out, a read that was still running can no longer show its answer to the next user.
- Old addresses of the Instances and Docker pages redirect to the new ones (kept until 0.15).

## What is new

### Package registry
- `hs update` fetches the index and runs `hs pkg repo migrate`: an installed package whose repository was replaced is recorded under the new one
  (same version, nothing reinstalled or downgraded). A package that official does not list stays installed but gets no updates. Repositories you
  added yourself are not touched. If the index host is down, the update still succeeds. `hs pkg repo migrate --dry-run` shows what would change.
- A repository is added with an index: `hs pkg repo add <name> <url> --key <allowed-signers-file> --index <address>`. Repositories without an
  index still work. A withdrawn version gets no update offer.
- `hs pkg refresh` and a daily timer fetch the index. A change makes the update count and the Marketplace read again. After three days without a
  fetch, or when the index has expired, `hs pkg list` and a banner in the web interface warn, and one push message goes out shortly before expiry.
  `hs sys pkg index` shows the state.
- Each package in the index has the date its current version came out and up to 10 older versions with commit and checksum. Nothing installs from
  that list yet. The versions appear once the index is rebuilt by the official release of 0.13.
- `hs pkg install` refuses a package whose commands clash with the core or another package, whose route points at an admin page or has an invalid
  name, exposure or port, or that has a start command without its plan command. The previous copy comes back or the new one goes. `hs pkg remove`
  names every package that needs the one you remove.
- Updating or rolling back a package restarts its running service; installing or removing a package that offers an integration restarts the
  services that use it. A service that is not running is left alone.
- `hs smoke` checks only what the switched-on parts need, and runs a check of a package only if it is a command of that package declared as reading
  (or a changing command that takes `--dry-run`); other checks are skipped with a warning and count as a failure.

### Blueprints and first run
- `hs blueprint list`, `show` and `apply`: a plan first (settings, parts, one rebuild, Docker, apps), then one background job. It only fills what
  is not set and never overwrites a value. A failed rebuild stops before the apps; a failed app does not stop the next one. `hs preset` stays for
  one release.
- `hs-install` records the choice (`--blueprint`, `--parts` or `--core-only`) and fetches nothing. `hs first-run` offers only the core, one blueprint
  or single parts; `--yes` never types a name for you. The web wizard has one step "What is this server for?".
- Docker has its own setting `docker`. `hs update` moves a server over with `hs docker migrate`: it sets `docker`, remembers Arcane or Portainer if
  one runs and touches no container. `hs docker migrate --undo` puts the old setting back.

### Extensions
- Services and confined commands run as an unprivileged user with more systemd hardening (no kernel settings, modules, clock, namespaces or odd
  system calls). Unix sockets, the network and declared permissions such as the GPU stay. A command that asks to write elsewhere is refused. If both
  the old and the new state folder exist, the service does not start and nothing is changed.
- Service extensions get their integrations (provider, API address, key header) in the init message; keys still come only as systemd credentials.
  Keys and monthly sums (rollups) work again for extension services (fix).
- Rust SDK: handlers take `&dyn Ctx`, and `hobnix_ext_sdk::testing::FakeCtx` runs a handler in a test. The job record writer handles `error`,
  `result` and `skip` in Rust.
- In 0.14 the crate `hobnix-ext-sdk` is replaced by the `hobnix-pkg` crates: a breaking change for extension authors. The old name re-exports them
  and is deprecated for one release. Crates pin the SDK by rev, so nothing breaks until a crate bumps its pin.

### Web and shares
- Marketplace update lists each new permission and asks for the package name. "Update selected" and automatic updates never accept new permissions.
- Shares has the views Local, Remote and Kept folders; remote shares moved from Network (`/network?tab=remote` still opens them).
- Remote shares pair with a code: `hs remote offer <share> --code`, `hs remote add --code`, `hs remote codes`. A code works once and at most an
  hour. The web has Give access, Add remote share, Reconnect and New code. Needs the program from the next rebuild.
- Forms offer a searchable list for a share, user, group or instance instead of typing its name.

### Security
- Portainer (docker:9000) and Arcane (docker:3552) can no longer be made public; a hand-made proxy route to them is imported as never-public.
- A package route with an invalid value could pass the admin-page check; it is now refused.

## Upgrade notes
- Run `hs update`; it migrates repositories and Docker. Afterwards `hs pkg repo migrate --dry-run` should list nothing.
- Anything that reads an extension's state at `/var/lib/hs/<name>` should use `/var/lib/hs-ext/<name>` (`$STATE_DIRECTORY`); the old path stays as a link
  for root tools.
- Extension authors: plan the 0.14 SDK rename.

## Not tested on hardware yet
Everything not named as seen in "Read this first". In particular: the repository migration of a v0.12 server checked step by step, the move of
extension state and the backup and restore of `/var/lib/hs-ext`, `hs docker migrate`, the installer and first-run choice, `hs blueprint apply`,
remote share pairing between two servers, a community or third-party repository, the installer ISO, and the new web screens one by one
(permission dialog, wizard step, Shares views, forms, Apps & VMs). Tracker: [#1137](https://github.com/hobnix/core/issues/1137).

## Known limits
- **Media Hub and Jellyfin 12:** Jellyfin 12 refuses the way Media Hub 0.2.0 sends its key, so no playbacks are counted. The fix is an
  update of the package in `hobnix/official`, independent of this release.
- **A service written with the Rust SDK** that writes from a thread of its own can write before the SDK says `ready`, and the start then fails
  ([#1353](https://github.com/hobnix/core/issues/1353), milestone 0.14).
- One blueprint, `minimal`. Not every refusal has an error code yet (#1127), and the web does not show the German texts.
- Version history in the index cannot be used to go back yet.
- Packages that official does not list get no updates.

## Not in 0.13
- Blueprints `edge` and `example-server`; the web read of the setup choice.
- Pinning `:latest` images.
- A multi-step recipe SDK and the plan speed work: 0.14.
- Moving the first capability (metrics) into the `capabilities/` folder of hobnix/official (#225, epic #217) is planned for 0.14; capabilities stay in
  the core for now.
