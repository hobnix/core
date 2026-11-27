# Hobnix 0.14.0 release notes

Release notes of "0.14 Marketplace", built from the entries of `docs/changelog/` that are new since `v0.13.0` and from the pull requests of this
release. Beta: `v0.14.0-beta.1`.

## Read this first

**Nothing of 0.14 has been tested on a real server.** That includes everything in these notes: the new pages, the fixes and the update from 0.13.0.
The tracker issue [Hardware test: 0.14](https://github.com/hobnix/core/issues/1366) lists the boxes to check on a server, and none is ticked. It may
not have a box for every change yet. An unticked box is postponed and does not block a release. One fault named below (monthly sums) was seen on a
server before 0.13.0; its fix was not run on one.

**On 0.13.0, do not rely on `--dry-run` with the commands below. It was silently dropped or ignored, and the command really ran.**

- `hs ct <name> stop --dry-run` stopped the instance. `start`, `restart`, `update` and `autostart` had the same fault. `stop --keep-off` did nothing
  about the start at boot.
- `hs backup ct <name> reset --dry-run` removed the backup rules. A restore of a path, `hs backup offsite off` and `hs backup browse --off` also ran
  with `--dry-run`. Many other changing `hs backup` commands accepted it and did the real work.
- Misspelled options were ignored too: `hs backup prune --dryrun` pruned, and `hs net ip <name> clear --dryrun` cleared the address reservation.
- `hs user` and `hs group` commands such as `hs user <name> unlock` or `hs group <name> remove` dropped extra words in the same way.

0.14 fixes this ([#1360](https://github.com/hobnix/core/pull/1360), [#1361](https://github.com/hobnix/core/pull/1361)).

What changes for you as a server owner:

- **Dry runs and unknown words are checked.** A command does a dry run, or refuses and changes nothing. Words that were ignored before are now an
  error, so check your own scripts.
- **The Marketplace looks and works like a store:** app cards, categories, search, a page per app, and words that say who vouches for it.
- **Monthly sums of extension services work.** On 0.13.0 they were all dropped, for example the plays and watched minutes of Media Hub.
- **Every package from nixpkgs moves** with this update, not only one.
- **Authors of Rust extensions:** the SDK is renamed. This is a breaking change.

## What is new

### Marketplace

- **Apps > Marketplace** shows apps as cards with icon, name and one line, with a category filter and search. The tabs are Apps, Add-ons (extensions
  and capabilities), Installed, Updates and Advanced (repositories, package builder and the full package table).
- Each app has a page at `/apps/marketplace/<repository>/<name>` with description, pictures, needs, version, source and signature. An installed app
  shows Open and Manage instead of Install. Installing still shows the plan first. The App catalog page did not change.
- **Who vouches for it:** "Official, signed" (only the official Hobnix repository with a checked signature), "Community" (a signed repository added on
  this server) or "Community, unsigned".
- **Tested date:** for the official repository the page shows "Tested on a real server on <day>" if the signed index names a day, else "Not tested on
  a real server". Other repositories show "No Hobnix test date". Nothing writes this day into the index yet.
- **Does it fit:** an app that is not installed shows whether the memory and disk space its package states fit this server, with the reason if not,
  and notes such as a missing graphics card. A package that states neither shows "Memory and disk not stated". When the check was built, no app in the
  official index stated memory or disk. The figures come from the package and do not promise that the install works.
- **Version history:** the app page lists the newest version and up to 10 older ones from the signed index, with day, change text and withdrawn state.
  A repository without a signed index has no list. You cannot install an older version.

### Packages

- A package can name the highest core API level it works with (`requires_core_max`). `hs pkg install` and `hs pkg update` refuse a package outside its
  range. After a core update, an installed package whose range is too low keeps running; `hs update` names it and does not stop
  ([#1312](https://github.com/hobnix/core/pull/1312)).
- A package with the same name in another repository no longer shows as an update of yours, and installing it no longer replaces your copy. To switch
  repositories, remove the package first with `hs pkg remove <name>` ([#1313](https://github.com/hobnix/core/pull/1313)).

### Commands

- Every `hs ct <name>` command that changes the instance takes `--dry-run`. Unknown or misspelled options are refused. `hs ct <name> stop --keep-off`
  works. `hs ct <name> remove` always asks you to type the name and refuses `--yes`.
- The changing `hs user` and `hs group` commands take `--dry-run`.
- Of the changing `hs backup` commands, only `now`, `report`, `prune`, `init`, `restore ct` and `config restore` have a dry run. The others refuse
  `--dry-run`. All of them refuse unknown words. `hs backup prune --dry-run` still mounts the backup disk and takes the lock.
- `hs net ip` refuses words it does not know.

### Fixes

- **Monthly sums of extension services are recorded again.** On 0.13.0 the core dropped every one, with a warning in the service's journal. Dropped
  sums are not added later ([#1362](https://github.com/hobnix/core/pull/1362)). The 0.13 notes said these sums worked again; they did not.
- A share with a long name (42 to 80 characters), made by taking over a disk, can be deleted and changed in the web interface again. Taking over a
  disk now shortens a long name and shows it in the plan. Two folders do not become one share by accident. A new share still has at most 41 characters
  ([#1316](https://github.com/hobnix/core/pull/1316)).

### Performance measurement

- `sudo hs perf baseline --minutes 30 --out <file>` records CPU and memory of the live-state collector and the web server and times the page reads.
  `sudo hs perf baseline --compare <before> <after>` compares two runs. `hs timing` has the new option `--split`. It changes no setting and no data.
  Steps and limits: [Operations](operations.md#take-a-performance-baseline). This release gives no speed numbers.

### For authors of Rust extensions

**Breaking change** ([#1321](https://github.com/hobnix/core/pull/1321)): `hobnix-ext-sdk` is split into `hobnix-pkg` (shared base),
`hobnix-pkg-command` and `hobnix-pkg-service`. The protocol lines are byte for byte the same. A crate that pins an older tag or rev is not affected
until you move the pin.

The old name stays for 0.14 only, with a deprecation warning. **Not every 0.13 extension builds unchanged with it.** What to do when you move the pin:

- Build `Event`, `Success`, `Failure`, `EventRow`, `Init` and `http::Response` with their constructors, not with a struct literal.
- Add a `_` arm to a `match` that names every variant of `Lang`, `Caller`, `LogLevel`, `EventLevel`, `ErrorCode`, `HttpError` or `testing::Call`.
- `row.credential()` of an integration row returns `Option<Secret>`: read the value with `key.expose()`.
- The old `command::Request` no longer implements `Deserialize`.

To move to the new crates, also change the imports. `Service::start` and `on_event` return `hobnix_pkg::Error`, `ctx.event` is now `ctx.emit`, and
`ctx.credential` returns `Option<Secret>`. The full list is in [Write an extension](extensions-sdk.md#write-it-in-rust).

- **Optional:** with the feature `macros` of `hobnix-pkg-command`, `#[command]`, `#[derive(Args)]` and `commands!` make the dispatch and the
  `commands.tsv` rows from your code. `hs pkg validate` reads the rows from the program file without running it and refuses rows that differ
  (`binary.drift`) or a damaged or second table (`binary.table`) ([#1343](https://github.com/hobnix/core/pull/1343)).
- **A service that writes while it starts** no longer fails with `protocol_error`. The SDK holds these messages (at most 1000 and 4 MiB) and sends
  them after `ready`; a warning counts what was dropped. Output written straight to stdout is not held. **Rebuild the extension** to get the fix
  ([#1367](https://github.com/hobnix/core/pull/1367)).
- The Rust code of the core and the SDK now has stricter checks, edition 2024 and a pinned toolchain
  ([#1317](https://github.com/hobnix/core/pull/1317)). The SDK needs Rust 1.94 or newer.

## Security

- A repository added on the server is never shown as "Official" and cannot show a Hobnix test date, whatever its index says.
- Package pictures are treated as untrusted data: strict names and paths, only SVG, PNG and WebP with a type check, at most 300 KB, and sandbox
  headers.
- A package cannot replace an installed package of the same name from another repository.
- The macros and `hs pkg validate` refuse control characters in command rows.

## Upgrade notes

- A beta is a prerelease. A server gets it only if its update channel is `beta` (`hs config set updateChannel beta`). Look first with
  `hs update --preview`, then run `hs update`. Not tested on hardware yet.
- **The nixpkgs pin moved** to a newer revision of `nixos-26.05`, so every package from nixpkgs moves. What else changes with it was not compared.
  SQLite goes from 3.51.2, which has a rare WAL-reset corruption bug, to 3.53.3 ([#1350](https://github.com/hobnix/core/pull/1350)). After the
  update, check that the server boots, `hs` answers, and the web interface and your apps work.
- Check your own scripts for `hs` commands with extra or misspelled words. They are now refused.
- Package authors: keep `requires_core` in the form `">=N"` and use `requires_core_max` for an upper limit. `v0.13.0-beta.1` rejects a whole signed
  index when `requires_core` has another form. It lists a blueprint that uses the new key but refuses to show or apply it.
- Extension authors: see the SDK rename above.

## Not tested on hardware yet

Everything. In particular: the update from 0.13.0 with the new nixpkgs pin; the dry runs and refused words, the nightly backup, weekly check, prune
and report timers, and the backup and app actions of the web interface; the Marketplace with a real repository index and real pictures; the core range
and same-name packages; long share names; monthly sums; a baseline run; an extension built with the new SDK or the macros. Tracker:
[#1366](https://github.com/hobnix/core/issues/1366).

## Known limits

- **What an extension service writes to stderr is thrown away.** A design record says it goes to the journal. Crash messages and panics of a service
  are not visible, and neither are the log lines the SDK writes there when `start` fails. Read from the code, not run on a server
  ([#1368](https://github.com/hobnix/core/issues/1368)).
- A package that is too new for its own `requires_core_max` range can be shown as "needs a newer Hobnix", with the advice to update the server. That
  advice does not help here. The fit check can also approve an app whose install is then refused because of a same-name package.
- `hs pkg rollback` does not check the core range.
- Shares of 65 to 80 characters are still refused by the Docker editor and by remote sharing. Whether Samba accepts the longer name that deleting such
  a share creates is not checked.
- Taking over a disk with `--merge`, or disk by disk, can keep share names with capital letters, spaces, `_` or `.`. By the patterns in the code, the
  web interface cannot delete them and the file manager hides them. This was read from the code, not reproduced.
- Packages that state no memory or disk need cannot be checked for fit.
- The new SDK crates are not yet used by the packages in `hobnix/official`.

## Not in this release

- Installing an older version of a package, and holding a package at its version.
- Other open work of milestone 0.14 is not in this beta.
- The new core, daemon and job system planned for 0.15. This release has only their design records and migration map
  ([PLAN-core-daemon-migration](PLAN-core-daemon-migration.md)), a build measurement from a development PC, and tests of how app start and stop
  behave today.
