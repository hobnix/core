"""The app contract and the store fields of a package.toml (docs/PLAN-app-lifecycle.md Q4/Q5, docs/Package-API.md "App contract", API level 9).
Python stdlib only, no CLI. pkg.py (validate, check-draft) and the repository check call `check()`.

Every key here is optional, so a manifest written before API level 9 validates unchanged. The key names are read by the web interface
(Apps, Marketplace) and by later steps: after they are merged they change only with an API level bump (ADR 0008 rule 4).

check(m, folder=None, core=False) -> (errors, warnings), lists of text.
  folder: the package folder (pictures and icon are checked on disk); None for a draft that has no files yet.
  core:   the package is flagged `core = true` in the index: the [app] contract is then required (an error, else a warning).
"""
import ast
import os
import re
import tomllib

API_LEVEL = 9
STORE_KEYS = ("description", "description_de", "icon", "category", "upstream", "app_version", "screenshots")
APP_KEYS = {"instances", "autostart", "health", "backup", "routes", "update", "version", "remove", "uses"}
INSTANCES = ("one", "many")
HEALTH_CHECKS = ("container", "tcp", "http")
BACKUP_MODES = ("instance", "paths", "none")
SCHEMES = ("http", "https")
EXPOSURES = ("never-public", "private-ok", "public-ok")
UPDATE_KINDS = ("pin", "os", "manual")
UPDATE_DEFAULTS = ("automatic", "notify", "pinned")
VERSION_SOURCES = ("image-tag", "http-json", "exec")
ROUTE_KEYS = {"port", "scheme", "exposure", "admin"}
ICON_NAME = re.compile(r"^ph:[a-z0-9]+(-[a-z0-9]+)*$")
ICON_FILE = re.compile(r"^[A-Za-z0-9._-]+\.svg$")
PICTURE = re.compile(r"^[A-Za-z0-9._/-]+\.(png|webp)$")
ROUTE_NAME = re.compile(r"^[a-z][a-z0-9-]{0,29}$")
DUMP_KIND = re.compile(r"^[a-z][a-z0-9-]{0,39}$")
APP_VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+~-]{0,39}$")
MAX_ICON = 20 * 1024
MAX_SHOT = 300 * 1024
MAX_SHOTS = 5
MAX_TEXT = 500
HERE = os.path.dirname(os.path.abspath(__file__))
# what the web interface needs from a package that shows up in a store
STORE_REQUIRED = ("description", "icon", "category", "app_version")
CONTRACT_REQUIRED = ("health", "backup", "update", "remove")


def backup_paths(m):
    """The paths of [app.backup] mode = "paths" (absolute, inside the instance), else []. The recipe run seeds the backup rules from them."""
    app = m.get("app") if isinstance(m.get("app"), dict) else {}
    b = app.get("backup") if isinstance(app.get("backup"), dict) else {}
    paths = b.get("paths", [])
    if b.get("mode") != "paths" or not _strs(paths):
        return []
    return [p for p in paths if p.startswith("/") and ".." not in p.split("/")]


def categories():
    """The fixed category list, config/package-categories.toml (`ids = [...]`)."""
    for base in (os.environ.get("HS_CONFIG_DIR"), os.path.join(HERE, "..", "..", "config"), "/etc/nixos/config"):
        if not base:
            continue
        try:
            with open(os.path.join(base, "package-categories.toml"), "rb") as f:
                return [str(c) for c in tomllib.load(f).get("ids", [])]
        except (OSError, tomllib.TOMLDecodeError):
            continue
    return []


def admin_targets():
    """ADMIN_TARGETS of scripts/services.py (the guard stays there; read, not copied)."""
    try:
        with open(os.path.join(HERE, "..", "services.py"), encoding="utf-8") as f:
            m = re.search(r"^ADMIN_TARGETS\s*=\s*(\{.*\})\s*$", f.read(), re.M)
        return set(ast.literal_eval(m.group(1))) if m else set()
    except (OSError, ValueError, SyntaxError):
        return set()


def uses_app(m):
    return "app" in m or any(k in m for k in STORE_KEYS)


