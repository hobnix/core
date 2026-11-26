"""hs pkg new: start a package in a checkout of a package repository (docs/PLAN-packages.md). Standard library only.

  pkg.py new <name> --template recipe|extension|capability [--protocol shell|python] [--dir <path>] [--title <text>] [--title-de <text>]
         [--description <text>] [--description-de <text>] [--icon ph:<name>] [--category <id>] [--app-version <text>] [--instances one|many]

Writes <dir>/recipes/<name>/ (recipe), <dir>/extensions/<name>/ (extension) or <dir>/capabilities/<name>/ (capability) and appends
[package.<name>] to <dir>/index.toml, so that `pkg.py validate` (the folder linked as packages/ or capabilities/, as the repositories' CI
does) and `pkg.py repo-check <dir>` pass without edits. Never overwrites anything.
A recipe and an extension carry the store fields (docs/PLAN-app-lifecycle.md Q5: description, icon, category from
config/package-categories.toml, app_version; requires_core ">=11"), a recipe also the [app] contract tables (Q4) and `instances`.
A capability package carries neither (the checks refuse them there) and stays at level 1.
Output, read by scripts/pkg.sh only (not a contract with the web interface):
  done:    folder TAB <absolute package folder>, then one `file TAB <path inside it>` per file, then `index TAB <absolute index.toml>`; exit 0
  refused: error TAB <code> TAB <detail, - when none>; exit 2. Codes: usage, template, name, title, field (detail: the option), notrepo, exists, write
"""
import os
import re
import shutil
import tomllib

SUB = {"recipe": "recipes", "extension": "extensions", "capability": "capabilities"}
RESERVED = ("list", "enable", "disable")   # words of `hs ext`
VERSION = "0.1.0"
REQUIRES = {"recipe": ">=11", "extension": ">=11", "capability": ">=1"}   # the store fields and [app] tables came with API level 9

R_PACKAGE = '''# Manifest of a package (docs/PLAN-packages.md of the core). Raise version here AND in index.toml with every change.
name = "{name}"
version = "0.1.0"
kind = "recipe"
title = {q_title}
title_de = {q_title_de}
requires_core = ">=11"
audience = "generic"
permissions = []
needs = []
uses = []
runs = ["lxc"]
input = "none"
script = "run.sh"
{store}
# The app contract (docs/Package-API.md): what Apps shows and the Remove dialog offers. Delete a table to leave it out.
[app]
instances = {q_instances}
[app.health]
check = "container"
[app.backup]
mode = "instance"
[app.update]
kind = "manual"
default = "notify"
[app.remove]
keeps = ["the container and its data"]
data = []
[app.uses]
ram_mb = 1024
disk_gb = 5
ports = []
gpu = false
'''

R_RUN = '''#!/usr/bin/env bash
# recipe: {title}
# recipe.de: {title_de}
# kind: generic
# needs: -
# uses: -
set -euo pipefail

# What it does: creates the container "{name}" and runs one step inside it. Replace that step with the installation of your app, built
# from the helpers of the core (scripts/recipes/_lib.sh: ensure_container, step, in_ct, fetch_pinned, wait_page, declare_service, docs_hint).
# Rules: pin every download (version and sha256), print no raw command output, never read a secret from argv or the environment, never
# open a public route for an admin page. The header lines above and package.toml must agree (python3 <core>/scripts/pkg.py validate).
scripts=${HS_SCRIPTS:-$(dirname "$0")/../../scripts}
ct=${RECIPE_NAME:-{name}}
. "${HS_RECIPE_LIB:-$scripts/recipes/_lib.sh}"

if [ "${1:-}" = --dry-run ]; then
  say "Would:"
  say "$(t "  create the container '%s' (1024 MB RAM limit) unless it exists" "$ct")"
  exit 0
fi

ensure_container "$ct" 1024
step "$(t 'Set up %s' "$ct")"
in_ct "Checking the container" 'true'
box <<DONE
$(t 'Done: the container %s is ready.' "$ct")
$(docs_hint {name})
DONE
'''

R_GUIDE = '''# {title}

{title}. This guide installs it with two commands. Not tested on hardware yet.

## Before you start

- An installed server: see [Install](install.md).

## Install it

```bash
hs pkg install {name}
```

```bash
hs recipe {name}
```

The recipe creates the container `{name}` and sets it up. Running it again changes only what is not current.

## Check that it worked

- `hs ct list` shows the container `{name}` as running.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| The recipe stops with an error | a step inside the container failed | run `hs recipe {name}` again; `hs doctor` checks the server |

## Next

- [Containers and apps](containers-and-apps.md)
'''

