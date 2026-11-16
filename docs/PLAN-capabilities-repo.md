# Plan: optional capabilities as packages in hobnix/capabilities (accepted 2026-11-16)

Status: **Accepted 2026-11-16**: the owner accepted every recommended answer O1 to O11 (table at the end). Design record, for epic [#217](https://github.com/hobnix/server/issues/217) and its children #225, #221, #224, #228, #229, #177, #235
and #615. Nothing is built by this page. It turns ADR 0017 (`docs/adr/0017-capabilities-repository-and-channels.md`, accepted 2026-11-10)
into issue scopes, acceptance criteria and an ordered step list, checks its facts against the code of 2026-11-16 (branch `0.5`), and names
the points where the code now disagrees with the record. Owner decisions are in the table at the end. This plan changes no storage, network or
firewall behaviour. Not tested on hardware yet.

Read together with ADR 0008, ADR 0009 (a capability is a package kind), ADR 0017, docs/PLAN-packages.md, docs/PLAN-capabilities-on-machine.md,
docs/PLAN-channels.md and docs/PLAN-first-run-wizard.md.

## Problem

Every optional part of the server (a capability) lives in `capabilities/<name>/` of the core. A fix to one of them needs a core release, and
every server carries all of them. The epic wants the optional ones in their own signed repository, installed by the wizard or `hs pkg`, on
the server's update channel, so a stable server never gets untested work. The hard parts are a Nix module that comes from outside the
checkout, the generated files that a package changes, and CI across two repositories.

## What exists today (checked in the code on 2026-11-16)

| Part | State | Verdict |
| --- | --- | --- |
| **Recipe** | `kind = "recipe"`, `recipes/<name>/package.toml` + `run.sh` in hobnix/recipes; `hs recipe <name>` runs it (containers); no Nix | Keep |
| **Extension** | `kind = "extension"`, `extensions/<name>/package.toml` + `capability.toml` with `extension = true` + `commands.tsv` (rows only under `ext <name>`), `[[web.reads]]`/`[[web.changes]]`, `i18n/`, scripts; in hobnix/extensions (`ad-selfservice`, `games`, `passthrough`, `posters`); on/off without a rebuild (machine.toml `capabilities` + `/var/lib/hs/capabilities-on|off`); none has a `module.nix` | Keep; it already proves the "package without Nix" path |
| **Capability** | Core folder `capabilities/<name>/` with `capability.toml` (`kind = "feature"\|"provider"`, `requires`, `provides`, `needs`, `variants`, `implied_by`, `nix = "module.nix"`, `notes`); registry rows flagged `capability:<name>`; schema items with `capability = "<name>"`. **21 folders, 13 with `module.nix`** (ADR 0017 counted 20 and 12; `testlab` came later) | Not a package kind yet |
| `capabilities/default.nix` | `readDir ./.`, imports `./<name>/module.nix` when `enabled name` and the file exists; `options.nix` always | Extend (step 4) |
| `configuration.nix` line 68 | The enabled list = machine.toml `capabilities` + implied ones; names `metrics`, `tailscale`, `ad`, `docs`, `live-state`, `gateway`, `storage`, `incus`, `samba` by name | Those names are entangled; not pilots |
| `scripts/pkg.py` | `KINDS = ("recipe", "extension")`; `validate`, `repo-check` | Add `capability` (step 1) |
| `scripts/pkg_repo.py` | Fetch: local clone with tags; newest tag whose SSH signature verifies (`git verify-tag`, `gpg.ssh.allowedSignersFile` = `config/trusted-keys/<repo>.allowed_signers` for a default repository); beta tags only when `updateChannel` is beta or edge. Install: `git archive` of the index `path` at the tag into `current/.new-<name>`, links and `..` refused, read-only; `requires_core` checked in the index and in package.toml against `scripts/lib/api-level` (8); a name that is built in is refused; the old copy goes to `previous/<name>@<commit>`; `installed.toml` records version, repo, commit, tag. **No tree hash is recorded.** | Reuse; add vendoring (step 3) |
| `hs pkg remove` (scripts/pkg.sh) | Refused while the package is on or an enabled package `requires` it; typed name; rewrites `/var/lib/hs/generated/capabilities.tsv` when it exists; data and containers stay | Extend for vendored modules (step 3) |
| `schema-gen.py overlay` | Writes `capabilities.tsv` for installed capability manifests to `/var/lib/hs/generated/`; package options not built; not called by `hs pkg install` | Extend (step 6) |
| `config/package-repos.toml` | `recipes`, `extensions` only | Add `capabilities` after its first signed tag (step 11) |
| `config/trusted-keys/capabilities.allowed_signers` | Exists: `release@hobnix` and `release-ci` keys | Done |
| `hs sys pkg market` | Already has a `kind` column; `hs sys pkg list` has no `--kind` (ADR 0017 rule 21 names `hs sys pkg list --kind capability`, which does not exist) | The wizard filters `market` by kind; no new row shape |
| `scripts/dev/nix-matrix.sh` | Tar copy of the checkout to a temp dir, one variant per `capabilities/*/`, `all`, `core`, named assertions; CI runs it in the `nixos` job only for pull requests into `main`, pushes, tags, nightly | Add `--vendor` (step 5) |
| CI `packages` job | Checks out hobnix/recipes and hobnix/extensions at their default branch (no `ref:`), runs `validate`, `repo-check`, their tests | Add hobnix/capabilities (step 10) |
| Package repositories | Only `check.yml` in the sibling checkouts of recipes and extensions; no release or prepare-release workflow there yet (#522, #615 open); CONTRIBUTING step 3 still says "raise version in package.toml AND index.toml" | #615 applies to the new repository from day one |
| Installer | ISO carries the core repository only (`/etc/hs-installer`); `nixos-install` uses `install.nix`, which loads no capability; no package is on the stick | Nothing from hobnix/capabilities is needed to install |
| Web first-run wizard | `web/src/setup/steps.js`: account, network (slot), storage, preset, done; PresetStep polls `sys preset list` and `sys parts list` | Add a step (step 14) |
| `--impure` | Not used anywhere (the build is non-flake `nixos-rebuild`) | Keep it so |

Not verified: whether `registry_rows` (scripts/lib/registry-load.sh) reads a package whose kind is not `extension`; how the core web page of a
capability registers its reads (core READS table versus manifest `[[web.reads]]`); whether anything runs `git clean` in /etc/nixos; whether
`hs docs build` collects `guide.md` from installed packages. Each is checked in the step that needs it.

## Design

### Q1 What a capability package is (#225)

`kind = "capability"` in `package.toml` is the one manifest (ADR 0009 rule 3); `capability.toml` is not used for this kind. Fields: the
package fields (`name` = folder, `version`, `title`, `title_de`, `requires_core`, `audience`) plus the capability fields (`requires`,
`provides`, `needs`, `variants`, `implied_by`, `notes`) plus new ones: `type = "feature"|"provider"` (today's `kind` of capability.toml, renamed
because `kind` is taken, decision O5), `module = "module.nix"` (optional), `options = "options.toml"` (optional), `requires_nix_api = <int>`
(required when `module` is set). Everything else is as for an extension: `commands.tsv`, `[[web.reads]]`, `[[web.changes]]`, `[[events]]`,
`i18n/`, scripts, `NOTES.md`, `guide.md`, `tests/`.

Repository layout (ADR 0017 rule 1, unchanged):

```
index.toml                        [package.<name>] version, kind = "capability", path, title, requires_core, audience
capabilities/<name>/package.toml
capabilities/<name>/module.nix    optional; may import only *.nix files of its own folder
capabilities/<name>/options.toml  optional; [[item]] tables of config/schema.toml, each with capability = "<name>"
capabilities/<name>/commands.tsv, *.sh, i18n/, NOTES.md, guide.md, tests/
tests/run-all.sh                  runs every package's tests against HS_CORE
examples/                         one manifest example, not in the index
.github/workflows/check.yml       as hobnix/extensions, plus the nix matrix (Q5)
README.md LICENSE (AGPL-3.0) CONTRIBUTING.md SECURITY.md
```

A module refers to its own files by relative path (`${./testlab.sh}`), never to `/var/lib/hs/packages/...`: the file is copied into the store
at evaluation, so the system never depends on a mutable folder. Core helpers stay reachable through the `hs` argument (`hs.scripts`,
`hs.machine`, `hs.notifyFailure`).

### Q2 Fetch, pin, verify

Unchanged path: `hs pkg fetch` (signed tag only, never a branch), `hs pkg install <name>` (index `path` at the tag, read-only copy, requires_core).
New for the capability kind:

| Question | Options | Recommended |
| --- | --- | --- |
| Pin | `installed.toml` only; plus a lock in the checkout | **Both.** `installed.toml` stays the record of what is installed; `vendor/capabilities.lock` is what the Nix evaluation trusts |
| Hash in the lock | git tree id of the folder at the tag + sha256 of each `*.nix` file; sha256 of a tarball; sha256 of `module.nix` only | **Tree id + sha256 per `*.nix` file** (decision O3): the tree id is covered by the signed tag, the per-file sha256 is what Nix can check with `builtins.hashFile`, and a module that imports a sibling file (like incus/internal-link.nix) is covered |
| Who may ship Nix | any repository; default repositories only | **Default repositories only** (ADR 0009 rule 4); `pkg_repo.py` refuses at install, not at rebuild |

Lock format (generated by `hs pkg`, never edited; keys sorted, so the same input gives the same bytes):

```toml
[testlab]
version = "1.0.0"
repo = "capabilities"
tag = "v0.2.0"
commit = "<40 hex>"
tree = "<git rev-parse <tag>:capabilities/testlab>"
[testlab.nix]
"module.nix" = "<sha256 hex, as builtins.hashFile returns it>"
```

### Q3 Pure evaluation: vendoring the module into the checkout (#221)

The build is non-flake, so an absolute `import /var/lib/hs/packages/current/x/module.nix` would work today. It is still refused: the closure
would depend on a mutable folder, `nix-matrix.sh` and CI could not see it, `hs backup config` would not cover it, and a later flake or
`pure-eval` setting would break it. ADR 0017 rules 7 to 12 stay:

1. `hs pkg install|update` of a capability with `module` copies the verified folder from `current/<name>` to
   `/etc/nixos/vendor/capabilities/<name>/` (a copy, not a link; the target is `HS_NIXOS_DIR`, default `/etc/nixos`) and rewrites
   `/etc/nixos/vendor/capabilities.lock` atomically (`.new` + rename). `hs pkg remove` deletes both. One function does it:
   `pkg.py vendor --from <package folder> --to <checkout>`, so CI uses the same code (Q5).
2. `vendor/` is ignored by git through one line `/vendor/` in the tracked `.gitignore` (decision O2; ADR 0017 named `.git/info/exclude`, which
   must be repeated on every clone). `hs update`'s fast-forward never touches it.
3. `capabilities/default.nix` gets: `lock = if pathExists ../vendor/capabilities.lock then fromTOML (readFile ...) else {}`; for each enabled name
   that is not a core folder but is in `lock`, it imports `../vendor/capabilities/<name>/module.nix` after asserting that every file named in
   `lock.<name>.nix` has that sha256 and that the folder has no `*.nix` file the lock does not name. A mismatch is an evaluation error that names
   the package and says `hs pkg install <name>`. With no `vendor/` the import list is unchanged, so the store path of today's servers stays
   equal (proved with `nix-instantiate` before and after).
4. A core level `capabilities/nix-api-level` (one integer, starting at 1) is read by `pkg.py` (install refuses `requires_nix_api` above it) and
   by `hs update` after the pull (Q6). It goes up only when an `hs.*` name a module may use is removed or changes meaning; an added name does
   not raise it (deprecation rule of ADR 0008 rule 4).
5. `scripts/rebuild.sh` gets a pre-check before `nixos-rebuild`: every enabled name is a core folder, an installed package, or implied; a package
   with `module` is vendored and its lock line matches `installed.toml`. Otherwise it stops with the name and the command, nothing is built.

Install and wizard: `install.nix` loads no capability, so `nixos-install` needs nothing from hobnix/capabilities and works offline as today.
Packages are fetched on the installed system (first-run wizard or `hs pkg`), vendored, and take effect at the `hs rebuild` that follows.

### Q4 Generated files on the machine (#224)

What the build regenerates in the checkout (`schema-gen.py write`, `openapi-gen.py`, `openapi-ts-gen.py`) stays a developer step and never
runs on a server for packages. On the server, `schema-gen.py overlay write` (ADR 0017 rules 13 to 16, design 1 of
PLAN-capabilities-on-machine.md):

| Output in `/var/lib/hs/generated/` (root, not in git, not in the checkout) | From | Read by | Built |
| --- | --- | --- | --- |
| `capabilities.tsv` | `package.toml` of installed capability packages | `capability.sh`, `hs_ext.py` | yes |
| `schema.overlay.json` | `options.toml` of installed packages | `hs config`, `config-change.sh`, `hs config check` | no |
| `config-keys.overlay` | the same | the `CONFIG_KEYS` allowlist of `web-serve.py` | no |
| `layout.overlay.json` | the same + `[settings]` of the manifest | web settings pages | no |
| `retired-keys.tsv` | options of a removed package (key, capability, version) | `hs config check` (a note "unused, capability X removed", never an error) | no |

Rules: inputs are the core `config/schema.toml` of the running checkout and `current/*/package.toml` + `options.toml`, sorted by package name
and file order; JSON with sorted keys and fixed separators; no time stamps; so the same inputs give byte-equal files and `overlay check` can
compare. A key that clashes with the core or another package is refused: at install the package is not activated and the previous overlay
stays; after a core update that adds the same key, the package's options are left out and `hs doctor` names the package. Runs as the last
step of `hs pkg install|update|remove`, after `hs update` pulls a new core, and in a boot unit when the folder is missing.

Registry rows are not generated: `registry_rows` reads `commands.tsv` of packages that are on (built for extensions). A capability package's
rows are not in the core's `registry.tsv`, `openapi.json` or `sys.gen.d.ts`; the package documents its own `sys` rows. Which words a
capability package may own is decision O4 (recommended: rows whose first word, after `sys`, is the package name, for default repositories
only; any clash with a core row is refused by the loader).

Options with `store = "machine"`: the value is in machine.toml, the default is in the module (`hs.machine.<key> or <default>`), because
`config/defaults.nix` is core-only and generated. The package's tests check that the `or` default equals the `default` in its `options.toml`.
`hs config sync` keeps such keys (it already moves unknown keys to the closing section).

### Q5 CI across the repositories (#228)

| Where | What runs | Which ref of the other repository |
| --- | --- | --- |
| hobnix/server pull request | `packages` job: `validate`, `repo-check`, tests of hobnix/capabilities; `nixos` job: `nix-matrix.sh --vendor <capabilities checkout>` when the pull request touches `capabilities/default.nix`, `capabilities/options.nix`, `capabilities/nix-api-level`, `configuration.nix`, `scripts/pkg*.py` or `scripts/dev/nix-matrix.sh` (decision O9) | the branch of the same name if it exists, else `develop` (ADR 0017 decision 7) |
| hobnix/server release pull request (into `main`) and `v*` tags | the same, always | hobnix/capabilities `main` at its newest signed tag: what stable servers get |
| hobnix/capabilities pull request | `check`: `validate`, `repo-check`, `bash -n`, tests with `HS_CORE`; nix matrix with `--vendor .` when a `module.nix`, `package.toml` or `options.toml` changed | hobnix/server: same-name branch, else `develop` |
| hobnix/capabilities release pull request | `check` + nix matrix | hobnix/server at its newest signed stable tag **and** `develop` (decision O11) |

`nix-matrix.sh --vendor <dir>`: in the temp copy, runs `pkg.py vendor` for every package of `<dir>` that has a `module`, then the existing
variants plus `only-<name>` per vendored package and `all` including them. The job logs the commit of the other repository it used. A package
whose `requires_core` or `requires_nix_api` is not met fails with its name.

A core pull request that changes an interface a module uses: (1) the core adds the new name and keeps the old one for one release; (2) a
same-name branch in hobnix/capabilities moves to the new name, and both pull requests are green against each other; (3) the old name is
removed later with `nix-api-level` raised and `requires_nix_api` raised in the packages. The matrix catches a step done out of order.

### Q6 Uninstall, compatibility, rollback (#235)

- **Remove** (existing refusals stay): a package with `module` must be off and the rebuild that turned it off must have run (`hs sys parts
  pending` shows nothing for it); then `hs pkg remove` deletes `current/<name>`, `vendor/capabilities/<name>`, its lock line, its on/off marks,
  rewrites the overlay and appends its option keys to `retired-keys.tsv`. Data, containers, settings and machine.toml values stay (ADR 0009
  rule 7). Units of the module disappear at the rebuild that turned it off.
- **Compatibility**: `requires_core` (API level) and `requires_nix_api` are checked at install and update (index and package.toml). `hs pkg
  updates` and `hs sys pkg market` show a newer release whose needs are not met as "waits for core vX" (a new value in an existing column only
  if the shape allows it; otherwise a new labelled line, never a changed field). After `hs update` pulls a core whose `nix-api-level` is
  above what a vendored package was tested for, or below what it needs, the update stops before the rebuild and names the package.
- **Rollback**: package level, `previous/<name>@<commit>` is kept (exists) and the old lock is kept as `vendor/capabilities.lock.previous`;
  when the rebuild after `hs pkg update` fails, `rebuild.sh` offers (plan, then confirm) to put the previous copy and lock back. System level:
  the NixOS generation rollback restores the old closure, but `vendor/` still holds the new copy, so the next `hs rebuild` would bring it back;
  the guide says to restore the package first.

### Q7 Versions, releases, channels (#615, #217)

- Per package semver in `package.toml` and `index.toml`; per repository a signed `vX.Y.Z` on `main` (ADR 0007). hobnix/capabilities starts with
  #615: a pull request never edits a version; it carries a label `bump: minor` or `bump: major` (none = patch); the manual `prepare-release`
  workflow raises versions and opens the release pull request. CONTRIBUTING says so from the first commit.
- Channels as for recipes and extensions (PLAN-channels.md): stable = newest signed `vX.Y.Z`; beta = newest incl. `-beta.N` (cut from the
  milestone branch); edge counts as beta (packages never follow a branch).
- **Stable never gets untested work** because: only signed tags are installed; a capabilities release is gated by the matrix against the
  stable core tag; a core release is gated by the matrix against capabilities `main`; a release whose needs the installed core does not meet
  is shown, not installed; a package with `module` or a major bump never updates unattended (owner decision 8 of ADR 0017).

### Q8 The pilot

Criteria: off by default and optional for every user; no storage, network or firewall rule; not named in `configuration.nix`; small module;
`requires` only core parts; exercises every part of the chain (module, an option, rows, a page) so the pilot proves the path for the others.

| Candidate | Module lines | Options / rows | Named in configuration.nix | Touches network, firewall, storage | Fit |
| --- | --- | --- | --- | --- | --- |
| **testlab** | 31 | 1 (machine) / 5 | no | no (fetches hobnix/ refs only, allowlisted) | **best**: developer-only, nothing on a home server depends on it |
| edge-watcher | 40 | 1 / 0 | no | runs on edge nodes (public role) | second |
| live-state | 41 | 1 / 5 | 4 times | no | entangled |
| tailscale | 45 | 4 / 0 | 2 times | firewall provider (`hs.privateInterfaces`, SSH assertion) | no |
| metrics | 68 | 3 / 0 | legacy switch `metrics = true` | no | entangled |
| network (ADR 0017 decision 1) | none | 1 (settings) / 4 | no | router DHCP reservations, an API key in the vault; `scripts/lib/network.sh` is used by the recipe helper `fixed_address`, `manage-ct.sh`, the Docker and Unraid importers | touches the network; the "no Nix" path is already proven by four extensions |
| docs | none | 0 / 0 | yes (`webUi && webDocs`); `hs update` runs `hs docs build` | no | entangled with the core web |

**Recommended: `testlab`** (decision O1; it replaces ADR 0017 decision 1, so the owner must confirm). What moves: `module.nix` (script paths
relative, `testlabNightly` read with `or false`), `testlab.sh`, `testlab-change.sh`, the five rows, the option `testlabNightly` as
`options.toml`, NOTES.md, guide.md, tests/testlab.sh. What stays in the core: `scripts/dev/nested.sh` and `nested_stages.py` (CI's
`nested.yml` uses them), `scripts/dev/testlab-browser.py` (not verified who else uses it), the web page (nav `capability: testlab`, hidden
while off; moving web components is ADR 0016's matter).

Migration of a server with `testlab` on: the core release that drops the folder ships a check in `hs update` (after the pull, before the
rebuild): `testlab` is enabled and not installed as a package, so it shows a plan (`hs pkg install testlab`, signed tag, rebuild) and asks;
without a person it stops with the command (decision O10). Giving up the pilot: revert the core pull request (folder back); because a built-in
name refuses a package of the same name, that core release's `hs update` removes `vendor/capabilities/testlab` and the package copy first,
shows it, and keeps `testlabNightly` in machine.toml.

### Q9 What stays in the core

ADR 0009 rule 2, unchanged: storage, backup and restore, samba, incus, the web interface and its renderers, the registry loader,
notifications, `hs` itself, the installer, `hs pkg`. Also: everything `install.nix` and the installer need offline, `capabilities/default.nix`,
`options.nix`, `nix-api-level`, the trusted keys, `nix-matrix.sh`, and every capability that `configuration.nix` names (until it stops naming
it). The firewall providers (`tailscale`, `gateway`, `edge-ports`) and `network` are not moved by this plan.

## Issue scopes and acceptance

| Issue | Scope | Done when |
| --- | --- | --- |
| #217 epic | Steps 1 to 18 | the pilot was installed, enabled, rebuilt, updated and removed on a real server from a signed stable tag, and a stable server did not see a beta |
| #225 | Steps 1, 9, 11, 12 | hobnix/capabilities has a signed tag holding `testlab`; the core no longer has `capabilities/testlab`; both CIs green |
| #221 | Steps 2, 3, 4, 5 | a fixture package with a `module.nix` evaluates through `vendor/` with no `--impure`; a changed byte in the vendored module fails the evaluation with its name; store path of a server without `vendor/` unchanged |
| #224 | Steps 6, 7 | `hs pkg install` of a package with `options.toml` makes its keys settable in `hs config` and the web without a rebuild; remove makes them vanish and `hs config check` reports them as unused; two runs give byte-equal files |
| #228 | Steps 5, 10 | a core pull request that renames an `hs.*` name a vendored module uses fails the matrix with the package name; the capabilities `check` runs against the same-name core branch |
| #229 | Step 14 (backend half) | `hs sys pkg start install` + `parts start enable` + rebuild run as one job from the wizard, with a plan first |
| #177 | Step 14 (page half) | the first-run wizard has the step, lists capability packages, shows `requires`, skips cleanly |
| #235 | Steps 3 (remove), 7, 13, 15 | removal of an enabled or required package is refused; an incompatible release is shown, not installed; a failed rebuild after an update offers the previous copy |
| #615 | Step 11 for this repository | a capabilities release was prepared and cut without a version edit by hand |

## Steps

Sizes: S up to a day, M two to three days, L a week. Every step adds its tests, `bash -n` for touched scripts, `scripts/dev/t quick <names>`,
`python3 scripts/pkg.py validate`, and a changelog entry when users see it.

| # | Size | Step | Files | Needs | Done when |
| --- | --- | --- | --- | --- | --- |
| 1 | S | `capability` kind in `pkg.py` (fields of Q1, `type`, `module`, `options`, `requires_nix_api`), `repo-check`, `hs pkg list --kind capability` (help text only), a fixture package in `tests/fixtures/pkgtree` | scripts/pkg.py, scripts/pkg.sh, scripts/lib/registry.tsv (help text), scripts/lib/i18n/de.tsv, tests/pkg.sh | O5 | validate accepts the fixture and refuses each bad field |
| 2 | S | `capabilities/nix-api-level` and its check at install | capabilities/nix-api-level, scripts/pkg_repo.py, tests/pkg-repo.sh | 1 | a package needing level 2 is refused on level 1 |
| 3 | M | Vendoring: `pkg.py vendor`, install/update/remove write and delete `vendor/` and the lock, non-default repository and core name refused, `.gitignore` line | scripts/pkg.py, scripts/pkg_repo.py, scripts/pkg.sh, .gitignore, tests/pkg-vendor.sh (new) | 1, 2, O2, O3 | install, update, remove of the fixture give the expected tree and lock, byte-equal on a second run |
| 4 | M | `default.nix` loads vendored modules with the hash check; `rebuild.sh` pre-check | capabilities/default.nix, scripts/rebuild.sh, tests/rebuild*.sh | 3 | store path equal without `vendor/` (nix-instantiate before/after); a tampered module fails with its name |
| 5 | M | `nix-matrix.sh --vendor <dir>`; a fixture capability with `module.nix`; CI path filter | scripts/dev/nix-matrix.sh, tests/fixtures/capabilities/hello-nix/ (new), .github/workflows/ci.yml | 3, 4, O9 | matrix green with the fixture in WSL Debian and in CI; no `--impure` anywhere (`git grep impure`) |
| 6a | S | Overlay writer for `options.toml` (+ determinism test) | scripts/schema-gen.py, tests/schema-overlay.sh | 1 | two runs byte-equal; a clash refused |
| 6b | M | Readers: `hs config`, `hs config check`, `config-change.sh`, `machine-sync.sh` | scripts/config.sh, scripts/config-change.sh, scripts/machine-sync.sh, tests/machine-toml.sh, tests/config-*.sh | 6a | a package key is settable and checked; the core keys unchanged |
| 6c | M | Readers: `web-serve.py` allowlist and the settings layout; `hs pkg install|update` call `overlay write`; boot unit | scripts/web-serve.py, web/src/settings/*, scripts/pkg.sh, a unit in configuration.nix | 6a | the web shows and saves a package option without a rebuild |
| 7 | S | `retired-keys.tsv` on remove; `hs config check` note | scripts/pkg.sh, scripts/schema-gen.py, scripts/config.sh | 6b | a removed package's key is a note, not an error |
| 8 | S | Row namespace for capability packages in the loader | scripts/lib/registry-load.sh, tests/ext.sh, tests/commands.sh | 1, O4 | a `testlab ...` row of a default-repository package loads; the same row from an added repository or a clash with a core row is refused |
| 9 | S | Scaffold hobnix/capabilities (README, CONTRIBUTING with #615 labels, SECURITY, empty `index.toml`, `examples/`, `check.yml`, `tests/run-all.sh`), branch protection on `main` and `develop` | the other repository | 1, owner approval | its `check` is green against core `develop` |
| 10 | M | CI both ways (Q5) | .github/workflows/ci.yml; check.yml of hobnix/capabilities | 5, 9, O11 | the four rows of the Q5 table run; each logs the other repository's commit |
| 11 | S | Release flow: `release.sh` on the new repository, `prepare-release` (#615, #522), first signed tag, then `capabilities` in `config/package-repos.toml` | scripts/dev/release.sh (if needed), config/package-repos.toml, tests/release.sh, tests/pkg-repo.sh | 9, O8 | `hs pkg fetch` verifies the tag on a test server; a server without the tag shows no failed row |
| 12 | L | Pilot `testlab` (Q8): package in hobnix/capabilities; core drops the folder, its schema item (`schema-gen.py write`), its rows; nix-matrix variant via `--vendor`; `hs update` migration check | capabilities/testlab/ (removed), config/schema.toml + generated files, scripts/lib/registry.tsv, scripts/testlab*.sh (moved), scripts/update.sh, tests/testlab.sh (moved), docs/operations.md, changelog | 3 to 8, 10, 11, O1, O10 | a test VM with `testlab` on updates, installs the package, rebuilds, `hs testlab results` works; both CIs green |
| 13 | S | Rollback of a package update (`lock.previous`, `rebuild.sh` offer) and the revert path of the pilot | scripts/rebuild.sh, scripts/pkg_repo.py, tests/pkg-vendor.sh | 3, 4 | a failing fixture update is put back after confirmation |
| 14 | M | Wizard step: `parts` after `preset` in `FIRST_RUN_STEPS`, `PartsStep.svelte` (filters `sys pkg market` by kind, shows `requires`, plan via `sys pkg plan install`), one job: install, enable, rebuild; the terminal `hs first-run` asks the same | web/src/setup/steps.js, web/src/setup/PartsStep.svelte (new), web/src/pages/FirstRun.svelte, scripts/first-run.sh, tests/web-first-run-steps.mjs | 3; can use the fixture repository before 12; O7 | the step lists the fixture, the job runs in the test lab |
| 15 | S | Compatibility display and the `hs update` stop for vendored packages | scripts/pkg_repo.py, scripts/update.sh, tests/update-channel.sh | 2, 3 | a release needing a newer core shows "waits for core"; an update that breaks a vendored package stops before the rebuild |
| 16 | S | `hs backup config` includes `vendor/` and the lock (ADR 0017 decision 10) | the backup config script (backup area) | 3 | a config restore on a clean VM rebuilds without reaching GitHub |
| 17 | S | Guides: operations "Optional parts from hobnix/capabilities", containers-and-apps package section, ADR 0017 note that decision 1 was replaced (if O1) | docs/operations.md, docs/containers-and-apps.md, docs/adr/0017-... | 12 | `tests/docs.sh` green |
| 18 | S | Hardware test on a real server: install, enable, rebuild, update, remove the pilot; a stable server ignores a beta tag | the issues' "Hardware test" boxes | 12 to 16 | boxes ticked with what was seen. Not tested on hardware yet. |

Parallel sessions after step 1: lane A 2 → 3 → 4 → 5 (Nix), lane B 6a → 6b / 6c → 7 (overlay), lane C 8 (loader), lane D 9 → 11 (other
repository, needs the owner). Steps 13, 14, 15 and 16 can start once 3 is merged. Step 10 waits for 5 and 9; step 12 waits for everything
above it. Steps 4 and 12 both edit `configuration.nix` or `capabilities/` and must not run at the same time; 6b and 6c touch different readers.

## Risks

- **A second tree of Nix code.** A core change can break a module it cannot see. Mitigation: the matrix with `--vendor` on interface changes,
  `nix-api-level`, the release gates both ways.
- **Untracked files define the system.** `/etc/nixos/vendor/` is not in git: lost by a re-clone or a `git clean -x` (not verified that nothing runs
  one), invisible to a later flake (flakes ignore untracked files). Mitigation: backup of `vendor/` (step 16), `rebuild.sh` pre-check, the lock is
  reproducible from `installed.toml` + the package copy.
- **Core and package out of step.** `hs update` and `hs pkg update` are separate; the stop of step 15 turns a silent break into a named refusal.
- **Options in two places.** Package keys are in the overlay, not in `machine.toml.example`; `hs config sync` moves them to the closing section,
  so their paragraph and comment are lost. Accepted for now.
- **Row namespace.** Letting a package own a top-level word (O4) widens what a package can add; limited to default repositories.
- **The pilot is a developer tool.** It proves the chain, not user value; testlab itself has never run on a server ("UNVERIFIED" in its module).
  The hardware test needs only install, enable, `results`, update and remove, not a nested run.
- **The record changes.** O1 replaces an accepted owner decision; until the owner answers, step 12 does not start (steps 1 to 11 are the same
  for every pilot).
- New PLAN pages must be listed in docs/categories.tsv and docs/README.md (tests/docs.sh); this page is not listed yet.

## Decisions for the owner

Accepted on 2026-11-16: all recommended answers, O1 to O11. The "Recommended" column is the decision. O1 replaces decision 1 of ADR 0017 (the pilot is `testlab`, not `network`).

| Id | Question | Options | Recommended |
| --- | --- | --- | --- |
| O1 | Which capability is the pilot (step 12) | `testlab`; `network` (ADR 0017 decision 1); `docs`; `edge-watcher` | `testlab`: optional, off by default, no network/firewall/storage rule, not named in configuration.nix, 31-line module, exercises module + option + rows + page; the "no Nix" path is already proven by four extensions |
| O2 | How `vendor/` is ignored (step 3) | `/vendor/` in the tracked `.gitignore`; `.git/info/exclude` on each server | `.gitignore`: one line, every clone and CI get it |
| O3 | What the lock pins (step 3) | git tree id + sha256 per `*.nix`; tarball sha256; `module.nix` sha256 only | tree id + sha256 per `*.nix` |
| O4 | Which command words a capability package may own (step 8) | its own name as first word, default repositories only; only `ext <name>` (renames the pilot's rows and its web contract); rows stay in the core | own name, default repositories only |
| O5 | Name of the capability's own kind in package.toml (step 1) | `type = "feature"\|"provider"`; `capability_kind`; drop it | `type` |
| O6 | May a package declare `store = "machine"` options (step 6) | yes, default in the module with `or`, checked by the package tests; settings options only for now | yes (the pilot has one) |
| O7 | Wizard without a network (step 14) | network needed, step skippable; the ISO carries the stable index and packages (ADR 0017 rule 22) | network needed first; the ISO copy later, once a stable capabilities tag exists |
| O8 | When `capabilities` joins `config/package-repos.toml` (step 11) | after its first signed tag; at once | after the first signed tag (with no tag every `hs pkg fetch` shows a failed row) |
| O9 | When the core runs the matrix with `--vendor` (step 5) | path filter on the Nix interface files; every pull request; release pull requests only (today's rule) | path filter, plus always for release pull requests and tags |
| O10 | A server with the pilot on meets the core release that drops it (step 12) | `hs update` shows a plan and asks to install the package; the rebuild refuses with the command only | plan and ask; without a person stop with the command |
| O11 | What a capabilities release is tested against (step 10) | the core's newest stable tag and `develop`; `develop` only | both |

## Check that it worked

- `git grep -n impure` finds nothing; a server without `vendor/` has the same system store path before and after steps 4 and 12.
- `hs pkg install testlab` on a test VM: signed tag verified, `vendor/capabilities/testlab` and the lock written, `hs ext`/`hs help --all` show
  the rows, `hs rebuild` builds the timer when `testlabNightly = true`; `hs pkg remove testlab` after `hs ext disable testlab` and a rebuild
  leaves no row, option or page, and keeps `/var/lib/hs/testlab`.
- On a stable server, a `-beta.N` tag of hobnix/capabilities is not offered.

Not tested on hardware yet.
