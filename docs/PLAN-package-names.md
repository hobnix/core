# Package names: what every package is called today, what it is for, and a proposed name

Status: draft for the owner to correct, 2026-11-22. Part of milestone 0.13 (docs/PLAN-registry.md, "Names" and the retouch issue). A package
id is its identity in the index, so a name is cheapest to change **before** the move into `hobnix/official`; after it, a rename needs
`renamed_from`. Nothing here is decided until the owner marks it.

## Rules for a name

- Lowercase, hyphens, no repository or kind prefix (`jellyfin`, not `recipe-jellyfin`).
- **Unique across all kinds in one repository.** Today `docker` is both a capability and a recipe; that cannot stay (see the table).
- A recipe is named after the app it installs (`radarr`); a capability after the function it gives (`reverse-proxy`, `backup`).
- A family shares a prefix (`edge-mail`, `edge-ports`); a name never repeats what the kind already says.
- A name says what it is for, so someone who has not read the docs can guess (`gateway` does not; `local-names` does).
- Renames are listed in the index with `renamed_from`, so installed servers follow.

## Capabilities (21 today, NixOS modules)

| Now | What it is for | Proposed | Note |
| --- | --- | --- | --- |
| `ad` | Active Directory: domain users, Domain Admins sign in | `active-directory` | `ad` is short but unclear. Same family as recipe `domain` and extension `ad-selfservice`: decide whether they become one package with parts. |
| `backup` | restic to the backup disk, restore drills; needs storage | keep | |
| `dashboard` | tiles for the services | extension, later | Owner leans to an extension: the core stays light. Today it is code inside the web bundle (`web/src/dashboard/`, used by `App.svelte` and `Services.svelte`), so it can only leave once a package can place its own page and the block list covers tiles (milestone 0.12, #473). Until then it stays; a fresh server needs a fallback landing page. |
| `docker` | Docker host with a web page to manage it | `docker-host` or merge | Clashes with recipe `docker`. They look like one thing: merge into one package, or keep two with different names. |
| `docs` | guides and command reference in the web interface | core | Decided with the owner 2026-11-22. |
| `edge-mail` | public mail entry (MX) on the VPS | keep | Family `edge-*`; a blueprint `vps-edge` pulls them. |
| `edge-ports` | public game and call ports | keep | |
| `edge-status` | status document of the edge node | keep | |
| `edge-watcher` | outside watcher of the home server | keep | Only one of the four without `requires = ["tailscale"]`; check why. |
| `gateway` | Traefik owns port 80: a local name `<label>.<site>.<domain>` per service, by Host header; with `passthrough` also outside domains | `local-proxy` or keep | Not DNS: it answers no DNS queries. It only checks that `*.<site>.<domain>` points at this server and holds the ACME DNS-01 token. `local-proxy` is already the name of its slot in the reverse-proxy interface (`provides = ["local-proxy"]`). `local-names` and `dns` both mislead. Absorbs extension `passthrough`. |
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
| `docker` | Docker apps (compose) with Arcane or Portainer | see capability `docker` | Name clash. |
| `domain` | the domain controller, this server joined to it | see `active-directory` | The installer of that capability. |
| `monitoring` | Grafana and Loki: history of load, disks, containers, logs | `grafana` | Names the app; Loki is part of it. Needs `metrics`. |
| `upload-storage` | file sync and upload server (Seafile or ownCloud) | `file-sync` | Not an app name, but it holds two apps; `storage` in the name is confusing next to the capability `storage`. |
| `homeassistant` | Home Assistant in its own VM | `home-assistant` | The app's own spelling. |
| `paperless-ngx` | scanned documents, OCR, search | `paperless` | The `-ngx` is the project's, not what people say. |
| `matrix-hook` | Radarr, Sonarr and others post events to a Matrix room | `matrix-notify` | Says what it does. |
| `steamos`, `sunshine` | game streaming from the server (Steam Remote Play; Moonlight) | decide | Overlap: check whether they are one package with two modes. |
| `catalyst-node`, `catalyst-panel`, `pelican` | game server panels | keep | Three panels for the same job: check whether all three stay. |
| `zoraxy` | the reverse proxy for public names | keep | The provider of `reverse-proxy`; a `core = true` hard case in the plan. |
| `claude-vm`, `paperclip` | AI agent machines | keep | Check whether `claude-vm` should be a generic `dev-vm`. |
| `droppedneedle` | discover music and ask for albums (formerly MusicSeerr) | keep | Renamed once already. |

The rest are unchanged: `audiobookshelf`, `authentik`, `bazarr`, `bulwark`, `cloudflared`, `configarr`, `immich`, `jellyfin`, `lidarr`,
`livekit`, `maintainerr`, `navidrome`, `ntfy`, `prowlarr`, `qbittorrent`, `radarr`, `sabnzbd`, `seerr`, `sonarr`, `stalwart`, `synapse`,
`tdarr`, `uchiyomi`, `uptime-kuma`.

## What the answers change

- Decided 2026-11-22: `docs`, `live-state` and `notifications` stay in the core; `dashboard` leaves as an extension once packages can place
  their own page; `passthrough` is built into the gateway package.
- Still open: the name of `gateway`; the `docker` name clash; whether the Active Directory family becomes one package; the overlaps
  between `steamos` and `sunshine` and between the three game server panels.
- Counts above were read on 2026-11-22 from `capabilities/*/capability.toml` and the indexes of hobnix/recipes and hobnix/extensions.
- Not tested on hardware yet: nothing here changes behaviour; a rename is checked in the retouch pass of each package.
