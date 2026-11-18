# Hobnix 0.5.0 release notes (draft)

Draft for the release "0.5 Capabilities Repository", built from the commits (without merges) that are on `0.5` but not in `v0.4.0`, the 9 changelog entries
of `docs/changelog/` since then and the issues of the milestone. Written 2026-11-18. Re-read before the tag. The same text is the body of the release
pull request and of the GitHub release.

**Read this first.** 0.5.0 lets optional parts of the server come from their own repository (hobnix/capabilities) instead of the core. Nothing in
the core moved yet: the first optional parts are installed from that repository by hand or in the first-run wizard. In a virtual machine on the real
test-lab server the stages install, smoke check, rollback, backup and restore, pool and the upgrade from v0.4.0 passed on the tip of `0.5`
(2026-11-18). Stage 6 (browser) never ran there (no playwright on the server). The first run of stage 5 failed once because the server had no
internet for a while (a name lookup of cache.nixos.org); it passed on the rerun without a change. Items marked **UNVERIFIED** were written and tested
only with fakes, fixtures and unit tests. The owner then updated the real server to v0.5.0-beta.2 and looked at the web interface (2026-11-18):
every page opens and works, the pools still show the classic `bulk` and `fast`, Settings > Capabilities lists the built-in parts, and the language
switch and forms work. No capability package exists in the repository yet, so nothing of the package machinery could be tried on that server
(`hs pkg list --kind capability` says "No packages"). Do not trust this release with the only copy of your data.

**Found on the real server:** updating to v0.5.0-beta.1 stopped with "games is neither a part of the core nor an installed package. Nothing was built".
The server still had the removed extension `games` switched on; the new rebuild pre-check treated it as a blocker although the build ignores such a
name (hobnix/server#829). Beta 2 only warns about it and goes on; `hs ext disable <name>` now also removes such a leftover name.

## What 0.5.0 is
Optional parts (a third package kind, `capability`) that live in hobnix/capabilities, are fetched with `hs pkg`, copied into the checkout and
built by `hs rebuild`, and whose options you set like the built-in ones.

## Capability packages
- **A third package kind** (#225): `hs pkg list --kind capability`. A package that needs a newer Nix interface level than the server has
  (`capabilities/nix-api-level`) is refused at install (#221). A capability from a default repository may own its name as a command word
  (`hs <name> ...`) as long as no core command uses it.
- **Vendored Nix code** (#221): the module of a package is copied into `vendor/` of the checkout with a lock of its hashes (default repositories
  only), so the build stays pure (no `--impure`). `hs rebuild` checks before building that the package is in place and matches its lock; the check is
  skipped when `pkg.py` is not beside the script.
- **Roll back a package update**: when the rebuild fails after `hs pkg update`, `hs rebuild` offers to put the previous release and its lock line
  back (you type the package name); without a terminal it prints `hs pkg rollback <name>`. UNVERIFIED on a real server.
- **A release that needs a newer core waits**: `hs pkg updates` and the Marketplace show it as `waits`; `hs update` stops before the rebuild and
  names the package when an installed package does not suit the new core.

## Options and settings
- **`hs config` knows the options of installed capability packages** (#224): `list`, `set`, `check` and `sync` (their own section of machine.toml).
  Removing a package leaves its lines in place; `hs config check` shows "unused, capability X removed" as a note, never an error.
- **Settings pages** show the options of an installed capability under Settings > Capabilities (and Advanced) without a rebuild; settable ones can be
  changed there. UNVERIFIED in a browser.
- **First setup** (#229, #177): the first-run wizard and `hs first-run` offer optional parts from the signed repositories and install, switch on and
  rebuild them in one job. UNVERIFIED on hardware.
- **Backup**: `hs backup config` and its restore include `/etc/nixos/vendor` and the lock; with `--from-disk` the installed package copies come back, so
  a rebuild on a fresh install does not need GitHub.

## Docs and release process
- Guides for installing, switching on, updating, rolling back and removing an optional part (Operations; Containers and apps names the kind).
- CI fetches hobnix/capabilities and has a build matrix for them with a test fixture (#228); the release flow works for package repositories, with
  review fixes (a missing label lookup fails loudly, the gate sha is checked, no tag needs `--version`). Package versions are raised by the release
  (#615, open).

## Fixes carried from the 0.4 test runs
The installer asks no admin-name question in an unattended run; the lab creates the pool fast with `--use apps` and the SnapRAID pool with
`--use data --kind snapraid`, and stage 5 runs the rebuild after it; `hs rebuild` does not compare `bulkType` with the installed layout when
machine.toml has a `pools` line. The DCO check exempts the `agent-pr` label.

## Not in this release
- Moving the existing optional parts out of the core (only a pilot and the machinery are here); capability uninstall and version compatibility
  beyond the checks above (#235); packages' versions bumped by labels (#615).
- Live state on by default (see the 0.3 notes).

## Not verified
- Installing, rolling back and removing a capability on a real server (none exists yet); the wizard step; the settings pages of an installed package.
- The headless browser stage (6) never ran.
- The unlock page of this version.
