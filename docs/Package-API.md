# Package API

What a package (`package.toml`) may say to the core, and from which API level. The level is the number in `scripts/lib/api-level` (`hs pkg api`);
a package states the lowest level it needs in `requires_core = ">=N"` and the core refuses one that needs more (ADR 0008, rule 4). The design
is in [PLAN-app-lifecycle](PLAN-app-lifecycle.md) (Q4 and Q5); the states of a package are in ADR 0027.

**These field names are a contract.** The Apps and Marketplace pages and the later steps of the lifecycle plan (0.11, 0.13) read them. The field
names are stable for milestones 0.11 and 0.13: a field is renamed or removed only with an API level bump and one level in which the old name still
works. The checks live in `scripts/lib/pkg_app.py` (called by `scripts/pkg.py`); the level is 11. Adding an optional key
is a bump too, because an older core would refuse the unknown key.

## Level 9: the app contract and store fields

All keys are optional. A manifest written before level 9 validates unchanged. A package that uses any of them states `requires_core = ">=9"`
(`pkg.py validate` names it when it does not). They belong to recipes first; an extension that owns a service may use them later.

### Store fields (top level of package.toml)

| Key | Value | Rule |
| --- | --- | --- |
| `description`, `description_de` | text | one paragraph, at most 500 characters |
| `icon` | `"ph:<name>"` or `"<file>.svg"` | a Phosphor name, or an SVG in the package folder: at most 20 KB, no `<script`, no `on...=` handler, no external reference |
| `category` | id | one of `config/package-categories.toml`: media files network home games tools dev admin |
| `upstream` | address | `https://...` |
| `app_version` | text | the app release this package version pins; set at release time. The running version is read on the server, never looked up |
| `screenshots` | list of paths | at most 5, `.png` or `.webp` inside the package, each at most 300 KB |

The package index (`index.toml`) carries `icon`, `category` and `app_version` as well (optional); `pkg.py repo-check` compares them with the
package. Description, pictures and `[app.uses]` are read from the package itself.

**What the Marketplace does with a recipe's needs** (`hs sys pkg fit`, no key of its own): `[app.uses] ram_mb` (MiB) is compared with the
server's memory (above the total: does not fit; above what is free now: a note), `disk_gb` (GiB) with the free space of the storage pool where
a new container's disk goes (above it: does not fit), `[app.uses] gpu` or `uses = ["gpu"]` with the graphics card (never in the way), and
`needs` with what is set up. A key that is absent or 0 is "not stated"; a recipe with neither `ram_mb` nor `disk_gb` is never shown as
fitting. State what the app needs to run well, not the smallest value it starts with. Not tested on hardware yet.

### `[app]` tables

```toml
[app]
instances = "one"                 # one | many; default one
autostart = true                  # default of the instance's boot flag
[app.health]
check = "http"                    # container (default) | tcp | http
port = 8096                       # tcp and http: required
path = "/health"                  # http only; starts with /
timeout = 5                       # seconds, 1 to 60
[app.backup]
mode = "instance"                 # instance (default) | paths | none
paths = []                        # mode paths: absolute paths inside the instance, at least one
dump = "postgres-compose"         # optional dump kind, "-" for none
[app.routes]
default = "web"                   # must name one of the routes below
web = { port = 8096, scheme = "http", exposure = "private-ok" }   # scheme http|https; exposure never-public|private-ok|public-ok
[app.update]
kind    = "pin"                   # pin | os | manual
default = "notify"                # automatic | notify | pinned
[app.version]
source = "image-tag"              # image-tag | http-json (path + pointer, both start with /) | exec (command = ["word", ...])
[app.remove]
keeps = ["data volume", "share"]  # plain English, shown in the Remove dialog
data  = ["/var/lib/app"]          # what "delete the data" deletes
[app.uses]
ram_mb = 4096
disk_gb = 20
ports = [2283]
gpu = false
```

`hs pkg install` and `update` refuse the whole package (error code `pkg.rows`) when `[app]` or anything under `[app.routes]` is not valid: a
bad route name, `exposure`, `port`, `scheme` or `admin` value is refused, never skipped. Not tested on hardware yet.

An unknown key in any `[app]` table is an error. A route that is public-ok and marked `admin = true`, or whose container and port are in
`ADMIN_TARGETS` of `scripts/services.py`, is refused: a manifest cannot make an admin page public.