def _t(k):
    """A key from the manifest, made safe to print in a tab-separated line."""
    return re.sub(r"[\x00-\x1f\x7f]", "?", str(k))[:40]


def _is_int(v, lo=0, hi=None):
    return isinstance(v, int) and not isinstance(v, bool) and v >= lo and (hi is None or v <= hi)


def _strs(v, limit=200, count=20):
    return (isinstance(v, list) and len(v) <= count
            and all(isinstance(s, str) and 1 <= len(s) <= limit and "\n" not in s and "\t" not in s for s in v))


def svg_problem(text):
    """Why an SVG icon is refused (None = fine): script, event handler or an external reference."""
    low = text.lower()
    if "<script" in low:
        return "contains <script"
    if re.search(r"[\s\"'/]on[a-z]+\s*=", low):
        return "contains an on...= handler"
    if re.search(r"<(set|animate|animatetransform|animatemotion|use)[ />]", low) or "javascript:" in low or "data:text" in low:
        return "contains animation, use or a script address"
    if "<foreignobject" in low or "<iframe" in low or "<!entity" in low:
        return "contains foreignObject, iframe or an entity"
    for ref in re.findall(r"(?:href|src)\s*=\s*[\"']([^\"']*)[\"']", low):
        if not ref.startswith("#"):
            return "has an external reference"
    if re.search(r"url\(\s*[\"']?(?!#)", low) or re.search(r"@import|https?://(?!www\.w3\.org/)", low):
        return "has an external reference"
    return None


def _file_in(folder, rel):
    p = os.path.realpath(os.path.join(folder, rel))
    base = os.path.realpath(folder)
    if os.path.commonpath([p, base]) != base:
        return None
    return p


def _store(m, folder, bad):
    for k in ("description", "description_de"):
        if k in m:
            v = m[k]
            if not isinstance(v, str) or not v.strip() or len(v) > MAX_TEXT or "\n\n" in v:
                bad(f"{k} must be one paragraph of at most {MAX_TEXT} characters")
    if "icon" in m:
        ic = m["icon"]
        if not isinstance(ic, str) or not (ICON_NAME.match(ic) or ICON_FILE.match(ic)):
            bad('icon must be a Phosphor name like "ph:image" or a file name ending in .svg in the package')
        elif ic.endswith(".svg") and folder:
            p = _file_in(folder, ic)
            if not p or not os.path.isfile(p):
                bad(f"icon file {ic} is not in the package")
            elif os.path.getsize(p) > MAX_ICON:
                bad(f"icon file {ic} is larger than {MAX_ICON // 1024} KB")
            else:
                try:
                    with open(p, encoding="utf-8") as f:
                        why = svg_problem(f.read())
                except (OSError, UnicodeDecodeError):
                    why = "is not UTF-8 text"
                if why:
                    bad(f"icon file {ic} {why}")
    if "category" in m:
        cats = categories()
        if not isinstance(m["category"], str) or (cats and m["category"] not in cats):
            bad("category is not one of config/package-categories.toml (" + " ".join(cats) + ")")
    if "upstream" in m:
        u = m["upstream"]
        if not isinstance(u, str) or not re.match(r"^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[^\s]*)?$", u):
            bad("upstream must be an https:// address")
    if "app_version" in m and (not isinstance(m["app_version"], str) or not APP_VERSION.match(m["app_version"])):
        bad("app_version must be a short version text (letters, digits, . _ + ~ -)")
    if "screenshots" in m:
        s = m["screenshots"]
        if not isinstance(s, list) or not all(isinstance(x, str) for x in s):
            bad("screenshots must be a list of file names")
        elif len(s) > MAX_SHOTS:
            bad(f"at most {MAX_SHOTS} screenshots")
        else:
            for x in s:
                if not PICTURE.match(x) or ".." in x.split("/") or x.startswith("/"):
                    bad(f"screenshot {x!r}: a relative png or webp path inside the package")
                elif folder:
                    p = _file_in(folder, x)
                    if not p or not os.path.isfile(p):
                        bad(f"screenshot {x} is not in the package")
                    elif os.path.getsize(p) > MAX_SHOT:
                        bad(f"screenshot {x} is larger than {MAX_SHOT // 1024} KB")


