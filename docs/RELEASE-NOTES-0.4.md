# Hobnix 0.4.0 release notes (draft)

Draft for the release "0.4 Install and Onboarding", built from the commits (without merges) that are on `0.4` but not in `v0.3.0`, the 28 changelog entries
of `docs/changelog/` since then and the issues of the milestone. Written 2026-11-18. Re-read before the tag. The same text is the body of the release
pull request and of the GitHub release.

**Read this first.** 0.4.0 changes how a new server is set up and how storage is named: a freshly installed home server has **no fixed pool names any
more** (no `bulk` and `fast`); you name the pools yourself. In a virtual machine on the real test-lab server the stages install, smoke check,
rollback, backup and restore, pool and the upgrade from v0.3.0 passed on the tip of `0.4` (2026-11-18). Stage 6 (browser) never ran there (no
playwright on the server). Nothing of this release was run on physical hardware, and nobody has looked at the web interface of this version.
Items marked **UNVERIFIED** were written and tested only with fakes, fixtures and unit tests. An update from 0.3 keeps its pools: a server without a
`pools` line keeps its classic rows (`hs pool record` writes the line from what the server has). Do not trust this release with the only copy of your data.

## What 0.4.0 is
A server that is not the author's: install without a domain controller, name the admin account, name your pools, a first-run wizard in the browser.

## Install and first setup
- **First setup in the browser** (#183): the installed system shows its web address and a one-time code on the console; the wizard asks for the
  account, the network (#179, checked before the disk step), the storage (create a pool on empty disks or import a ZFS pool that is on the disks),
  a preset and optional parts. UNVERIFIED on hardware.
- **Installer**: the name of the admin account is a choice (`--admin`, setting `adminUser`, #575); `--confirm-disk` on the command line means an
  unattended run (no question). A new home server starts with `pools = {}` and names its pools itself (#576). The one-time setup code is shown after
  the clock is set. A vault partition is left on the disk.
- **`hs sys storage discover`** lists what is on your disks (read-only, #181).

## Pools
- **Any number of pools with any name and a role** (#573): `hs pool <name> --use data|apps [--kind snapraid]`; `hs pool record` writes the `pools`
  line from the pools the server already has; `hs pool <pool> import` brings in a ZFS pool that is on the disks; a new pool is made on empty
  disks only. Shares (`hs share add --pool`), the file manager, instances (fast volumes go on an apps pool, `-s` chooses) and the storage incident
  guide follow the pools of machine.toml. A server without a pool says so and refuses shares.
- **Web**: pools, disks, shares, files, navigation and the health page read the pool list of the server.
- **Fix**: `hs rebuild` no longer compares `bulkType` with the installed layout when machine.toml has a `pools` line.

## Users
- **Users and groups without a domain controller** (#575): local users and groups for Samba. UNVERIFIED on a real server.

## Test-lab
Everything the 0.3 notes say, plus the fixes the 0.4 run needed: an installer that asks no question in an unattended run, the pool fast created
with `--use apps`, and stage 5 running the rebuild after the SnapRAID pool.

## Not in this release
- Booting the ISO on real hardware and recording what breaks (#175), the epic "works on a machine that is not the author's" (#459).
- Live state on by default (see the 0.3 notes).

## Not verified
- The web interface of this version, the first-run wizard on a real server, the pool import and the local users on real hardware.
- The headless browser stage (6) never ran.
- The unlock page of this version.
