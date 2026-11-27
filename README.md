<p align="center"><img src=".github/branding/banner@2x.webp" alt="hobnix" width="100%"></p>

# Hobnix

A NixOS home server you can read: apps in Incus containers, shares, backups, a web interface and one command, `hs`, to run it all.
Status: beta. What was not run on real hardware is marked "Not tested on hardware yet." in the guides and is not promised here.

## Who Hobnix is for

Hobnix is for people who run a home server today, for example with Unraid, and want apps, shares and backups on a system they can read and
rebuild. It is a home NAS with apps first, not a virtualization platform. Every update is a NixOS generation, the server is one repository
with one `machine.toml`, and every change shows a plan first; a destructive one asks you to type the name. It does not do clusters with
shared state, high availability or live migration (ADR 0013).

## Three repositories

| Repository | What is in it |
| --- | --- |
| [hobnix/core](https://github.com/hobnix/core) (this one) | The framework: the `hs` command, the web interface, the installer, the package client and the Nix glue. The core does not decide which capabilities a server has. |
| [hobnix/official](https://github.com/hobnix/official) | The packages the project maintains: apps (recipes), optional parts (extensions), capabilities and blueprints. `kind` in each package tells them apart. |
| [hobnix/community](https://github.com/hobnix/community) | Packages from other people, reviewed, with a lower trust tier. |

`hobnix/recipes`, `hobnix/extensions` and `hobnix/capabilities` are retired into `official`; a server that recorded packages from them moves
them over by itself (`hs pkg repo migrate`, also run by `hs update`). Design: [docs/PLAN-registry.md](docs/PLAN-registry.md).

## How packages reach a server

- Each repository publishes a signed `index.json`. The server checks the signature and the hash of each package folder; neither the host
  of the index nor the git host is trusted. The default repository is served from `packages.hobnix.dev` (live, signed). Servers on v0.12 keep the old
  rows in `config/package-repos.toml` until they update. See PLAN-registry.
- `hs pkg refresh` fetches the index (a daily timer does it too). `hs pkg fetch` updates the package repositories, `hs pkg available` shows
  what they offer, `hs pkg install <name>` installs one, `hs pkg update <name>` updates one at a time, and `hs pkg list` and
  `hs pkg updates` show what is installed and what is newer. `hs pkg repo add <name> <url> --key <allowed_signers file>` adds a
  third-party repository.
- `hs update` pulls this repository, refreshes the indexes and rebuilds.
- A blueprint is a package that lists other packages and presets. You choose one at install time (`--blueprint <name>`, `hs blueprint list`);
  nothing that was not chosen is installed. See [Install](docs/install.md).
- Writing a package: [Apps and containers](docs/containers-and-apps.md), [Extensions SDK](docs/extensions-sdk.md), `hs pkg new`.

Seen on one real server: installing and updating packages from the official index. Not tested on hardware yet: a community or third-party
repository.

## Install and use

- First install, or moving an existing `/etc/nixos` into a repository: [docs/install.md](docs/install.md).
- Daily work: change `machine.toml`, then `hs update` to pull and rebuild, or `hs rebuild` to apply local changes only.
- `hs help` lists every command (`scripts/lib/registry.tsv` is the one list). `hs` alone opens the full-screen interface.

## Documentation

All guides are in [docs/](docs/README.md): [Install](docs/install.md), [Apps and containers](docs/containers-and-apps.md),
[Storage and disks](docs/storage-and-disks.md), [Users and shares](docs/users-and-shares.md), [Backup and recovery](docs/backup-and-recovery.md),
[Operations](docs/operations.md), [Web interface](docs/web-interface.md). Release notes: `docs/RELEASE-NOTES-*.md`.

## Build and test the core

See [docs/dev-environment.md](docs/dev-environment.md). In short: `scripts/dev/t list` names the tests and `scripts/dev/t quick [name...]` runs
them quietly. Generated files (`config/defaults.nix`, `machine.toml.example`, ...) come from `config/schema.toml` through
`python3 scripts/schema-gen.py write`; do not edit them by hand. A new command needs a row in `scripts/lib/registry.tsv`.

## Layout

| Path | Purpose |
| --- | --- |
| `configuration.nix`, `install.nix` | Shared system config, and the minimal config for the first installation |
| `machine.toml.example` | Template for per-machine values, every option explained. `machine.toml` and `hardware-configuration.nix` are yours and not committed |
| `scripts/` | The commands, available as `hs <command>` |
| `config/` | Schema, defaults and the package repository list |
| `pkgs/`, `web/` | Packages that are not in nixpkgs, and the web interface |
| `docs/` | The guides, plans and decisions |

The `hs` commands print English only (ADR 0025); the web interface is translated.

## The name

**Hob** is a small, hairy, wizened household and farm spirit from the folklore of the English Midlands, Northern England and the
Anglo-Scottish border: the helper that quietly keeps the house running. **Nix** is NixOS, the operating system underneath. Hobnix is
the helper that keeps a NixOS home server running.

## AI was used here

Large parts of the code, the documentation and the tests of this repository were written with the help of AI coding assistants. The
maintainer directs, reviews and tests the work, but not everything has been run on every kind of hardware (the guides mark what has not
been tried yet: "Not tested on hardware yet."), and AI-written code can be wrong in ways that look right. This software runs as root on your server
and touches disks: read what it does, try it in a virtual machine first, and report what you find.

## Licence

The core is licensed under the GNU Affero General Public License v3.0 or later. In [hobnix/official](https://github.com/hobnix/official) the
recipes are MIT and everything else is AGPL-3.0. A community package keeps its author's licence.