**How a package protects its own admin page.** A package that has a management page (a Docker manager, a dashboard, a panel) declares
that route `exposure = "never-public"`, or marks it `admin = true`. `scripts/services.py` then refuses a public route for it, with no
entry in `ADMIN_TARGETS` needed (tests/services.sh, "never-public gets no route"). `ADMIN_TARGETS` is only the built-in list for the apps
the core already knows. **What no guard can catch** is a package that declares its own admin page `public-ok` without the mark and is not
on that list: the core cannot tell an admin page from a public one. The protection there is the signed repository, the diff shown before
an update (a changed `[app.routes]` is part of it) and the typed confirmation that makes a route public.

### How strict

| Package | Without the contract / store fields |
| --- | --- |
| a recipe flagged `core = true` in the index with `requires_core = ">=9"` | error: `[app.health]`, `[app.backup]`, `[app.routes]`, `[app.update]`, `[app.remove]` and the store fields `description`, `icon`, `category`, `app_version` are required |
| a recipe that carries any store field | warning until `description`, `icon`, `category` and `app_version` are all there |
| a core recipe that still says a lower level, any other recipe | validates; `pkg.py repo-check` prints a warning on stderr |

`pkg.py validate --warn` prints the same warnings for a tree. `pkg.py check-draft` (the package builder) reports errors only.

Not tested on hardware yet. The fields are validated; the server does not read them until the later steps of the lifecycle plan.

## Level 10 (milestone 0.8): protocol, timeout and service keys

The core validates these keys (`scripts/lib/pkg_protocol.py`, called by `pkg.py validate`, `repo-check` and `check-draft`) and, since step 2 of
[PLAN-extensions-access](PLAN-extensions-access.md), **runs the commands** of a package that says `protocol = [1]`. The `[service]` table is
still only validated (the service runner is step 4). A package without these keys keeps the shell contract and validates unchanged (ADR 0010 rule 10).

