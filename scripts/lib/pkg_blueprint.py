"""The package.toml of a blueprint (kind = "blueprint", docs/PLAN-registry.md "Blueprints"): an ordered package list plus fill-only config,
no script, no Nix, no other file read. Stdlib only, no CLI. pkg.py (validate, check-draft) and the repository check call `manifest_problems()`.

manifest_problems(m) -> [text]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
ROLES = ("homeserver", "edge", "minimal")
LISTS = ("capabilities", "extensions", "recipes")
MAX_PACKAGES = 40
LEVEL = 11      # the API level that knows the kind: an older core refuses a blueprint by its requires_core
DOCKER_MANAGERS = ("webui", "arcane", "portainer", "none")
DOCKER_SIZES = ("s", "m", "l")
# the keys of [machine] that a blueprint never sets: who the server is, its disks, and Docker (only through [docker])
MACHINE_REFUSED = ("role", "capabilities", "pools", "hostId", "bulkType", "dockerManager", "dockerSize")
TOP_KEYS = ("name", "version", "kind", "title", "title_de", "description", "description_de", "requires_core", "audience", "roles",
            "icon", "category", "upstream", "app_version", "screenshots", "renamed_from")
TOP_TABLES = ("blueprint", "docker", "machine", "settings", "answers", "meta")
SCALARS = (str, int, float, bool)


def _schema():
    """(options {key: store}, secrets {key}) of config/schema.toml, or None when it cannot be read."""
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import schema_options
    try:
        return schema_options.options(), schema_options.secrets()
    except (OSError, ValueError, KeyError):
        return None


def _flat(v):
    return isinstance(v, SCALARS) or (isinstance(v, list) and all(isinstance(x, SCALARS) for x in v))


def manifest_problems(m):
    out = []
    bad = out.append
    for k, v in m.items():
        if k in TOP_KEYS:
            continue
        if k in TOP_TABLES:
            if not isinstance(v, dict):
                bad(f"{k} must be a table")
            continue
        bad(f"{k} is not allowed in a blueprint (only the package list and fill-only config: [blueprint], [docker], [machine], [settings], [answers.<recipe>])")
    rq = re.match(r"^>=(\d+)$", str(m.get("requires_core", "")))
    if rq and int(rq.group(1)) < LEVEL:
        bad(f'a blueprint needs requires_core ">={LEVEL}" (this manifest says {m.get("requires_core")})')
    roles = m.get("roles")
    if not isinstance(roles, list) or not roles:
        bad("roles is missing or empty (homeserver, edge or minimal)")
    else:
        for r in roles:
            if r not in ROLES:
                bad(f"unknown role {r!r} in roles")
    bp = m.get("blueprint") if isinstance(m.get("blueprint"), dict) else {}
    if "blueprint" not in m:
        bad("[blueprint] table missing")
    seen = []
    for k, v in bp.items():
        if k not in LISTS:
            bad(f"[blueprint] {k} is not capabilities, extensions or recipes")
            continue
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            bad(f"[blueprint] {k} must be a list of package names")
            continue
        for x in v:
            if not NAME.match(x):
                bad(f"[blueprint] {k}: {x!r} is not a lowercase package name")
            elif x == "docker":      # in every list: the capability folder docker would skip the fill-only and typed-name rules of [docker]
                bad("Docker is the core capability: use the [docker] table")
            elif x in seen:
                bad(f"[blueprint] {x} is named twice")
            seen.append(x)
    if len(seen) > MAX_PACKAGES:
        bad(f"[blueprint] names {len(seen)} packages, at most {MAX_PACKAGES}")
    dk = m.get("docker")
    if isinstance(dk, dict):
        for k, v in dk.items():
            if k == "manager":
                if v not in DOCKER_MANAGERS:
                    bad("[docker] manager is not " + ", ".join(DOCKER_MANAGERS))
            elif k == "size":
                if v not in DOCKER_SIZES:
                    bad("[docker] size is not " + ", ".join(DOCKER_SIZES))
            else:
                bad(f"[docker] {k} is not manager or size")
        if "manager" not in dk:
            bad("[docker] needs manager")
    answers = m.get("answers")
    if isinstance(answers, dict):
        for r, t in answers.items():
            if r not in (bp.get("recipes") if isinstance(bp.get("recipes"), list) else []):
                bad(f"[answers.{r}] is for a recipe the blueprint does not name")
            elif not isinstance(t, dict) or not all(isinstance(v, str) for v in t.values()):
                bad(f"[answers.{r}] must hold text values")
    sch = None
    for table, store in (("machine", "machine"), ("settings", "settings")):
        t = m.get(table)
        if not isinstance(t, dict) or not t:
            continue
        if sch is None:
            sch = _schema() or False
            if sch is False:
                bad("config/schema.toml cannot be read: [machine] and [settings] are not checked")
        for k, v in t.items():
            if k in MACHINE_REFUSED:
                bad(f"[{table}] {k} is not allowed in a blueprint" + (" (Docker only through [docker])" if k.startswith("docker") else ""))
            elif sch:
                opts, secrets = sch
                if k not in opts:
                    bad(f"[{table}] {k} is not an option of config/schema.toml")
                elif opts[k] != store:
                    bad(f"[{table}] {k} belongs in [{'settings' if store == 'machine' else 'machine'}]")
                elif k in secrets:
                    bad(f"[{table}] {k} is a secret: a blueprint never carries one")
            if table == "settings" and not isinstance(v, str):
                bad(f"[settings] {k} must be text")
            elif not _flat(v):
                bad(f"[{table}] {k}: only text, numbers, true/false and lists of them")
    return out
