# Hobnix 0.13.0 release notes

Draft release notes of the release "0.13 Package Registry", built from the entries of `docs/changelog/` dated 2026-11-24 and 2026-11-25
(plus the remote-share entries of the same days) and from the closed issues of milestone 0.13. Written 2026-11-25 for the beta `v0.13.0-beta.1`.

**Read this first.** Nothing in 0.13 has run on a real server, and the new web screens were only compiled by CI, never viewed in a browser. The beta
exists to test it. Not tested on hardware yet. The tracker issue [Hardware test: 0.13](https://github.com/hobnix/core/issues/1137) lists the boxes to
check on a server; an unticked box is postponed and never blocks the release. What changes for you as a server owner:

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
  that list yet.
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
  Keys and rollups work again for extension services (fix).
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
The whole release. In particular: the repository migration on a real v0.12 server, the move of extension state and the backup and restore of
`/var/lib/hs-ext`, services under the unprivileged user, `hs docker migrate`, the installer and first-run choice, `hs blueprint apply`, remote share
pairing between two servers, and everything in a browser (permission dialog, wizard step, Shares views, forms). Tracker:
[#1137](https://github.com/hobnix/core/issues/1137).

## Known limits
- One blueprint, `minimal`. Not every refusal has an error code yet (#1127), and the web does not show the German texts.
- Version history in the index cannot be used to go back yet.
- Packages that official does not list get no updates.

## Not in 0.13
- Blueprints `edge` and `example-server`; the web read of the setup choice.
- Pinning `:latest` images.
- A multi-step recipe SDK and the plan speed work: 0.14.