X_PACKAGE = '''# Manifest of a package (docs/PLAN-packages.md of the core). Raise version here AND in index.toml with every change.
name = "{name}"
version = "0.1.0"
kind = "extension"
title = {q_title}
title_de = {q_title_de}
requires_core = ">=11"
audience = "generic"
permissions = ["web.read"]
{proto}{store}'''

X_CAP = '''# Manifest of the extension (docs/PLAN-extensions.md of the core): the commands are in commands.tsv, the scripts in this folder (@/file).
name = "{name}"
title = {q_title}
title_de = {q_title_de}
kind = "feature"
requires = []
provides = []
needs = []
# No NixOS module: scripts only. Off until `hs ext enable {name}` (no rebuild).
notes = "NOTES.md"
extension = true

# What the web interface may read while the extension is on: each read is a `sys ext {name} ...` row of commands.tsv.
[[web.reads]]
words = "list"
kind = "tsv"
ttl = 30
'''

X_COMMANDS = '''# Commands of the extension package "{name}" (docs/PLAN-extensions.md of the core). Same columns as scripts/lib/registry.tsv of the core:
# kind\tpath\tscript\targs\thelp\thelp.de\tflags
# Only rows under this package's own name (user: ext {name} ..., sys: sys ext {name} ...) are loaded, and only while the package is on.
user\text {name} list\t@/list.sh\tlist\tthe saved entries of {name}: name and value\tdie gespeicherten Einträge von {name}: Name und Wert\ttopic:system,reads
sys\tsys ext {name} list\t@/list.sh\t--list\tthe saved entries of {name} as data: name, value (- when empty)\t-
'''

X_LIST = '''#!/usr/bin/env bash
# help: the saved entries of {name}
# help.de: die gespeicherten Einträge von {name}
# args: list | --list
# The example command of the extension {name}: replace it with your own. It reads <state>/{name}/entries (name TAB value per line).
# --list (hs sys ext {name} list) = name TAB value, one row per entry, no header, nothing when there is none; an empty value is written -
# (machine readable: the web interface reads it; never change its shape once it is released). HS_STATE_DIR points tests at another folder.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
scripts=${HS_SCRIPTS:-$here/../../scripts}   # the core helpers; hs and hs-web set HS_SCRIPTS
. "$scripts/lib/ui.sh"
file=${HS_STATE_DIR:-/var/lib/hs}/{name}/entries

rows() { [ ! -s "$file" ] || awk -F'\\t' 'NF { printf "%s\\t%s\\n", $1, ($2 == "" ? "-" : $2) }' "$file"; }

case "${1:-list}" in
  --list) rows ;;
  list)
    if [ ! -s "$file" ]; then note "Nothing saved yet."; exit 0; fi
    { thead 'Name' 'Value'; rows; } | table ;;
  *) say "usage: hs ext {name} list"; exit 1 ;;
esac
'''

X_NOTES = '''# {name}

{title}. An extension package (docs/PLAN-extensions.md of the core): switch it on with `hs ext enable {name}` (no rebuild).
Commands: commands.tsv (`hs ext {name} list`, `hs sys ext {name} list`); the web read `list` is declared in capability.toml.
Scripts: list.sh in this folder; it finds the core helpers through HS_SCRIPTS, which hs sets.
'''

X_GUIDE = '''# {title}

{title}. Not tested on hardware yet.

## Before you start

- An installed server: see [Install](install.md).

## Switch it on

```bash
hs pkg install {name}
```

```bash
hs ext enable {name}
```

## Show the entries

```bash
hs ext {name} list
```

## Check that it worked

- `hs ext list` shows `{name}` as on.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `hs ext {name} list` is unknown | the extension is off | `hs ext enable {name}` |

## Next

- [Containers and apps](containers-and-apps.md)
'''

C_PACKAGE = '''# Manifest of a capability package (docs/PLAN-capabilities-repo.md). Raise version here AND in index.toml with every change.
name = "{name}"
version = "0.1.0"
kind = "capability"
type = "feature"
title = {q_title}
title_de = {q_title_de}
requires_core = ">=1"
audience = "generic"
permissions = []
requires = []
provides = []
# Add module = "module.nix" and requires_nix_api = 1 for a NixOS module, options = "options.toml" for its settings.
'''

C_GUIDE = '''# {title}

{title}. A capability package: a part of the server that is switched on in the settings. Not tested on hardware yet.

## Before you start

- An installed server: see [Install](install.md).

## Install it

```bash
hs pkg install {name}
```

## Check that it worked

- `hs pkg list` shows `{name}`.

## If something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| `hs pkg install {name}` stops | the repository is not fetched yet | `hs pkg fetch` |

## Next

- [Containers and apps](containers-and-apps.md)
'''

