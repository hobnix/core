# Package registry: a signed index over git, a core that is only the framework

Status: design, decided with the owner on 2026-11-22; milestone 0.13 "Package Registry" (before the marketplace, 0.14). Step 2, the index format and its CI build and signing, is built (hobnix/core#1069, see "Built: the index format"), and `hs pkg` reads it (hobnix/core#1070, "Built: the client"); the timer and the event are not.
It replaces "What stays in the core", the repository list and the tag-based version rule in docs/PLAN-packages.md, and part of the plan of
the closed milestone 0.5 (docs/PLAN-capabilities-repo.md and ADR 0017, accepted 2026-11-10 and 2026-11-16): the repository
`hobnix/capabilities` and the optional-only move. **Kept from that plan:** vendoring of Nix modules with a lock and a pure evaluation
(ADR 0017 rules 8 to 12, `scripts/lib/pkg_vendor.py`), `nix-matrix.sh --vendor`, CI across repositories. **Not yet reconciled:** the
channels (`updateChannel`, rules 24 to 26) against one version per package; see "Open points". The old plan was not read in full when this page
was first written; the steps and issues of 0.5 (#221, #224, #228, #229, #231, #235, #615) need to be checked against this page before
step 4.

## Why

- A package's version is tied to a release of its repository ("the latest release tag is the available version"). A package bump needs a
  repository release, so the repository version rises very fast and means nothing.
- A server only sees an update after `hs pkg` fetched; nothing refreshes by itself.
- The marketplace needs icon, background, screenshots, author and a trust label without cloning every package.
- The core still carries capabilities (storage, incus, samba, network ...) that a server such as a VPS never needs.

## Decisions

1. **One version per package, no repository release.** A bump is a pull request that changes `version` in `package.toml`.
2. **A signed index** (`index.json`) is what servers read. Git stays the storage; no npm- or Docker-style registry service.
3. **Three repositories:** `hobnix/core` (renamed from `hobnix/server`), `hobnix/official` (recipes, extensions and capabilities as one
   set; `kind` tells them apart) and `hobnix/community`. Third-party repositories stay possible. `hobnix/recipes`, `hobnix/extensions` and
   `hobnix/capabilities` are retired.
   **Switched (2026-11-24, #1074):** `config/package-repos.toml` has the one default row `official` (signed index, `replaces` the three old
   names, `core` the four packages the core names); `hs pkg repo migrate` moves installed packages over. Not tested on hardware yet.
4. **The core is only the framework.** All capabilities move to `hobnix/official`. A server works with any subset.
5. **Blueprints** choose the set at install time.

## The index

One `index.json` per repository, built and signed by CI on every merge to the main branch, and daily so it does not expire.

```json
{
  "format": 1, "serial": 1042, "generated": "2026-11-22T04:00:00Z", "expires": "2026-12-06T04:00:00Z",
  "repo": "official",
  "packages": {
    "jellyfin": {
      "kind": "recipe", "version": "1.4.2", "commit": "<sha>", "tree": "sha256:<hash>",
      "requires_core": ">=0.13", "yanked": false,
      "needs": ["docker"], "core": false,
      "meta": { "title": "Jellyfin", "author": "...", "license": "...", "homepage": "...", "tags": ["media"],
                "icon": "assets/<hash>.webp", "background": "assets/<hash>.webp", "screenshots": [], "changes": "..." }
    }
  }
}
```

- `serial` only goes up; a client refuses an index with a lower serial than the one it has (no rollback to an old index).
- `expires`: a client keeps working from its cache after expiry and shows a warning after a grace period of 7 days.
- `tree` is a hash of the package folder at `commit`. The server fetches an archive of that commit from the git host and checks the hash;
  neither the index host nor the git host is trusted, only the signature and the hash.
- Only current versions and what a rollback needs are listed. A bad version is marked `yanked`.
- `meta` is built from `package.toml` and `assets/` in the package folder, reviewed and versioned with the package. CI resizes images and
  names them by content hash, so the marketplace reads only the index and the assets and the server can cache them for offline use.
- Format changes bump `format`; a client reads every format it knows and ignores unknown fields.

### Built: the index format (hobnix/core#1069)

`scripts/lib/pkg_index.py`, reached as `python3 scripts/pkg.py index ...` or `hs pkg index ...`: `build`, `validate`, `sign`, `verify`, `tree`.
Not tested on hardware yet; the signing workflow has never run on GitHub.

- **Entry fields** beyond the example above: `path` (the package folder in the repository, so a server can fetch it), `yanked_reason`
  (optional), `renamed_from` (optional list), `binaries` (optional, see below). `meta.icon` and `meta.background` are `null` when the package has none.
- **`binaries`** (hobnix/core#1129): for a package whose manifest has `[[binary]]` rows, a list `[{bin, target, sha256, size}]` read from the manifest
  (`size` of the file in the folder when it is there; a row not built yet is left out). **Informational only**, inside the signed document so the
  signature covers it, so a client can say "contains a prebuilt program (x86_64)" before it downloads anything. Install and update never use it: they
  check the manifest `sha256` and the tree hash. A package without `[[binary]]` has no field, and an index without it stays valid. The builder side
  (`pkg_index.py validate`, `verify`) refuses a row with a bad shape; a client (`validate` without strict) ignores a malformed or unknown field.
- **Source:** the entries come from `index.toml` (paths, `core`) when the repository has one, else from `package.toml` files under `packages/`,
  `recipes/`, `extensions/`, `capabilities/`, `blueprints/`. `meta` is the `[meta]` table of package.toml (`author`, `license`, `homepage`,
  `tags`, `changes`) plus `title` and `title_de`. `needs` is `needs` of a recipe plus `requires` of a capability.
- **Yanked:** `yanked.toml` in the repository: `[[yanked]]` with `name`, `version`, `reason`. Only the current version is listed; keeping
  the versions a rollback needs is not built yet.
- **Tree hash** (decided here): `sha256:` over the listing `<mode> <size> <sha256 of the content> <path>
`, files sorted by path, mode 755
  for an executable file else 644, symlinks refused. It does not depend on git, so a server computes the same hash from an archive of the commit.
- **Assets** (`assets/icon.*`, `assets/background.*`, `assets/screenshots/*`; png, jpg, webp, at most 5 MB each, 8 screenshots): resized
  (icon 256x256, background 1280x720, screenshot 1280x1280, proportions kept), written as WebP, named `assets/<first 16 hex of the sha256>.webp`.
  The builder needs Pillow; `--skip-assets` leaves the images out.
- **Serial:** `--serial N`, or `--prev <index.json>` for the previous index plus 1. `verify --prev` refuses a lower serial, and the same
  serial with different content. `expires` is `generated` plus 14 days (`--ttl-days`); an expired index only warns.
- **Signature** (decided here; the plan named none): an SSH signature, as for release tags, made with `ssh-keygen -Y sign` over the exact
  bytes of `index.json`, namespace `hobnix-index`, stored beside it as `index.json.sig`. The trusted keys are an `allowed_signers` file
  (`config/trusted-keys/<repo>.allowed_signers`) whose line carries `namespaces="hobnix-index"`, so a key that signs git tags does not sign
  indexes. `verify` checks the signature first and reads nothing from the file before that.
- **The key** is never in the repository, in argv or in a build step's environment: `sign` takes the name of a key FILE. In CI only the
  `sign` job of the CALLER workflow (environment `index-signing`, main branch only) has the secret, because an environment secret did not reach the
  jobs of a reusable workflow (hobnix/official run 45365647291). The job passes it as the input `key` to the composite action
  `.github/actions/index-sign` of the core, which masks it, writes it to a file with mode 600 in the one step that gets it, signs, verifies against
  the trusted keys and removes the file in an always() step. `build` (reusable, `.github/workflows/package-index.yml`) needs no secret, and the
  tests sign with a key made on the spot. The caller block is in the header of the workflow. Neither has run in this shape.
- **Not decided here:** the key itself (nobody has made it; its public half goes into `config/trusted-keys/` with the namespace above), the
  channels (the index has no `channel` field yet; a client ignores unknown fields, so adding one later is a compatible change), the offline
  root key.

### Built: the client reads the index (hobnix/core#1070)

`scripts/pkg_repo.py`. Not tested on hardware yet; no default repository has an index yet, so nothing changes for a server until one does.

- **Which repository:** a repository row with an `index` address (`hs pkg repo add <name> <git url> --key <file> --index <address>`, or `index =` in
  `config/package-repos.toml`). `url` stays the git address the commits come from. A row without `index` keeps the signed release tags. The key file must carry `namespaces="hobnix-index"`, and the `repo` field of the index must equal the row's name (so another repository's index, signed by the same CI key, cannot be served under this address): add the repository under the name its index has.
- **Fetch:** `hs pkg fetch` loads `index.json` and `index.json.sig` (https or a local path), checks the signature first (the same key file, line with
  `namespaces="hobnix-index"`), the schema, and the serial against the kept `index/<repo>/live/index.json` and against the serial floor `index/<repo>/serial` (serial and sha256 of that
  index): lower is refused, the same serial with other content too. The fetch holds a lock (`index/<repo>/.lock`, flock). The floor is written first (synced, atomic rename) and never removed by the swap; then the kept pair (`index/<repo>/live/`) is replaced by a directory swap. A crash in the swap leaves `.old`, which is still read (and is not deleted before the new `live/` exists), and the next fetch repairs it; with `live/` and `.old` both gone the floor still refuses an older signed index. Every read re-verifies the signature of the kept copy. An index past `expires` plus 7 days
  prints a warning; it keeps working. `hs pkg fetch` also clones or fetches the git repository, so a read (`show`, `asset`, `capabilities`) never runs `git clone` or `git fetch`; the checked package folders are cached per commit in `index-cache/<repo>/` (a read of a commit that is not in the clone says `hs pkg fetch`). The fetch (index part and git part) runs under the one lock and fetches every commit the index pins, also one no branch reaches any more; every git call has no terminal prompt and a time limit (`HS_PKG_GIT_TIMEOUT`, 180 s), and waiting for the lock is bounded (`HS_PKG_LOCK_WAIT`, 240 s, then "another pkg fetch is running"), so a stalled remote cannot hold the lock. An install may fetch, but under the same lock; the plan/diff of an update never fetches (a missing commit says `hs pkg fetch`). The clone is fetched once per run; a pinned commit that still cannot be fetched is recorded in `index/<repo>/unfetchable.json`: that package is not available (`show`/`install`/`update` give the reason, a warning goes to stderr) and the other packages and the exit code are unaffected. The package stays in the catalog flagged unavailable: never offered, an installed copy shows in `market` as `current` with the reason in the title (not as `orphan`), and `hs pkg install --core` exits non-zero naming it. The fetches by id share one `HS_PKG_GIT_TIMEOUT` budget, so the lock is held at most 3 x that + 60 s, which is also how long a waiting fetch or install waits; git gets `GIT_HTTP_LOW_SPEED_*` and (unless set by the person) an ssh command with ConnectTimeout/ServerAlive, so a fetch left behind by a killed caller ends by itself. Repositories without an index are still fetched outside the lock (unchanged). When the index is accepted but the clone step fails (or the index itself is refused), the row is `<repo><TAB>-<TAB>-<TAB><reason>` and `hs pkg fetch` (and `hs pkg update`) exit 1; the accepted index stays and is read. A damaged `serial` file with no kept index left refuses the fetch (delete the file by hand, the message names the exact path; this works for the default repositories too); a missing one is the first fetch. The cache keeps a folder created or read in the last 10 minutes when it prunes.
- **Version:** the `version` of the entry is the available version. The tag column of the existing machine lines is `v<version>-<8 hex of the commit><8 hex of the tree hash>`, so a plan made for a tag installs only those files (the web job accepts that shape), the Release
  column of `hs pkg fetch` is `serial-<N>` (shapes unchanged). An update is offered when the index version is higher; a changed commit with the same
  version is not an update.
- **Install:** the pinned `commit` is fetched into the clone, `git archive` of the package folder is extracted and its tree hash (`pkg_index.py tree_hash`)
  must equal the entry's `tree`, else nothing is installed. `show`, `asset` and the update prompts read files from such a checked copy, not from git objects; a path with `..`, an absolute path or one that resolves outside the folder is refused.
- **Yanked:** a yanked entry is not listed by `available`, not offered by `updates`, refused by `install`, `update` and the plan (`show`) with its reason; an installed copy stays.
- **Not built:** the timer and event, ETag, the per-channel index, the check that a name does not exist in two repositories, `repo/name` syntax.

## Hosting

- **GitHub Pages behind a custom domain** on `hobnix.dev` (registered 2026-11-22), for example `packages.hobnix.dev/official/index.json`.
  The client stores the URL, so the host can change later without touching installed servers. A mirror URL may be added to the config.
- Not release assets: every publish would be a release with a tag, which brings the repository-version noise back, and there are no cache
  headers.
- Pages holds the index, its signature and the assets. It does **not** hold package contents (a Pages deploy replaces the whole site).
- The index is fetched with an ETag on a timer by the server, which emits an event; the update chip and the top-bar count follow the event,
  not a poll in the browser (the marketplace issue "The package index refreshes by itself").
- The domain is not usable before 0.13 starts; until then the plan and the index format are written against it.

## Trust and tiers

| Tier | Repository | Signed by | Shown as |
| --- | --- | --- | --- |
| Official | `hobnix/official` | key shipped in the core (`config/trusted-keys/`) | Official |
| Verified | `hobnix/community` | the hobnix CI key, after a maintainer reviewed the pull request | Verified |
| Community | any repository added with `hs pkg repo add <index-url>` | its own key, trusted for that repository only | Unverified |

- The **signature moves from release tags to the index.** One signature covers every entry and its tree hash. `hs pkg` verifies the index
  first, then the tree hash of each fetched package, and refuses anything else.
- **Verified** works like Flathub: the author keeps the code in their own repository, a manifest in `hobnix/community` pins a commit, a
  maintainer reviews that commit, CI signs the index. A new commit is a new review.
- **Community:** adding a repository shows its URL and signer fingerprint and the user types the repository name to confirm. Updates show
  the diff (manifest, command rows, web declaration, scripts) and ask first; `--yes` does not skip that for a diff that touches
  `commands.tsv`, `[web.*]` or a new `needs`. Nothing is downloaded or enabled by itself.
- The signing key lives in a protected GitHub environment usable only from the main branch. Later an offline root key signs a rotating CI
  key, so a CI leak does not lose the root of trust. A package name that exists in two repositories is refused for the second one.
- Everything else in docs/PLAN-packages.md "Trust" stays.

## Names

Qualified names for everyone: `repo/name` always works in the CLI and the web interface, and a bare `name` means the official package and
only that.

- `hs pkg install jellyfin` is `official/jellyfin`; `community/metrics-extra` and `acme/cool-app` name packages of other repositories,
  where `acme` is the alias of that repository **on this server**.
- The alias is local, chosen when the repository is added and stored in `machine.toml` (like a Flatpak remote name). The index may suggest
  an `id`, which the add dialog offers as the default; the user can change it, and a clash with an existing alias is refused when adding.
  A repository never decides its own name on a server.
- `official`, `community`, `core` and `local` are reserved aliases.
- A bare name never falls back to another repository: if it is not in official the command fails and suggests `community/<name>` where it
  exists. A repository added later cannot change what a bare name means.
- Trust is tied to the signer fingerprint, not to name or alias. `installed.toml` records alias and fingerprint, so a changed key shows
  as a changed repository even under the same alias.
- All three tiers work the same in the CLI; the tier shows as a label (Official, Verified, Unverified), not as a different syntax.
- **Dependencies stay inside what a tier may trust** (against dependency confusion): official needs only official; community needs
  official and community; a third-party package needs its own repository and official. Blueprints follow the same rule. Inside a
  repository `foo` or `self/foo` means the same repository; the index stores the repository reference, not the local alias, so a package
  behaves the same whatever alias a server uses.
- **Renames:** an index entry may carry `renamed_from = ["old-name"]`, so a package renamed in the retouch pass (docs/PLAN-package-names.md)
  updates on servers that have the old name installed instead of showing as a new package.

## What the core is

The core keeps: `hs` and the registry loader, `hs pkg` (index, fetch, verify, install), `scripts/lib/ui.sh` and the other libraries that make
up the package API, the schema and the config merge, the Nix glue that loads modules, the installer, and the generic web shell and its
renderers. It knows no capability by name.

Everything else is a package, including storage, incus, samba, network, backup, encryption, vault, tailscale, vps and the edge roles. A VPS
that only routes traffic is core plus tailscale plus the edge capabilities.

For this each package brings its whole surface:

- its **command rows** (today in `scripts/lib/registry.tsv`; as `commands.tsv` already works for extensions), so `hs help` and the web tabs
  show only what is installed;
- its **config keys**; the schema generator merges them, so `config/schema.toml` no longer holds keys that belong to a module;
- its probes (`hs smoke`), guide, changelog entries and web declaration;
- `needs` and `provides` between packages (`backup` needs `storage`). The installer and `hs pkg` resolve them and refuse a removal that
  breaks a dependent.

Capabilities are NixOS modules (`default.nix`, `options.nix`, `nix-api-level`). The system is a plain, non-flake NixOS configuration, so
they reach the core the way ADR 0017 (rules 8 to 12) already decided: **vendoring**. `hs pkg install|update|remove` copies the verified
package tree into `/etc/nixos/vendor/capabilities/<name>/` and records name, version, commit and tree hash in `capabilities.lock`; the
evaluation stays pure and `default.nix` asserts the hash. This plan changes what the lock line is made from (the index entry and its tree
hash instead of a release tag) and nothing else in that mechanism. `nix-api-level` and `requires_core` guard the pair. Packages the core refers to by name today (`docker` as a need, `zoraxy`, `domain`, `monitoring`, `ntfy`)
are packages with `core = true` in the index: a core change that breaks them fails CI, and a blueprint that needs them pulls them.

**Removing a capability never destroys data.** Disabling `storage` on a server with pools is a destructive command: show a plan, make the
user type the name of the thing that changes. Removing a package means it stops being managed, not that what it managed is wiped.

## Blueprints

A blueprint is a package with `kind = "blueprint"`: a list of packages plus preset config (`media-server` pulls storage, incus, samba and
the recipes it needs; `vps-edge` pulls tailscale and the edge roles). The installer asks for a blueprint or for capabilities one by one and
installs nothing that was not chosen. Blueprints live in `official` and in the community tier. The presets that are in the core today
become blueprints.

## CI

- Core CI runs a **core-only** profile and a **vps** profile on every change, so the core cannot start to depend on a capability again.
- Core and `official` test as a pair (`requires_core`, `nix-api-level`); a change in either repository runs the other's tests on the pinned
  counterpart.
- `official` CI builds the index, runs `python3 scripts/pkg.py validate`, and signs only on the main branch.

## Order of work

1. Rename `hobnix/server` to `hobnix/core` (GitHub redirects the old URL; check that `hs update` and the installer do not hardcode the old
   name; update docs, CI badges and board links). Never create another repository called `server`.
2. Index format, CI that builds and signs it, `hs pkg` reading the index and fetching by tree hash, the timer and the event.
3. Per-package registry rows, config keys, probes and web declarations, so the core stops hard-coding capabilities. Target: the vps profile.
4. Merge `recipes`, `extensions` and `capabilities` into `official`; the capabilities move one by one, vendored (ADR 0017), starting with the
   pilot (#225).
5. Blueprints and the installer choice; core-only and vps CI profiles.
6. `hobnix/community` and the verified tier; the assets in the index feed the marketplace (0.14).

Steps 1 to 3 solve the versioning problem; 4 to 6 are the repository layout and the community side. Step 4 is the risky one (NixOS build,
installer) and is "Not tested on hardware yet." until it runs on a real server.

## Open points

- Which capability is the pilot (`tailscale` or `metrics`; a small one with few dependants).
- Whether `base`-like groups are only blueprints or also a `group` field in the index (start with blueprints only).
- Channels: the core already has `updateChannel` (stable, beta; docs/PLAN-channels.md) and ADR 0017 extends it to capabilities. With one
  version per package the natural fit is one index per channel (or a `channel` field per entry), a server reading the index of its
  channel. Decide when step 2 starts, after reading the PLAN-capabilities-repo.md steps that are already built; do not drop what exists.
- Whether a mirror of the index is shipped in the core as a fallback URL.
- A second index host (for availability) once the first one is in use.
- Restricted web access through the local proxy: expose only parts of the web interface (for example a user's self-service page, or
  start and stop of incus and docker) with manager and viewer modes, so not the whole server is reachable. An idea of the owner; it touches
  the web login and roles, so it needs its own design and is not part of 0.13. "Admin pages are never public" stays the rule.
- Rewriting packages (and maybe `hs`) in Rust: an idea for after the move, one package and one version at a time. Depends on how the
  package API (`_lib.sh`, `ui.sh`) looks by then, because that is the contract a package is written against. No decision.
