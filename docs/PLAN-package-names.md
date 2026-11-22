# Package names: what every package is called today, what it is for, and a proposed name

Status: draft for the owner to correct, 2026-11-22. Part of milestone 0.13 (docs/PLAN-registry.md, "Names" and the retouch issue). A package
id is its identity in the index, so a name is cheapest to change **before** the move into `hobnix/official`; after it, a rename needs
`renamed_from`. Nothing here is decided until the owner marks it.

## Rules for a name

- Lowercase, hyphens, no repository or kind prefix (`jellyfin`, not `recipe-jellyfin`).
- **Unique across all kinds in one repository.** Today `docker` is both a capability and a recipe; that cannot stay (see the table).
- A recipe is named after the app it installs (`radarr`); a capability after the function it gives (`reverse-proxy`, `backup`).
- **One recipe, one app.** A recipe that offers a choice of apps is split (`upload-storage` into `seafile` and `owncloud`).
- A family shares a prefix (`edge-mail`, `edge-ports`); a name never repeats what the kind already says.
- A name says what it is for, so someone who has not read the docs can guess (`gateway` does not; `local-names` does).
- Renames are listed in the index with `renamed_from`, so installed servers follow.

## Capabilities (21 today, NixOS modules)

| Now | What it is for | Proposed | Note |
| --- | --- | --- | --- |
| `ad` | Active Directory: domain users, Domain Admins sign in | `active-directory` | `ad` is short but unclear. Same family as recipe `domain` and extension `ad-selfservice`: decide whether they become one package with parts. |
| `backup` | restic to the backup disk, restore drills; needs storage | keep | |
| `dashboard` | tiles for the services | extension, later | Owner leans to an extension: the core stays light. Today it is code inside the web bundle (`web/src/dashboard/`, used by `App.svelte` and `Services.svelte`), so it can only leave once a package can place its own page and the block list covers tiles (milestone 0.12, #473). Until then it stays; a fresh server needs a fallback landing page. |
| `docker` | Docker host with a web page to manage it | keep, slimmer | Decided: the capability replaced the recipe `docker`, so the recipe is not moved and the name is free. Packages that `needs = ["docker"]` resolve to the capability. Decided 2026-11-22: it loses the manager variants (Arcane, Portainer) and is only the Docker host container; each manager becomes its own recipe (`arcane`, `portainer`) that `needs` `docker`, so a person adds one only if wanted, next to the web interface's own Docker controls. See the notes under "What the answers change". |
| `docs` | guides and command reference in the web interface | core | Decided with the owner 2026-11-22. |
| `edge-mail` | public mail entry (MX) on the VPS | keep | Family `edge-*`; a blueprint `vps-edge` pulls them. |
| `edge-ports` | public game and call ports | keep | |
| `edge-status` | status document of the edge node | keep | |
| `edge-watcher` | outside watcher of the home server | keep | Only one of the four without `requires = ["tailscale"]`; check why. |
| `gateway` | Traefik owns port 80: a local name `<label>.<site>.<domain>` per service, by Host header; with `passthrough` also outside domains | `local-proxy` (decided) | Not DNS: it answers no DNS queries. It only checks that `*.<site>.<domain>` points at this server and holds the ACME DNS-01 token. `local-proxy` is already the name of its slot in the reverse-proxy interface (`provides = ["local-proxy"]`). `local-names` and `dns` both mislead. Absorbs extension `passthrough`. |
| `incus` | containers and VMs, VLAN profiles; needs storage | keep | |
| `live-state` | collector that feeds the web interface | core | Decided with the owner 2026-11-22. |
| `metrics` | Prometheus, node and smartctl exporters on the host | keep | Grafana is already apart (recipe `monitoring`). Pilot candidate (#225), moved unchanged first. |
| `network` | router connection, fixed addresses for instances (UniFi) | `router` | Providers (`unifi`) stay inside. |
| `notifications` | channels (ntfy and others) | core | Decided with the owner 2026-11-22; `hs health` uses it. |
| `reverse-proxy` | publishes the services (providers: Zoraxy, Traefik) | keep | The interface name; Zoraxy and Traefik are its providers. |
| `samba` | shares and network discovery; needs storage | keep | |
| `storage` | ZFS or SnapRAID pools, shares, encrypted disks | keep | |
| `tailscale` | private access to this server | keep | |
| `testlab` | builds the installer ISO and runs it in a nested VM; needs incus | not a package | A developer tool; stays in the core repository under `scripts/dev` or in a separate dev repository. |
| `vps` | the VPS as the front door | keep or `vps-front-door` | Check that its title and name say the same. |

## Extensions (4 today)

| Now | What it is for | Proposed | Note |
| --- | --- | --- | --- |
| `ad-selfservice` | domain users change their own password | keep | Family of `active-directory`. |
| `games` | game PCs (wake, list) and the Game streaming page | `game-pcs` | `games` is confused with game servers (`pelican`, `catalyst-*`). |
| `passthrough` | outside domains to reverse proxies on the LAN | built into `gateway` | It requires `gateway`, writes route files into its folder, reads its public-port options and has no Nix module of its own. Becomes a part of that package. Its `ext passthrough` and `sys ext passthrough` rows are a contract with the web interface: keep them with `legacy:<new>` and migrate servers that have the extension enabled (`renamed_from` / `replaces` in the index). |
| `posters` | posters drawn from the command line or the web | keep | |

## Recipes (40 today)

Most are named after their app and stay as they are. Only the ones with a question:

| Now | What it is for | Proposed | Note |
| --- | --- | --- | --- |
| `docker` | Docker apps (compose) with Arcane or Portainer | removed | Replaced by the capability `docker`; not moved to official. |
| `domain` | the domain controller, this server joined to it | part of `active-directory` | Its "controller" mode; not moved as a recipe (see "What the answers change"). |
| `monitoring` | Grafana and Loki: history of load, disks, containers, logs | `grafana` | Names the app; Loki is part of it. Needs `metrics`. |
| `upload-storage` | file sync and upload server (Seafile or ownCloud) | `seafile` and `owncloud` | Decided: a combined recipe is split, one recipe per app. The name `upload-storage` goes away (it was also confusing next to the capability `storage`). |
| `homeassistant` | Home Assistant in its own VM | `home-assistant` | The app's own spelling. |
| `paperless-ngx` | scanned documents, OCR, search | `paperless` | The `-ngx` is the project's, not what people say. |
| `matrix-hook` | Radarr, Sonarr and others post events to a Matrix room | `matrix-notify` | Says what it does. |
| `steamos` | game streaming with Steam Remote Play | keep | Independent of `sunshine` (its script only says it replaces it). |
| `sunshine` | Moonlight streaming | removed | Not working (the parked recipe hung in Xorg); not moved to official. |
| `catalyst-node`, `catalyst-panel` | game server panel | removed | Not moved to official. |
| `pelican` | game servers with a web panel (Panel and Wings, two containers) | keep, touch up | The owner is not happy with it; a retouch item. It is one recipe today; the retouch decides whether Panel and Wings become two packages. |
| `zoraxy` | the reverse proxy for public names | keep | The provider of `reverse-proxy`; a `core = true` hard case in the plan. |
| `claude-vm`, `paperclip` | AI agent machines | keep | Check whether `claude-vm` should be a generic `dev-vm`. |
| `droppedneedle` | discover music and ask for albums (formerly MusicSeerr) | keep | Renamed once already. |

The rest are unchanged: `audiobookshelf`, `authentik`, `bazarr`, `bulwark`, `cloudflared`, `configarr`, `immich`, `jellyfin`, `lidarr`,
`livekit`, `maintainerr`, `navidrome`, `ntfy`, `prowlarr`, `qbittorrent`, `radarr`, `sabnzbd`, `seerr`, `sonarr`, `stalwart`, `synapse`,
`tdarr`, `uchiyomi`, `uptime-kuma`.

## What the answers change

- Decided 2026-11-22: `docs`, `live-state` and `notifications` stay in the core; `dashboard` leaves as an extension once packages can place
  their own page; `passthrough` is built into the gateway package.
- Decided the same day: `gateway` becomes `local-proxy` (its `provides` entry stays `local-proxy`: service descriptors say
  `local-proxy = true`, so changing it would touch every recipe); the `docker` recipe, `sunshine`, `catalyst-node` and `catalyst-panel`
  are not moved; `steamos` and `pelican` stay, `pelican` gets a retouch.
- Decided the same day: `upload-storage` is split into `seafile` and `owncloud`.
- Active Directory, the shape (owner's idea, 2026-11-22): the same pattern as the `docker` capability, which installs a container
  and offers variants. `ad` (this server is a member: Samba joins, winbind, Kerberos, Domain Admins sign in; no module of its own, on
  exactly when `adDomain` is set) and recipe `domain` (the domain controller container) become one capability, `active-directory`, with a
  mode chosen when it is turned on: **controller** (a domain controller container here, system-labelled so it cannot be deleted by
  accident, and this server is a member of the domain; today's `domain`) or **member** (join a domain without a controller of its own).
  A controller either **creates** a new domain or **joins an existing one as an additional controller**: the owner runs two servers that
  are each a controller and a member of the same domain and replicate to each other (dc1 and dc2). That setup is in use and **must keep
  working** (an acceptance criterion of the move; not checked here whether the recipe already does the replica case, or how). The DC container is
  installed by the capability, not by a separate recipe. `ad-selfservice` stays a small extension (`needs` the capability), renamed
  `active-directory-selfservice` so the family sorts together. Not `ad-host` and `ad-client`: there is one switch (`adDomain`) and the
  commands `hs user`, `hs dns` and `hs dc cert` serve both roles. Checked in the code: `ad` has no module and its notes name `domain` as the
  controller; not checked: whether a member-only join (for example a domain on a Windows server) works today. If it does not, "member" is
  only the second half of "controller" until the retouch adds it.
- Docker, the shape: the capability keeps the Docker host container and the `docker` service; the manager variants (`arcane`, `portainer`,
  `none`) go. Each manager becomes a recipe with `needs = ["docker"]`, never public like today. Three things to handle: (1) servers that
  have Arcane or Portainer through the variant (installs from before count as Arcane) must be migrated to the recipe with the volume and
  compose file kept, as the variant switch does today; (2) the "never public" guard: a manager recipe declares its route `never-public`, or `admin = true`
  on the route (both exist today: `[app.routes]` in docs/Package-API.md, tests/pkg.sh), and services.py then refuses a public route. The
  name list `ADMIN_TARGETS` stays as a built-in floor for the apps the core knows. What no guard can catch is a package that declares its
  own admin page `public-ok` without the mark; that is what the signed repository, the diff before an update and the typed confirmation
  are for; (3) the interface `provides = ["docker-manager"]` moves from the capability to the manager recipes.
- Counts above were read on 2026-11-22 from `capabilities/*/capability.toml` and the indexes of hobnix/recipes and hobnix/extensions.
- Not tested on hardware yet: nothing here changes behaviour; a rename is checked in the retouch pass of each package.
