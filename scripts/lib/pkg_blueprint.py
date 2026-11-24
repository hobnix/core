"""The package.toml of a blueprint (kind = "blueprint", docs/PLAN-registry.md "Blueprints"): an ordered package list plus fill-only config,
no script, no Nix, no other file read. Stdlib only, no CLI. pkg.py (validate, check-draft) and the repository check call `manifest_problems()`;
`hs pkg blueprint list|show|record` (pkg_repo.run) calls the three readers below.

manifest_problems(m) -> [text]
show(R, pkg, name, lang) -> (lines, problems)   the blueprint and the packages it names as key<TAB>value lines (the plan of blueprint-change.sh reads them):
  repo, version, tag, commit, title, description, roles (csv), added (yes|no), machine<TAB>key<TAB>toml literal, setting<TAB>key<TAB>value,
  part<TAB>capabilities|extensions|recipes<TAB>name<TAB>state (capabilities `-`; extensions new|installed; recipes `ok` or `later:<why>`: input terminal,
  a secret ask, an ask without default or answer), needs<TAB>recipe<TAB>csv|-, docker<TAB>manager<TAB>size|-, answer<TAB>recipe<TAB>KEY<TAB>value
listing(R, pkg, lang) -> [row]   name, repo, version, roles, packages (in order), state new|applied|update|waits, title (tab separated, - = empty)
record(R, pkg, name)             writes [applied.<name>] to blueprints.toml (HS_BLUEPRINTS_FILE, else <HS_STATE_DIR or /var/lib/hs>/blueprints.toml), atomically
R is a pkg_repo.Repos, pkg the module pkg.py. A blueprint may name packages of its own repository and of `official`, no other.
"""
import datetime
import json
import os
import tempfile
import tomllib
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


# ── reading (hs pkg blueprint ...) ──
TRUSTED = "official"


def literal(v):
    """a value as the TOML literal machine_set takes"""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join(literal(x) for x in v) + "]"
    return json.dumps(v, ensure_ascii=False)


def _one(R, name):
    """(repo, entry, tag, commit, manifest) of the blueprint called name, else ValueError"""
    rows = [r for r in R.catalog().get(name, []) if r[1].get("kind") == "blueprint"]
    if not rows:
        raise ValueError("No blueprint called '%s'." % name)
    if len(rows) > 1:
        raise ValueError("%s is in more than one repository (%s)." % (name, ", ".join(r[0] for r in rows)))
    try:
        return R.verified_package(name, rows[0][0])
    except Exception as e:     # pkg_repo.Refused: the reason is the text
        raise ValueError(str(e))


def _named(R, name, repo):
    """(kind, manifest) of a package a blueprint names, from its own repository or official only"""
    rows = [r for r in R.catalog().get(name, []) if r[0] in (repo, TRUSTED)]
    if not rows:
        raise ValueError("%s is in no repository this blueprint may use (its own, %s)." % (name, TRUSTED))
    try:
        return rows[0][1].get("kind", ""), R.verified_package(name, rows[0][0])[4]
    except Exception as e:
        raise ValueError(str(e))


def _recipe_state(pm, given, n, bad):
    """ok, or later:<why>: a recipe that needs a person is not run by the blueprint"""
    why = "it is set up in a terminal" if pm.get("input", "none") == "terminal" else ""
    keys = [a.get("key") for a in pm.get("ask", [])]
    for a in pm.get("ask", []):
        key = a.get("key", "")
        if a.get("type") == "secret":
            if key in given:
                bad.append("[answers.%s] %s is a secret: a blueprint never carries one" % (n, key))
            why = why or "it asks for a secret (%s)" % key
        elif key not in given and a.get("default") in (None, "") and a.get("when") is None:
            why = why or "it asks for %s" % key
    bad.extend("[answers.%s] %s is not a question of the recipe" % (n, k) for k in given if k not in keys)
    return "later:" + why if why else "ok"


