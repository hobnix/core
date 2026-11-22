# Package registry: a signed index over git, a core that is only the framework

Status: design, decided with the owner on 2026-11-22; milestone 0.13 "Package Registry" (before the marketplace, 0.14). Nothing is built yet.
It replaces "What stays in the core", the repository list and the tag-based version rule in docs/PLAN-packages.md, and the plan of the
closed milestone 0.5 (`hobnix/capabilities`, optional-only move, release channels).

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

Capabilities are NixOS modules (`default.nix`, `options.nix`, `nix-api-level`). They reach the core as **flake inputs** of
`hobnix/official`, pinned by commit in `flake.lock` (Nix checks the content hash); the index names the commit to pin. `nix-api-level` and
`requires_core` guard the pair. Packages the core refers to by name today (`docker` as a need, `zoraxy`, `domain`, `monitoring`, `ntfy`)
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
4. Merge `recipes`, `extensions` and `capabilities` into `official`; the capabilities move one by one as flake inputs, starting with the
   pilot (#225).
5. Blueprints and the installer choice; core-only and vps CI profiles.
6. `hobnix/community` and the verified tier; the assets in the index feed the marketplace (0.14).

Steps 1 to 3 solve the versioning problem; 4 to 6 are the repository layout and the community side. Step 4 is the risky one (NixOS build,
installer) and is "Not tested on hardware yet." until it runs on a real server.

## Open points

- Which capability is the pilot (`tailscale` or `metrics`; a small one with few dependants).
- Whether `base`-like groups are only blueprints or also a `group` field in the index (start with blueprints only).
- Channels (stable and beta) per package: not now; one stream. A `channel` field can be added to the index later without a format break.
- Whether a mirror of the index is shipped in the core as a fallback URL.
- A second index host (for availability) once the first one is in use.
- Restricted web access through the local proxy: expose only parts of the web interface (for example a user's self-service page, or
  start and stop of incus and docker) with manager and viewer modes, so not the whole server is reachable. An idea of the owner; it touches
  the web login and roles, so it needs its own design and is not part of 0.13. "Admin pages are never public" stays the rule.
- Rewriting packages (and maybe `hs`) in Rust: an idea for after the move, one package and one version at a time. Depends on how the
  package API (`_lib.sh`, `ui.sh`) looks by then, because that is the contract a package is written against. No decision.