XP_COMMANDS = '''# Commands of the extension package "{name}" (docs/extensions-sdk.md of the core). Same columns as scripts/lib/registry.tsv of the core:
# kind	path	script	args	help	help.de	flags
# The package says `protocol = [1]`, so every row runs the script with the command protocol (ADR 0010): the words after the name are the command.
user	ext {name} list	@/{script}	-	the saved entries of {name}: name and value	die gespeicherten Einträge von {name}: Name und Wert	topic:system,reads
sys	sys ext {name} list	@/{script}	-	the saved entries of {name} as data: name, value (- when empty)	-
'''

XP_SH = '''#!/usr/bin/env bash
# The command `list` of {name}, in the command protocol (ADR 0010; helper scripts/lib/ext_sdk.sh, needs jq; guide docs/extensions-sdk.md).
# It reads <state>/{name}/entries (name TAB value per line). HS_STATE_DIR points tests at another folder.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "${HS_SCRIPTS:-$here/../../scripts}/lib/ext_sdk.sh"   # hs sets HS_SCRIPTS
ext_init
file=${HS_STATE_DIR:-/var/lib/hs}/{name}/entries

case "${EXT_WORDS[0]:-}" in
  list)
    rows='[]'
    [ ! -s "$file" ] || rows=$(jq -Rsc 'split("\\n") | map(select(length > 0) | split("\\t") | [.[0], (.[1] // "")])' "$file")
    ext_ok "" "$rows" ;;
  *) ext_fail not_found "no such command" ;;
esac
'''

XP_PY = '''#!/usr/bin/env python3
"""The command `list` of {name}, in the command protocol (ADR 0010; helper scripts/lib/ext_sdk.py; guide docs/extensions-sdk.md).
It reads <state>/{name}/entries (name TAB value per line). HS_STATE_DIR points tests at another folder."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.environ.get("HS_SCRIPTS", os.path.join(HERE, "..", "..", "scripts")), "lib"))   # python3 -I: name the folder yourself
import ext_sdk  # noqa: E402

FILE = os.path.join(os.environ.get("HS_STATE_DIR", "/var/lib/hs"), "{name}", "entries")


def handle(req, ctx):
    if req.words == ["list"]:
        rows = []
        if os.path.isfile(FILE):
            with open(FILE, encoding="utf-8") as f:
                for line in f:
                    parts = line.rstrip("\\n").split("\\t")
                    if parts[0]:
                        rows.append([parts[0], parts[1] if len(parts) > 1 else ""])
        return ext_sdk.ok(rows)
    raise ext_sdk.Failure("not_found", "no such command")


ext_sdk.run(handle)
'''

# (path inside the folder, text, mode)
TEMPLATES = {
    "recipe": [("package.toml", R_PACKAGE, 0o644), ("run.sh", R_RUN, 0o755), ("guide.md", R_GUIDE, 0o644)],
    "extension": [("package.toml", X_PACKAGE, 0o644), ("capability.toml", X_CAP, 0o644), ("commands.tsv", X_COMMANDS, 0o644),
                  ("list.sh", X_LIST, 0o755), ("NOTES.md", X_NOTES, 0o644), ("guide.md", X_GUIDE, 0o644)],
    "capability": [("package.toml", C_PACKAGE, 0o644), ("guide.md", C_GUIDE, 0o644)],
}
# `--protocol shell|python` swaps list.sh and commands.tsv of the extension template for a script that speaks the command protocol
PROTO_FILES = {"shell": ("list.sh", XP_SH), "python": ("list.py", XP_PY)}

STORE_OPTIONS = ("--description", "--description-de", "--icon", "--category", "--app-version")
OPTIONS = ("--template", "--dir", "--title", "--title-de", "--instances", "--protocol") + STORE_OPTIONS


def refuse(code, detail="-"):
    print("error\t%s\t%s" % (code, detail or "-"))
    return 2


def bad_title(s):
    return len(s) > 100 or any(ord(c) < 0x20 or ord(c) == 0x7f for c in s) or s != s.strip()


def render(text, name, title, title_de, q, extra=None):
    vals = {"q_title_de": q(title_de), "q_title": q(title), "title_de": title_de, "title": title, "name": name}
    vals.update(extra or {})
    return re.sub(r"\{(q_title_de|q_title|title_de|title|name|store|q_instances|proto|script)\}", lambda m: vals[m.group(1)], text)


