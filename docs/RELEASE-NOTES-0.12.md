# Hobnix 0.12.0 release notes

Draft release notes of the release "0.12 Package Pages", built from the changelog entries of `docs/changelog/` that are on `develop` but not in
`v0.11.0`, from the plan `docs/PLAN-package-pages.md`, from `docs/errors.md`, `docs/extensions-sdk.md` and ADR 0028, and from the closed issues of
milestone 0.12. Written 2026-11-23 for the beta `v0.12.0-beta.1`.

**Read this first.** Nothing in 0.12 has run on a real server. The Svelte frontend was only compiled by CI and was never viewed in a browser. The
beta exists to test it. Every item below is built and covered by the tests of the repository. Not tested on hardware yet. The tracker issue
"Hardware test: 0.12" lists the boxes to check on a server. A box that is not ticked is postponed, it never blocks the release.

## What 0.12 is
Packages (recipes and extensions) place their own pages in the interface. A package says in its manifest where its page sits, which blocks it
shows, which actions and health checks it adds and which other packages it talks to. Refused and failed changes carry a stable error code. The
event log is pruned by class. Confined extension services get their keys and rollups through systemd credentials and a service message.

## Package pages
- **Placement:** `[web.page]` names the group (default Apps), tabs, a page shape (`template`: list, object or feed), a card (`state`) and a `role`
  for the page and its buttons. The places of the core keep their order, package places follow alphabetically, `after` puts one behind a place.
  There is no separate Extensions group any more. An unknown group, or a read the package did not declare, is ignored. A button whose `role` is
  above yours is disabled with the reason.
- **Card:** a package that declares `state` gets one dot and one line on the group page and on Apps.
- **Recipe page:** a recipe with a page in its manifest gets an Open button in Apps > Installed, with status blocks and the few actions it declares.
- **Blocks** are a registered list with a schema and a version each: `table`, `kv`, `cards`, `text`, `empty`, `gallery`, `chart`, `stat`, `log`,
  `progress` and `form`. `hs pkg validate` checks the blocks of `[web.page]` against the registry; the Components gallery lists them; a block
  this version does not know shows a note, not a broken page.
  - `chart`: a series over time from a declared read. `stat`: tiles with a value, a unit and a state dot.
  - `log`: the last lines of a log that follows the server log stream. `progress`: a bar fed by a read or a job.
  - `form`: fields (text, number, toggle, select, secret) with checks as data. Submitting opens the plan dialog of the package's own area, so
    nothing changes without the person starting it. A secret field goes on stdin only and is never shown back. Validation refuses an unknown field
    type, a plan of another area and a secret field without an stdin mapping.
- **Install dialog:** the review step says "The server is rebuilt." only when the plan has a rebuild (fix, #850).

## Slots
A package may add to fixed places only: page, tab, action, health check, state card and `requires`. An unknown slot name is refused with the list of
known ones.
- **Action:** a button in the page header and on the Apps list; one main action, the others under More.
- **Health check:** shows in System > Health with the package named. A check may report **information** that is not a problem (a gaming PC that is
  switched off): these lines sit under "For your information", are not counted in the badge and send no message.
- **requires:** a part of a package that needs something switched off shows nothing until it is on; the install dialog says so.

## Settings
Settings > Capabilities (optional parts) and the new Settings > Extensions are two lists in the style of Instances and Shares: name, state, what it
is, and the switch, which still opens the plan first. The old address `/settings/capabilities#extensions` goes to the new page.
The Instances, Shares and Users lists have row buttons instead of a quick look (Open instance, Browse files and Open share, Edit, Change password
and Open user).

## Error codes
A plan or start that is refused or breaks names what went wrong with a short stable code (for example `vault.locked`, `run.timeout`) next to the
English text. The web shows the code, what happened, the likely reason, one next step and a link to `docs/errors.md`. A code the web does not know
still shows the English text. Design: ADR 0028; the rule for new messages is in `docs/CLI-DESIGN.md`. Only the errors met most often carry a code
(see "Known gaps").

## Integrations
- A package says what it offers to others in `[integrations.<name>]` (a local API address and a key file). `hs pkg integrations` lists them with
  the state of each key file and the header the key goes in (`key_header`, last column); the key itself is never printed.
- `api_url` may contain `{port}`, filled from the service record of the app (LXC or docker mode). Without a known port the address shows `-` and a
  warning says so; nothing is guessed. `hs pkg validate` accepts `{host}` and `{port}` and refuses any other placeholder.
- An extension that needs a key declares the permission `integration:<name>` and names the app: `integration_key media radarr my-ext`. The old
  two-argument call still works for one release.
- Removing an app lists the key file it handed out in the plan and deletes it with the app.

## Events
A package names a retention class (`ephemeral`, `audit` or `metric`) for each event it declares in `package.toml`; the core prunes the event log by
class. Extensions can keep monthly rollups per user and kind instead of raw ticks. A declaration without a class counts as `audit`.

## Confined extension services
A confined service could not reach the server state, so it could not read an integration key or add a rollup. The core now starts the service in its
own transient unit while the supervisor stays outside it.
- Keys reach the service as systemd credentials, one per app that offers a declared integration, named `integration-<name>-<app>` (for example
  `integration-media-radarr`). The SDKs read them with `credential(name, provider)` (Python) and `credential_for(name, provider)` (Rust).
- Rollups of declared metric events go through a new service message.

## Rust SDK and compiled programs
- The Rust extension SDK calls the JSON API of an integration over plain http (no extra libraries, static binary) and reads the integration list as
  typed rows. https is not supported.
- `[[binary]]` in `package.toml` declares a compiled program with its sha256. Install and update check the hash and refuse a mismatch, keeping the
  old version. A server that is not x86_64 says so before installing.

## Pilot extensions
`games`, `game-lobbies` (#924, first slice) and `media-hub` (#928, first slice) in hobnix/extensions are the first users of these slots and
integrations. They are first slices, not finished products.

## Security notes
- Extension services still run as uid 0 inside their unit: hobnix/core#1134.
- Permission enforcement for extensions is not built: #239.
- The vault and credential path was reviewed four times and has never run under real systemd.

## For developers
- New and changed commands: `hs pkg integrations`; `hs pkg validate` knows the block registry, `{host}` and `{port}` and `[[binary]]`. Rows are in
  `scripts/lib/registry.tsv`.
- The block registry is the component list: add a block there with its schema and version, not as a one-off in a page.
- Error codes: a new refusal or failure gets a code in the catalogue and a row in `docs/errors.md` (ADR 0028). Generated docs stay generated
  (`python3 scripts/events-doc-gen.py write`, `python3 scripts/openapi-gen.py write`, `python3 scripts/openapi-ts-gen.py write`).
- Extension SDK details: `docs/extensions-sdk.md`.

## Not tested yet
The whole release on hardware: Not tested on hardware yet. In particular:
- Real systemd: `LoadCredential` for keys, `MountFlags=private` and the propagation of the vault mount into the unit.
- The Jellyfin and Plex adapters against real servers.
- https for the Rust client (unsupported); the install-time hash check of `[[binary]]` on a real install.
- Not seen in a browser by anybody: every new page, block, list and the error display; the keyboard and screen reader pass and the phone layout.

## Known gaps
- `game-lobbies` (#924) and `media-hub` (#928) are first slices.
- PTY and RCON blocks, package secrets and extension actions as jobs are 0.14 (#1123 to #1126).
- The long tail of error codes is open: #1127.
- Rollback does not re-hash the previous copy of a program.
