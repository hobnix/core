"""The package.toml of a blueprint (kind = "blueprint", docs/PLAN-registry.md "Blueprints"): an ordered package list plus fill-only config,
no script, no Nix, no other file read. Stdlib only, no CLI. pkg.py (validate, check-draft) and the repository check call `manifest_problems()`;
`hs pkg blueprint list|show|record` (pkg_repo.run) calls the three readers below.

manifest_problems(m) -> [text]
show(R, pkg, name, lang) -> (lines, problems)   the blueprint and the packages it names as key<TAB>value lines (the plan of blueprint-change.sh reads them):
  repo, version, tag, commit, title, description, roles (csv), added (yes|no), machine<TAB>key<TAB>toml literal, setting<TAB>key<TAB>value,
  part<TAB>capabilities|extensions|recipes<TAB>name<TAB>state (capabilities `-`; extensions new|installed; recipes `ok` or `later:<why>`: input terminal,
  a secret ask, an ask without default or answer, or a repository the user added), from<TAB>recipe<TAB>repo, needs<TAB>recipe<TAB>csv|-, docker<TAB>manager<TAB>size|-, answer<TAB>recipe<TAB>KEY<TAB>value
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
NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}\Z")   # \Z, not $: a name with a newline at the end is no name
ROLES = ("homeserver", "edge", "minimal")
LISTS = ("capabilities", "extensions", "recipes")
MAX_PACKAGES = 40
LEVEL = 11      # the API level that knows the kind: an older core refuses a blueprint by its requires_core
DOCKER_MANAGERS = ("webui", "arcane", "portainer", "none")
DOCKER_SIZES = ("s", "m", "l")
# THE ONE LIST of the options a blueprint may fill ([machine] and [settings]): plain preferences only. Everything that touches access, keys,
# the firewall, storage, networks or users (sshKeys, nodeKeys, adminUser, sshOverIp, gateway*, tailscale*, pools, incusDefaultPool, role,
# capabilities, hostId ...) is NOT in it, and neither is anything new by default: a key that is not here refuses the blueprint. Docker only through [docker].
ALLOWED_KEYS = ("language", "timeZone", "keyMap", "icons", "loginMessage", "webAccent", "siteName", "quietHours", "notifications",
                "backupNewShares", "backupNewInstances")
# every string of a blueprint (keys and values, any depth): no control character (a newline would start a new line of the plan), and a length cap
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]")   # C0, DEL, C1 (U+0085 too), line and paragraph separators: splitlines() breaks on them
MAX_KEY, MAX_TEXT, MAX_LONG = 64, 300, 2000
LONG_FIELDS = ("description", "description_de")
TOP_KEYS = ("name", "version", "kind", "title", "title_de", "description", "description_de", "requires_core", "audience", "roles",
            "icon", "category", "upstream", "app_version", "screenshots", "renamed_from")
TOP_TABLES = ("blueprint", "docker", "machine", "settings", "answers", "meta")
SCALARS = (str, int, float, bool)


def _so():
    """schema_options, imported when it is needed: pkg.py loads this file at start, and a pulled core without schema_options.py (hs update) must still load it"""
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import schema_options
    return schema_options


def _schema():
    """(options {key: store}, secrets {key}) of config/schema.toml, or None when it cannot be read."""
    try:
        so = _so()
        return so.options(), so.secrets()
    except (OSError, ValueError, KeyError, ImportError):
        return None


def _typed(k, v):
    """why the value does not fit the schema entry of the option k (type, pattern, choices), else empty"""
    try:
        it = _so().specs().get(k)
    except (OSError, ValueError, KeyError, ImportError):
        return ""
    if not it:
        return ""
    if it.get("settable") is False:
        return "is not settable"
    t = it.get("type", "string")
    if t == "string":
        ok = isinstance(v, str)
    elif t == "bool":
        ok = isinstance(v, bool) or v in ("true", "false")
    elif t == "int":
        ok = (isinstance(v, int) and not isinstance(v, bool)) or (isinstance(v, str) and re.fullmatch(r"-?[0-9]{1,9}", v) is not None)
    else:
        return ""
    if not ok:
        return "must be " + t
    sv = v if isinstance(v, str) else str(v)
    if t == "string" and it.get("pattern") and not re.search(it["pattern"], sv):
        return "does not match " + str(it.get("hint") or it["pattern"])
    if it.get("choices") and sv not in it["choices"]:
        return "is not one of " + ", ".join(it["choices"])
    return ""


def _flat(v):
    return isinstance(v, SCALARS) or (isinstance(v, list) and all(isinstance(x, SCALARS) for x in v))


def _safe(t):
    """a message is printed as a line: whatever a hostile manifest put into it (a key, a name) loses its control characters and is cut short"""
    t = CONTROL.sub("?", str(t))
    return t if len(t) <= 240 else t[:240] + "..."


def _strings(v, path, out):
    """every (path, text, is_key) of a nested value"""
    if isinstance(v, str):
        out.append((path, v, False))
    elif isinstance(v, dict):
        for k, x in v.items():
            out.append((path, str(k), True))
            _strings(x, path + "." + str(k) if path else str(k), out)
    elif isinstance(v, list):
        for x in v:
            _strings(x, path, out)


def text_problems(m):
    """a control character or an over-long text anywhere in the manifest refuses the whole blueprint"""
    found, out = [], []
    _strings(m, "", found)
    for path, text, is_key in found:
        top = path.split(".")[0]
        cap = MAX_KEY if is_key else (MAX_LONG if top in LONG_FIELDS else MAX_TEXT)
        where = path or "the manifest"
        if CONTROL.search(text):
            out.append(f"{where}: a text with a control character (a line break, a tab) is not allowed in a blueprint")
        elif len(text) > cap:
            out.append(f"{where}: a text of {len(text)} characters is too long (at most {cap})")
    return [_safe(x) for x in out]


def manifest_problems(m):
    out = text_problems(m)
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
            n0 = len(out)
            if k.startswith("docker"):
                bad(f"[{table}] {k} is not allowed in a blueprint (Docker only through [docker])")
            elif sch:
                opts, secrets = sch
                if k not in opts:
                    bad(f"[{table}] {k} is not an option of config/schema.toml")
                elif opts[k] != store:
                    bad(f"[{table}] {k} belongs in [{'settings' if store == 'machine' else 'machine'}]")
                elif k in secrets:
                    bad(f"[{table}] {k} is a secret: a blueprint never carries one")
            if k not in ALLOWED_KEYS and len(out) == n0:
                bad(f"[{table}] {k} is not allowed in a blueprint" + " (only plain preferences: " + ", ".join(ALLOWED_KEYS) + ")")
            if k in ALLOWED_KEYS and sch:
                why = _typed(k, v)
                if why:
                    bad(f"[{table}] {k} {why}")
            if table == "settings" and not isinstance(v, str):
                bad(f"[settings] {k} must be text")
            elif not _flat(v):
                bad(f"[{table}] {k}: only text, numbers, true/false and lists of them")
    return [_safe(x) for x in out]


# ── reading (hs pkg blueprint ...) ──
TRUSTED = "official"


def _row(*cells):
    """one tab separated output row: a cell with a control character is refused, so no field can ever start a new row or a new column"""
    for c in cells:
        if CONTROL.search(str(c)):
            raise ValueError("a blueprint text holds a control character: refused")
    return "	".join(str(c) for c in cells)


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
    """(kind, manifest, repo) of a package a blueprint names, from its own repository or official only"""
    rows = [r for r in R.catalog().get(name, []) if r[0] in (repo, TRUSTED)]
    if not rows:
        raise ValueError("%s is in no repository this blueprint may use (its own, %s)." % (name, TRUSTED))
    try:
        return rows[0][1].get("kind", ""), R.verified_package(name, rows[0][0])[4], rows[0][0]
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
        out, bad = _show(R, pkg, name, lang)
    except ValueError as e:     # _row: a control character got as far as the writer
        out, bad = [], [str(e)]
    return out, [_safe(x) for x in bad]


def _show(R, pkg, name, lang):
    try:
        repo, _entry, tag, commit, m = _one(R, name)
    except ValueError as e:
        return [], [str(e)]
    bad = manifest_problems(m)
    if m.get("kind") != "blueprint":
        bad.append("%s is not a blueprint." % name)
    if bad and any("control character" in x or "too long" in x for x in bad):
        return [], bad        # a hostile text is not even printed
    added = not R.all().get(repo, {}).get("default")
    out = [_row("repo", repo), _row("version", m.get("version", "")), _row("tag", tag), _row("commit", commit),
           _row("title", m.get("title_" + lang) or m.get("title") or name),
           _row("description", " ".join(str(m.get("description_" + lang) or m.get("description") or "-").split())),
           _row("roles", ",".join(m.get("roles", []))), _row("added", "yes" if added else "no")]
    out += [_row("machine", k, literal(v)) for k, v in (m.get("machine") or {}).items()]
    out += [_row("setting", k, v) for k, v in (m.get("settings") or {}).items()]
    bp, answers, have = m.get("blueprint") or {}, m.get("answers") or {}, pkg.installed()
    for kind in LISTS:
        for n in bp.get(kind, []) if isinstance(bp.get(kind), list) else []:
            if kind == "capabilities":     # a core folder or a capability package: the bundle resolver of the shell part knows which
                out.append(_row("part", "capabilities", n, "-"))
                continue
            try:
                k, pm, prepo = _named(R, n, repo)
            except ValueError as e:
                bad.append(str(e))
                continue
            if kind == "extensions":
                out.append(_row("part", "extensions", n, "installed" if n in have else "new"))
            elif k != "recipe":
                bad.append("%s is not a recipe." % n)
            else:
                state = _recipe_state(pm, answers.get(n, {}), n, bad)
                if state == "ok" and not R.all().get(prepo, {}).get("default"):
                    # an app of an added repository needs its own typed name (apps-change.sh): the blueprint does not type it for you
                    state = "later:it comes from the repository %s you added, so you confirm it yourself" % prepo
                out.append(_row("part", "recipes", n, state))
                out.append(_row("from", n, prepo))
                out.append(_row("needs", n, ",".join(pm.get("needs", [])) or "-"))
                out += [_row("answer", n, k2, v) for k2, v in answers.get(n, {}).items()]
    if isinstance(m.get("docker"), dict):
        out.append(_row("docker", m["docker"].get("manager", "webui"), m["docker"].get("size", "-")))
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
            if m.get("kind") != "blueprint" or text_problems(m):     # the index says blueprint, the package.toml does not (or it holds a hostile text)
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
    if m.get("kind") != "blueprint":
        raise ValueError("%s is not a blueprint." % name)
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