def store_fields(main, opts, title, title_de):
    """(store fields as package.toml lines, the three the index carries, the refused option or None). Descriptions default to the titles."""
    pa = main.pkg_app
    desc = opts.get("--description", title)
    desc_de = opts.get("--description-de", title_de)
    icon = opts.get("--icon", "ph:package")
    cat = opts.get("--category", "tools")
    ver = opts.get("--app-version", VERSION)
    for opt, v in (("--description", desc), ("--description-de", desc_de)):
        if not v.strip() or len(v) > pa.MAX_TEXT or bad_title(v):
            return "", {}, opt
    if not pa.ICON_NAME.match(icon):
        return "", {}, "--icon"        # an SVG file is added by hand: a template cannot write one
    cats = pa.categories()
    if cats and cat not in cats:
        return "", {}, "--category"
    if not pa.APP_VERSION.match(ver):
        return "", {}, "--app-version"
    q = main.q
    text = "description = %s\ndescription_de = %s\nicon = %s\ncategory = %s\napp_version = %s\n" % (q(desc), q(desc_de), q(icon), q(cat), q(ver))
    return text, {"icon": icon, "category": cat, "app_version": ver}, None


def run(main, argv):
    opts, name, i = {}, None, 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            if a not in OPTIONS or i + 1 >= len(argv):
                return refuse("usage")
            opts[a] = argv[i + 1]
            i += 2
        else:
            if name is not None:
                return refuse("usage")
            name = a
            i += 1
    if name is None or "--template" not in opts:
        return refuse("usage")
    template = opts["--template"]
    if template not in SUB:
        return refuse("template", template)
    if not main.NAME.fullmatch(name) or name in RESERVED:
        return refuse("name", name)
    title = opts.get("--title", name)
    title_de = opts.get("--title-de", title)
    if bad_title(title) or bad_title(title_de):
        return refuse("title")
    instances = opts.get("--instances", "one")
    if instances not in ("one", "many") or (template != "recipe" and "--instances" in opts):
        return refuse("field", "--instances")
    proto = opts.get("--protocol")
    if proto is not None and (template != "extension" or proto not in PROTO_FILES):
        return refuse("field", "--protocol")
    store, idx = "", {}
    if template == "capability":
        used = [o for o in STORE_OPTIONS if o in opts]
        if used:
            return refuse("field", used[0])
    else:
        store, idx, why = store_fields(main, opts, title, title_de)
        if why:
            return refuse("field", why)
    d = os.path.abspath(opts.get("--dir") or os.getcwd())
    sub = SUB[template]
    index = os.path.join(d, "index.toml")
    if not os.path.isfile(index) or not os.path.isdir(os.path.join(d, sub)):
        return refuse("notrepo", d)
    try:
        with open(index, "rb") as f:
            parsed = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError):
        return refuse("notrepo", d)
    folder = os.path.join(d, sub, name)
    pk = parsed.get("package")
    if (isinstance(pk, dict) and name in pk) or os.path.lexists(folder):
        return refuse("exists", name)
    entry = ('\n[package.%s]\nversion = "%s"\nkind = "%s"\npath = "%s/%s"\ntitle = %s\nrequires_core = "%s"\naudience = "generic"\n'
             % (name, VERSION, template, sub, name, main.q(title), REQUIRES[template]))
    entry += "".join("%s = %s\n" % (k, main.q(idx[k])) for k in ("icon", "category", "app_version") if k in idx)
    extra = {"store": store, "q_instances": main.q(instances), "proto": "protocol = [1]\n" if proto else "",
             "script": PROTO_FILES[proto][0] if proto else ""}
    files_to_write = TEMPLATES[template]
    if proto:   # the script and the rows that speak the protocol take the place of the shell contract's
        script, text = PROTO_FILES[proto]
        files_to_write = [f for f in files_to_write if f[0] not in ("list.sh", "commands.tsv")]
        files_to_write += [("commands.tsv", XP_COMMANDS, 0o644), (script, text, 0o755)]
    new = index + ".new"
    files = []
    try:
        os.mkdir(folder)
        for rel, text, mode in files_to_write:
            p = os.path.join(folder, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(render(text, name, title, title_de, main.q, extra))
            os.chmod(p, mode)
            files.append(rel)
        with open(index, "rb") as f:
            data = f.read()
        if data and not data.endswith(b"\n"):
            data += b"\n"
        with open(new, "wb") as f:
            f.write(data + entry.encode("utf-8"))
        shutil.copymode(index, new)
        os.replace(new, index)
    except OSError as e:
        shutil.rmtree(folder, ignore_errors=True)
        try:
            os.remove(new)
        except OSError:
            pass
        return refuse("write", str(e).replace("\t", " ").replace("\n", " "))
    print("folder\t" + folder)
    for rel in files:
        print("file\t" + rel)
    print("index\t" + index)
    return 0
