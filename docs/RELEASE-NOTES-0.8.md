# Hobnix 0.8.0 release notes (draft)

Draft for the release "0.8 Extensions and Access", built from the changelog entries of `docs/changelog/` that are on `0.8` but not in `v0.7.0` (21) and the
issues of the milestone. Written 2026-11-20. The same text is the body of the release pull request and of the GitHub release; the first
beta is [v0.8.0-beta.1](https://github.com/hobnix/server/releases/tag/v0.8.0-beta.1) (a pre-release).

**Read this first.** 0.8.0 is about who may do what: extensions get a protocol, a supervised service and limits, and the web interface gets three roles
and API tokens. **Nothing in 0.8 has run on real hardware yet.** Everything was written and tested with fakes, fixtures and the test suite, and CI is green on `0.8`;
items marked **Not tested on hardware yet** have not been tried on a real server. Roles, tokens and confinement are about access: do not rely on them
to keep out a person you do not trust until they have been tried on a real server. Single sign-on and two-factor login are not in this release.

## What 0.8.0 is
Extensions that can run commands and services in a defined way, with permissions the server enforces where it can, and a web interface that follows the role of the signed-in person.

## Extensions
- **A command protocol and an SDK**: a package that says `protocol = [1]` in its `package.toml` (API level 10) has its commands run through the command
  protocol; the core prints the answer and stops a command that runs past its `timeout:` together with everything it started. `hs pkg new <name> --template extension --protocol shell|python` starts one; the
  new guide Extensions shows the shell and Python helpers and a Go example. Existing packages are unchanged. Not tested on hardware yet.
- **`[service]` extensions**: an extension with a `[service]` table runs as one supervised process. `hs ext status` shows its state, `hs ext start` and
  `hs ext stop` control it, and a service that fails five times in ten minutes is given up with an `ext.service-failed` event. Services get events,
  emit events and publish snapshots. Not tested on hardware yet.
- **Events declared by packages**: `hs event kinds [--package NAME]` lists the event kinds of the core and of installed packages; packages declare
  theirs in `package.toml` (the old core list of package kinds works until the recipes have moved). Recipes declare theirs too.
- **A new guide**: Extensions (commands, services, permissions, events); the Web interface guide covers the three roles and API tokens.

## Permissions and confinement
- **Packages should declare `permissions`** in their `package.toml`. A package without them fails the check of its repository; on a server `hs pkg install`
  and `hs ext enable` still work but warn that a later release will refuse it.
- **An extension can only emit the event kinds it declares** (`events.emit`); other kinds are dropped and warned about once per kind. Extensions without a
  permissions list behave as before.
- **Services run confined**: a service can write only where its permissions say. A command can opt in with the flag `confine` (run through
  `systemd-run` with limits from the permissions); this is partial: reading files, the network and calls to `hs`, `incus` and `systemctl` are not limited, and commands without the flag still run as root. The install and update prompts say so.
- **The deny list** (security fix #947): a confined service sees `/var/lib/hs` as an empty folder with only its own state bound back, and `/root`,
  `/etc/shadow`, `/etc/ssh` and `/etc/nixos` are inaccessible. A package whose `fs.read` or `fs.write` overlaps these places, or whose `fs.write` points below `/etc`, `/boot` or
  `/nix`, is refused with the reason. A service still runs as root and its network is not limited. Not tested on hardware yet.

## Roles and API tokens
- **Three roles, viewer < app manager < admin** (ADR 0012, `docs/adr/0012-roles-and-api-tokens.md`): people in the domain group `hn-viewers` can look, `hn-app-managers` can also
  change instances and apps, Domain Admins can do everything. Create the groups with `hs group roles`. A call a role may not make is refused with a 403.
  The local admin account is still an admin. The audit log names the signed-in person for changes made in the web interface.
- **Role-aware pages**: every page is listed for every role; the ones a role may not open (the Vault and the Identity pages) are greyed with a lock and
  the reason; a button the role may not use is greyed with a tooltip naming the role it needs. Under Settings, Users and access, a role below admin
  sees its own sessions only. Extensions can say which role (viewer, app-manager or admin) may use each web read and change; without one they stay admin-only, and `hs pkg validate` refuses an unknown role.
- **API tokens**: `hs token create|list|revoke`; `curl -H "Authorization: Bearer hn_..."` acts as the role of the person who made the token, never more.
- **Security fixes #944 to #947**:
  - #944: a token starts changes only for containers, backups, shares, Docker, apps, jobs, notifications, health, expiry and ISOs; SSH keys, packages, settings, system updates, routes, network, domain, nodes and migration are refused, so a token cannot start a change that outlives it.
  - #945: a signed-in domain session is checked against the groups at least once an hour, like a token: a disabled person is signed out, a lowered role applies.
  - #946: a viewer can no longer list file names or search backups (see "Known limits").
  - #947: extension confinement and the deny list (above).

## Also in this release
- `hs docker gpu on|off` passes an Intel or AMD graphics chip into the Docker container for hardware transcoding (NVIDIA is not covered).
- Apply of a Docker app whose images are not downloaded yet runs as a background job instead of failing with exit 127.

## Upgrading from 0.7
- **Extension state moves to `/var/lib/hs/<package>`.** A confined extension sees only its own folder there. An extension that kept files elsewhere in `/var/lib/hs` must move them; its permissions are refused if they overlap the deny list.
- **The games extension changes in 1.0.x** (hobnix/extensions#17, merged): it keeps its state in `/var/lib/hs/games`, not in all of `/var/lib/hs`. Update it with `hs pkg update`.
- Domain installs: run `hs group roles` to create the three groups and put people in them. Without groups only Domain Admins and the local admin sign in as before.
- Third-party packages without `permissions` keep working and warn; add them now.

## Known limits
- **No single sign-on and no two-factor login.** TOTP and OIDC (steps 19 and 20 of PLAN-extensions-access) are not in 0.8.
- **A viewer cannot list files or search backups** (ADR 0012, #946): the file manager (places, listings, sizes, details) and the backup file search need the admin role, because they show file names of every share. A viewer sees the file manager greyed with its reason.
- **Confinement is partial**: command confinement is opt-in and limits only writes; services still run as root with an open network.
- **#943**: the test `tests/pool-bare` lists `data-91` and `data-92` in the remove menu on a WSL host. A test problem on WSL, not seen on a server.
- Apps that update themselves and importing a Docker Compose file are still not in (see the 0.6 notes).

## What was tested on real hardware
**Nothing in 0.8 has run on hardware yet.** The test suite, the schema and changelog checks and CI are green on `0.8`; no real server, domain controller or
disk was involved. Not tested on hardware yet, and still open as hardware test rows:
- **`ad-selfservice` as a `[service]` extension** with a real domain: it still changes a real domain password.
- **Roles and tokens on a real server**: three real domain users in the three groups sign in and see what their role sees; a viewer's POST gets 403; a token from a script works, expires and stops when the person is disabled in AD; domain controller down.
- **A boot-time service**: a service starts at boot, is restarted after `kill -9`, and `hs ext stop` survives a reboot.
- **Confinement on NixOS**: a confined service cannot write outside its paths (systemd properties depend on the version); `incus` from a confined command fails as declared.
- **`t vm` on Incus**: the units of services and confinement in the nested VM (ADR 0023).

## Not verified
- Every item marked "Not tested on hardware yet" and every row above.
- The web interface of `v0.8.0-beta.1` has not been looked at by the owner.
- Whether a role lowered in the domain reaches a session and a token within the hour on a real domain.