| Key | Value | Rule |
| --- | --- | --- |
| `protocol` | `[1]` | the command protocol versions the package speaks (ADR 0010); `[1]` is the only value; every row of `commands.tsv` of the package runs through the protocol |
| `[service]` `exec` | `"@/<file>"` or `"scripts/..."` | the service's program, same rule as a `commands.tsv` script: a file in the package or a path under `scripts/`, no `..`, not absolute; required |
| `[service]` `subscribe` | list of event kind globs | lower-case words, dots and `*`; may be empty (a pure collector) |
| `[service]` `health_interval` | seconds | whole number from 5 to 300 (ADR 0011 rule 1; default 30) |
| `timeout:<seconds>` | a flag in column 7 of a `commands.tsv` row | whole number from 1 to 3600 (ADR 0010 rule 6; the dispatcher's default is 30), at most once per row |
| `confine` | a flag in column 7 of a `commands.tsv` row | opt in: the dispatcher runs this one command through `systemd-run` with the properties of the declared `permissions` (same mapping as the service unit, ADR 0014). The manifest must have `protocol = [1]` and a `permissions` list (`[]` is allowed); otherwise `pkg.py validate` refuses it. Partial: see below. |

An unknown key in `[service]`, a wrong type or a value out of range is an error. A manifest that uses `protocol` or `[service]` must state
`requires_core = ">=10"` or higher (decision D9: the API level is the promise that the core can run it); `pkg.py validate` names the missing level.

### How a protocol row runs

`scripts/lib/registry-load.sh` gives every row of a package with `protocol` the flag `proto`; `scripts/lib/hs.sh` then runs the row's script
through `python3 -I scripts/lib/ext_proto.py dispatch` instead of starting it. The script column is the extension program (`@/demo.py`; `.py` runs
with python3, `.sh` with bash, anything else directly).

| Part of the request | Comes from |
| --- | --- |
| `command` | the words of the row after the package name (placeholders such as `<x>` end the list) |
| `argv` | the arguments the dispatcher builds for the row (typed arguments, fixed arguments of the row) |
| `lang`, `caller` | `HS_LANG` / `LANG` (`en` or `de`); `HS_CALLER` (`ui` and `job` = `web`, `timer` and `boot` = `boot`, else `cli`) |
| `timeout_ms` | the row's `timeout:` flag, else 30 s |

The core renders `result.data` (the extension does not format output):

- a list: one line per item; an item that is a list is its cells joined by a tab, an item that is an object is its values in key order;
- an object: one line `key<TAB>value` per member; a scalar: itself;
- an empty string, `null` or `[]` is `-`; a nested value is compact JSON; tabs and line breaks inside a cell become a space.

A `user` row prints `result.text` when the extension sent one and else the rendered `data`; progress and log text go to stderr. A `sys` row prints
only the rendered `data` on stdout (the machine-readable contract of `hs sys ext ...` does not change). A failed call prints the error message on
stderr and exits 1 (the extension said `ok=false`), 124 (timeout), 130 (cancelled), 70 (protocol error) or 69 (the program did not start). A timeout
stops the whole process group of the extension: SIGTERM, five seconds of grace, then SIGKILL. Events sent by an extension are not used yet (step 5).

A demo package is `protocol-demo` in the extensions repository. Tests: `tests/ext-proto.sh`.

Not tested on hardware yet.

## Roles of web entries (milestone 0.8, step 18)

Every `[[web.reads]]` and `[[web.changes]]` entry of an extension's `capability.toml` may carry `role`. It is the least role of the web interface
that may use the entry (ADR 0012, decision D13). `pkg.py validate` (`scripts/lib/pkg_roles.py`) refuses any other value.

| Key | Value | Rule |
| --- | --- | --- |
| `role` | `"viewer"`, `"app-manager"` or `"admin"` | optional; **no `role` means `admin`**, so a manifest written before roles stays admin-only |

The web interface applies the higher of this role and the role of the core `sys` row the entry calls. A package can therefore make something
stricter, never wider than the core allows. A refused call is a 403 that names both roles and runs nothing; a token never has more than its
owner's role. Not tested on hardware yet.

## Confined commands (`confine`, partial)

A command row with the flag `confine` is started as `systemd-run --pipe --wait --collect --quiet --property=... -- <program>`; the properties are the
ones a service of the same package gets (`scripts/lib/ext_confine.py`): `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`,
`NoNewPrivileges=yes`, no capabilities, `PrivateDevices=yes` unless `devices:gpu`, `ReadWritePaths=` from `fs.write` (plus `/var/lib/hs/ext-svc`),
`ReadOnlyPaths=` from `fs.read`. Without `systemd-run`, without `permissions` or with a path that is not allowed the command does **not** run
(exit 69); it is never started unconfined as a fallback.

It does not cover: reading the file system (`fs.read` lists, it does not restrict), the network (`net` is declared only), calls to `hs`, `incus`
and `systemctl` (a confined command that calls them still acts as root through them), and secrets. Commands without the flag run as root and
unconfined, as before. The install and update prompts say this in the same words. A confined command cannot write `/etc/hs` or other state unless `fs.write` lists it: list the path or leave the row unconfined (ADR 0014, D7).
Not tested on hardware yet: only a fake `systemd-run` that records its arguments has run (tests/ext-confine.sh).

## Level 11 (0.13): blueprints

`kind = "blueprint"` (docs/PLAN-registry.md "Blueprints"): an ordered package list plus fill-only config, no script and no Nix. A blueprint says
`requires_core = ">=11"`, so a core that does not know the kind (level 10 or lower) refuses it instead of installing it. Validated by
`scripts/lib/pkg_blueprint.py`; a blueprint is applied (`hs blueprint apply`, a later release), never installed.

## What the core refuses (hobnix/core#1072)

All rules fail closed. Not tested on hardware yet.

1. A package row never shadows a core row: a first word that a core command uses is refused, and `hs pkg install` and `update` then refuse the
   whole package, so nothing stays half installed.
2. A package never takes a first word or an option key that another package or the core has. A clashing option key leaves out all options of that
   package.
3. No public route to an admin page: an `[app.routes]` entry with `exposure = "public-ok"` on an admin page is refused at install.
4. A `[[probe]]` of `hs smoke` must name a row of the same package with the flag `reads`, or a `changes` row when the words end in
   `--dry-run` and that word reaches the script (args `-` or a `{rest}` token). Any other probe is skipped and counted as a failure.
   This does not prove that the command only reads. This catches mistakes of a package, not a hostile one: the package sets the flags and names the script itself.
5. A `sys` row with the word `start` needs its twin with `plan`. Asking the person to type the name before a destructive change stays a review
   rule.
