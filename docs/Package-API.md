# Package API

What a package (`package.toml`) may say to the core, and from which API level. The level is the number in `scripts/lib/api-level` (`hs pkg api`);
a package states the lowest level it needs in `requires_core = ">=N"` and the core refuses one that needs more (ADR 0008, rule 4). The design
is in [PLAN-app-lifecycle](PLAN-app-lifecycle.md) (Q4 and Q5); the states of a package are in ADR 0027.

**These field names are a contract.** The Apps and Marketplace pages and the later steps of the lifecycle plan (0.11, 0.13) read them. The field
names are stable for milestones 0.11 and 0.13: a field is renamed or removed only with an API level bump and one level in which the old name still
works. The checks live in `scripts/lib/pkg_app.py` (called by `scripts/pkg.py`); the level is 10. Adding an optional key
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

An unknown key in any `[app]` table is an error. A route that is public-ok and marked `admin = true`, or whose container and port are in
`ADMIN_TARGETS` of `scripts/services.py`, is refused: a manifest cannot make an admin page public.

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