def show(R, pkg, name, lang="en"):
    try:
        repo, _entry, tag, commit, m = _one(R, name)
    except ValueError as e:
        return [], [str(e)]
    bad = manifest_problems(m)
    if m.get("kind") != "blueprint":
        bad.append("%s is not a blueprint." % name)
    added = not R.all().get(repo, {}).get("default")
    out = ["repo\t%s" % repo, "version\t%s" % m.get("version", ""), "tag\t%s" % tag, "commit\t%s" % commit,
           "title\t%s" % (m.get("title_" + lang) or m.get("title") or name),
           "description\t%s" % (" ".join(str(m.get("description_" + lang) or m.get("description") or "-").split())),
           "roles\t%s" % ",".join(m.get("roles", [])), "added\t%s" % ("yes" if added else "no")]
    out += ["machine\t%s\t%s" % (k, literal(v)) for k, v in (m.get("machine") or {}).items()]
    out += ["setting\t%s\t%s" % (k, v) for k, v in (m.get("settings") or {}).items()]
    bp, answers, have = m.get("blueprint") or {}, m.get("answers") or {}, pkg.installed()
    for kind in LISTS:
        for n in bp.get(kind, []) if isinstance(bp.get(kind), list) else []:
            if kind == "capabilities":     # a core folder or a capability package: the bundle resolver of the shell part knows which
                out.append("part\tcapabilities\t%s\t-" % n)
                continue
            try:
                k, pm = _named(R, n, repo)
            except ValueError as e:
                bad.append(str(e))
                continue
            if kind == "extensions":
                out.append("part\textensions\t%s\t%s" % (n, "installed" if n in have else "new"))
            elif k != "recipe":
                bad.append("%s is not a recipe." % n)
            else:
                out.append("part\trecipes\t%s\t%s" % (n, _recipe_state(pm, answers.get(n, {}), n, bad)))
                out.append("needs\t%s\t%s" % (n, ",".join(pm.get("needs", [])) or "-"))
                out += ["answer\t%s\t%s\t%s" % (n, k2, v) for k2, v in answers.get(n, {}).items()]
    if isinstance(m.get("docker"), dict):
        out.append("docker\t%s\t%s" % (m["docker"].get("manager", "webui"), m["docker"].get("size", "-")))
    return out, bad


def _nums(s):
    return tuple(int(x) for x in re.findall(r"\d+", str(s))[:3])


def listing(R, pkg, lang="en"):
    have, rows = _applied(), []
    for n, found in sorted(R.catalog().items()):
        for repo, entry, _tag, _commit in found:
            if entry.get("kind") != "blueprint":
                continue
            try:
                m = R.verified_package(n, repo)[4]
            except Exception:
                continue
            ver = str(m.get("version", ""))
            st = "new" if n not in have else ("update" if _nums(have[n].get("version", "0")) < _nums(ver) else "applied")
            rq = re.match(r"^>=(\d+)$", str(m.get("requires_core", "")))
            if rq and int(rq.group(1)) > pkg.api_level():
                st = "waits"
            bp = m.get("blueprint") or {}
            names = [x for k in LISTS for x in (bp.get(k) if isinstance(bp.get(k), list) else [])] + (["docker"] if "docker" in m else [])
            cells = [n, repo, ver, ",".join(m.get("roles", [])), ",".join(names), st, m.get("title_" + lang) or m.get("title") or n]
            rows.append("\t".join(" ".join(str(c).split()) or "-" for c in cells))
    return rows


def _applied_file():
    return os.environ.get("HS_BLUEPRINTS_FILE") or os.path.join(os.environ.get("HS_STATE_DIR") or "/var/lib/hs", "blueprints.toml")


def _applied():
    try:
        with open(_applied_file(), "rb") as f:
            return tomllib.load(f).get("applied", {})
    except (OSError, tomllib.TOMLDecodeError):
        return {}


def record(R, pkg, name):
    repo, _entry, _tag, commit, m = _one(R, name)
    have = _applied()
    have[name] = {"repo": repo, "version": str(m.get("version", "")), "commit": commit, "applied": datetime.date.today().isoformat()}
    path = _applied_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".blueprints.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for n in sorted(have):
            f.write("[applied.%s]\n" % n)
            f.writelines("%s = %s\n" % (k, json.dumps(str(v), ensure_ascii=False)) for k, v in have[n].items())
            f.write("\n")
    os.replace(tmp, path)