def _table(app, key, allowed, bad):
    t = app.get(key)
    if t is None:
        return None
    if not isinstance(t, dict):
        bad(f"[app.{key}] must be a table")
        return None
    for k in sorted(set(t) - allowed):
        bad(f"[app.{key}] has an unknown key {_t(k)}")
    return t


def _contract(name, m, bad):
    app = m.get("app")
    if not isinstance(app, dict):
        bad("[app] must be a table")
        return
    for k in sorted(set(app) - APP_KEYS):
        bad(f"[app] has an unknown key {_t(k)}")
    if app.get("instances", "one") not in INSTANCES:
        bad("[app] instances is not one or many")
    if "autostart" in app and not isinstance(app["autostart"], bool):
        bad("[app] autostart must be true or false")
    h = _table(app, "health", {"check", "port", "path", "timeout"}, bad)
    if h is not None:
        chk = h.get("check", "container")
        if chk not in HEALTH_CHECKS:
            bad("[app.health] check is not container, tcp or http")
        if chk in ("tcp", "http") and not _is_int(h.get("port"), 1, 65535):
            bad(f"[app.health] check {chk} needs a port (1 to 65535)")
        if chk == "container" and ("port" in h or "path" in h):
            bad("[app.health] port and path belong to tcp or http")
        if "path" in h and (chk != "http" or not isinstance(h["path"], str) or not re.match(r"^/[A-Za-z0-9._~/%?=&-]*$", h["path"])):
            bad("[app.health] path is for check http and starts with /")
        if "timeout" in h and not _is_int(h["timeout"], 1, 60):
            bad("[app.health] timeout is 1 to 60 seconds")
    b = _table(app, "backup", {"mode", "paths", "dump"}, bad)
    if b is not None:
        mode = b.get("mode", "instance")
        if mode not in BACKUP_MODES:
            bad("[app.backup] mode is not instance, paths or none")
        paths = b.get("paths", [])
        if mode == "paths" and not paths:
            bad("[app.backup] mode paths needs paths")
        if paths and (mode != "paths" or not _strs(paths) or any(not p.startswith("/") or ".." in p.split("/") for p in paths)):
            bad("[app.backup] paths: absolute paths inside the instance, only with mode paths")
        d = b.get("dump", "-")
        if d != "-" and (not isinstance(d, str) or not DUMP_KIND.match(d)):
            bad('[app.backup] dump is a dump kind name or "-"')
    routes = app.get("routes")
    if routes is not None:
        if not isinstance(routes, dict):
            bad("[app.routes] must be a table")
        else:
            names = [k for k in routes if k != "default"]
            for rn in names:
                rt = routes[rn]
                if not ROUTE_NAME.match(rn) or not isinstance(rt, dict):
                    bad(f"[app.routes] {_t(rn)}: a route is a lower case name with a table {{ port, scheme, exposure }}")
                    continue
                for k in sorted(set(rt) - ROUTE_KEYS):
                    bad(f"[app.routes] {_t(rn)} has an unknown key {_t(k)}")
                if not _is_int(rt.get("port"), 1, 65535):
                    bad(f"[app.routes] {_t(rn)}: port (1 to 65535) missing")
                if rt.get("scheme", "http") not in SCHEMES:
                    bad(f"[app.routes] {_t(rn)}: scheme is not http or https")
                ex = rt.get("exposure", "private-ok")
                if ex not in EXPOSURES:
                    bad(f"[app.routes] {_t(rn)}: exposure is not never-public, private-ok or public-ok")
                elif ex == "public-ok" and (rt.get("admin") is True or (_is_int(rt.get("port")) and (name, rt["port"]) in admin_targets())):
                    bad(f"[app.routes] {_t(rn)}: an admin page is never public (ADMIN_TARGETS of scripts/services.py)")
                if "admin" in rt and not isinstance(rt["admin"], bool):
                    bad(f"[app.routes] {_t(rn)}: admin must be true or false")
            if "default" in routes and routes["default"] not in names:
                bad("[app.routes] default must name one of the routes")
            if not names:
                bad("[app.routes] names no route")
    u = _table(app, "update", {"kind", "default"}, bad)
    if u is not None:
        if u.get("kind", "pin") not in UPDATE_KINDS:
            bad("[app.update] kind is not pin, os or manual")
        if u.get("default", "notify") not in UPDATE_DEFAULTS:
            bad("[app.update] default is not automatic, notify or pinned")
    v = _table(app, "version", {"source", "path", "pointer", "command"}, bad)
    if v is not None:
        src = v.get("source")
        if src not in VERSION_SOURCES:
            bad("[app.version] source is not image-tag, http-json or exec")
        elif src == "http-json" and not (isinstance(v.get("path"), str) and v["path"].startswith("/") and isinstance(v.get("pointer"), str) and v["pointer"].startswith("/")):
            bad("[app.version] http-json needs a path and a JSON pointer, both starting with /")
        elif src == "exec" and not (_strs(v.get("command"), 200, 20) and v["command"]):
            bad("[app.version] exec needs command as a list of words")
        elif src != "http-json" and ("path" in v or "pointer" in v):
            bad("[app.version] path and pointer belong to http-json")
        if src != "exec" and "command" in v:
            bad("[app.version] command belongs to exec")
    rm = _table(app, "remove", {"keeps", "data"}, bad)
    if rm is not None:
        for k in ("keeps", "data"):
            if k in rm and not _strs(rm[k], 120, 10):
                bad(f"[app.remove] {k} must be a short list of texts")
    us = _table(app, "uses", {"ram_mb", "disk_gb", "ports", "gpu"}, bad)
    if us is not None:
        for k in ("ram_mb", "disk_gb"):
            if k in us and not _is_int(us[k], 0, 10_000_000):
                bad(f"[app.uses] {k} must be a whole number")
        if "ports" in us and not (isinstance(us["ports"], list) and len(us["ports"]) <= 20 and all(_is_int(p, 1, 65535) for p in us["ports"])):
            bad("[app.uses] ports must be a list of port numbers")
        if "gpu" in us and not isinstance(us["gpu"], bool):
            bad("[app.uses] gpu must be true or false")


def check(m, folder=None, core=False):
    errors, warnings = [], []
    bad = errors.append
    name = str(m.get("name", "?"))
    kind = m.get("kind")
    if uses_app(m):
        rq = re.match(r"^>=(\d+)$", str(m.get("requires_core", "")))
        if rq and int(rq.group(1)) < API_LEVEL:
            bad(f"app contract and store fields need requires_core \">={API_LEVEL}\" (this manifest says {m.get('requires_core')})")
        if kind not in ("recipe", "extension", "blueprint"):
            bad("[app] and the store fields belong to a recipe, an extension or a blueprint")
    if "app" in m:
        _contract(name, m, bad)
    _store(m, folder, bad)
    app = m.get("app") if isinstance(m.get("app"), dict) else {}
    # strictness (D9): the five core recipes and a package that carries store fields must be complete; for the rest it is a warning
    store_carrier = any(k in m for k in STORE_KEYS)
    miss = []
    rq9 = re.match(r"^>=(\d+)$", str(m.get("requires_core", "")))
    # a recipe written before level 9 cannot be required to carry what level 9 introduced: it gets a warning until it raises requires_core
    strict = core and bool(rq9) and int(rq9.group(1)) >= API_LEVEL
    if kind == "recipe":
        if core:
            miss += [f"[app.{k}]" for k in CONTRACT_REQUIRED if k not in app]
            if "routes" not in app:
                miss.append("[app.routes]")
        if core or store_carrier:
            miss += [k for k in STORE_REQUIRED if k not in m]
        if miss:
            (errors if strict else warnings).append("missing: " + ", ".join(miss) + (" (required for a core recipe at requires_core >=%d)" % API_LEVEL if core else " (a package with store fields should carry all of them)"))
        elif not app and not store_carrier:
            warnings.append("has no [app] contract and no store fields (optional; docs/Package-API.md)")
    return errors, warnings
