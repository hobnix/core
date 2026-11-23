#!/usr/bin/env python3
"""The slots a package may fill (hobnix/server#472, docs/PLAN-package-pages.md "Slots", docs/extensions.md "Slots"). Python stdlib only.

A slot is a place in the interface that a package fills with data. Five exist in 0.12:
  page    [web.page]                a place in the tree (an extension) or an object page (a recipe)
  tab     [[web.page.tabs]]         a tab on the package's own page
  action  [[web.actions]]           an allowlisted plan with a role: page header and the Apps > Installed row (one main action, the rest under More)
  health  [[health]]                a declared read that returns level and message: a problem in System > Health with the package named
  state   [web.page.state]          the dot and the line of the card on lists and group pages
Any slot may carry `requires = "<capability or extension>"`: while that is off the slot shows nothing.
Anything else under [web] is refused with the list above. The page, tab and state keys are checked by hs_ext.py and pkg_blocks.py; this file checks
the shape of actions, health and requires, builds what the web interface and the health check read, and is the CLI of the health check:

  python3 pkg_slots.py problems   key TAB text for every package health check that reports warn or bad (scripts/health-check.sh)
  python3 pkg_slots.py list       package, id, level, message of every check, ok ones too
  python3 pkg_slots.py requires <package-toml-or-capability-dir>   slot TAB name for each `requires` that is off (the install dialog note)
"""
import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOTS = ("page", "tab", "action", "health", "state")
WEB_KEYS = ("reads", "changes", "page", "actions")      # the tables a package may write under [web]; `page` carries tab and state
ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,30}$")
NAME = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
LEVELS = ("ok", "info", "warn", "bad")      # the health system has no info level: ok and info rows are never problems (see problems())
ACTION_KEYS = ("id", "label", "plan", "role", "main", "danger", "icon", "requires")
HEALTH_KEYS = ("id", "read", "title", "requires")
MAX_ACTIONS, MAX_HEALTH = 8, 8


def known_text():
    return "known slots: %s" % ", ".join(SLOTS)


def _roles():
    spec = importlib.util.spec_from_file_location("pkg_roles", os.path.join(HERE, "pkg_roles.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def doc_of(cap, m=None):
    """The document that carries the slots: the capability.toml of an extension, else the package.toml (a recipe)."""
    return cap if cap else (m or {})


def _requires_problem(where, entry, own):
    r = entry.get("requires")
    if r is None:
        return []
    if not isinstance(r, str) or not NAME.match(r):
        return ["%s: requires must be the name of a capability or an extension" % where]
    if r == own:
        return ["%s: requires names the package itself" % where]
    return []


def manifest_problems(name, doc):
    """[text] for the slots of a parsed manifest: an unknown slot, [[web.actions]], [[health]] and every `requires`. Nothing for a manifest without slots."""
    doc = doc if isinstance(doc, dict) else {}
    web = doc.get("web", {})
    out = []
    if not isinstance(web, dict):
        return ["web: must be a table"]
    for k in web:
        if k not in WEB_KEYS:
            out.append("web.%s: unknown slot %r (%s; written as [web.page] with tabs and state, [[web.actions]] and [[health]])" % (k, k, known_text()))
    page = web.get("page")
    if isinstance(page, dict):
        out += _requires_problem("web.page", page, name)
        if isinstance(page.get("state"), dict):
            out += _requires_problem("web.page.state", page["state"], name)
        for i, t in enumerate(page.get("tabs", []) if isinstance(page.get("tabs", []), list) else []):
            if isinstance(t, dict):
                out += _requires_problem("web.page.tabs[%d]" % i, t, name)
    roles = _roles()
    actions = web.get("actions", [])
    if not isinstance(actions, list) or len(actions) > MAX_ACTIONS:
        out.append("web.actions: a list of at most %d actions" % MAX_ACTIONS)
        actions = []
    ids, mains = set(), 0
    for i, a in enumerate(actions):
        w = "web.actions[%d]" % i
        if not isinstance(a, dict):
            out.append("%s: an action is a table" % w)
            continue
        for k in a:
            if k not in ACTION_KEYS:
                out.append("%s: no key %s (allowed: %s)" % (w, k, ", ".join(ACTION_KEYS)))
        if not isinstance(a.get("id"), str) or not ID.match(a["id"]):
            out.append("%s: id must be lowercase letters, digits and dashes" % w)
        elif a["id"] in ids:
            out.append("%s: id %s is used twice" % (w, a["id"]))
        else:
            ids.add(a["id"])
        if not isinstance(a.get("label"), str) or not 1 <= len(a["label"]) <= 40:
            out.append("%s: label is 1 to 40 characters" % w)
        pl = a.get("plan")
        if not isinstance(pl, list) or not pl or not all(isinstance(x, str) for x in pl) or pl[0] != "ext/" + str(name):
            out.append("%s: plan must be a list that starts with \"ext/%s\" (an action plans a change of its own area)" % (w, name))
        if "role" in a and roles.of(a) is None:
            out.append("%s: role must be one of %s" % (w, ", ".join(roles.ROLES)))
        for k in ("main", "danger"):
            if k in a and not isinstance(a[k], bool):
                out.append("%s: %s must be true or false" % (w, k))
        mains += 1 if a.get("main") is True else 0
        out += _requires_problem(w, a, name)
    if mains > 1:
        out.append("web.actions: only one action is the main action (main = true); the others go under More")
    checks = doc.get("health", [])
    if not isinstance(checks, list) or len(checks) > MAX_HEALTH:
        out.append("health: a list of at most %d checks" % MAX_HEALTH)
        checks = []
    reads = {str(r.get("words")): r for r in web.get("reads", []) if isinstance(r, dict)} if isinstance(web.get("reads", []), list) else {}
    ids = set()
    for i, h in enumerate(checks):
        w = "health[%d]" % i
        if not isinstance(h, dict):
            out.append("%s: a health check is a table" % w)
            continue
        for k in h:
            if k not in HEALTH_KEYS:
                out.append("%s: no key %s (allowed: %s)" % (w, k, ", ".join(HEALTH_KEYS)))
        if not isinstance(h.get("id"), str) or not ID.match(h["id"]):
            out.append("%s: id must be lowercase letters, digits and dashes" % w)
        elif h["id"] in ids:
            out.append("%s: id %s is used twice" % (w, h["id"]))
        else:
            ids.add(h["id"])
        rd = reads.get(str(h.get("read")))
        if rd is None:
            out.append("%s: read %r is not a [[web.reads]] of this package" % (w, h.get("read")))
        elif rd.get("kind") != "tsv" or rd.get("args"):
            out.append("%s: the read must be kind tsv without args (rows: level, message; level is ok, info, warn or bad)" % w)
        if "title" in h and (not isinstance(h["title"], str) or not 1 <= len(h["title"]) <= 60):
            out.append("%s: title is 1 to 60 characters" % w)
        out += _requires_problem(w, h, name)
    return out


def _off(requires, on):
    return isinstance(requires, str) and requires not in on


def gate_page(page, on):
    """The page declaration as the web interface may see it: None when the page itself requires something that is off, tabs (and their blocks) and
    the state that require something that is off dropped."""
    if not isinstance(page, dict) or _off(page.get("requires"), on):
        return None
    page = dict(page)
    gone = {t.get("id") for t in page.get("tabs", []) if isinstance(t, dict) and _off(t.get("requires"), on)}
    if gone:
        page["tabs"] = [t for t in page["tabs"] if t.get("id") not in gone]
        page["blocks"] = [b for b in page.get("blocks", []) if not (isinstance(b, dict) and b.get("tab") in gone)]
    if isinstance(page.get("state"), dict) and _off(page["state"].get("requires"), on):
        del page["state"]
    return page


def declared(name, doc, on):
    """-> {"name", "title", "actions", "health"} of the package for the web interface and the health check, only what is allowed and not switched off
    by `requires`; None when the package declares no slot of its own. Raises ValueError when the manifest has a problem (nothing of it is used)."""
    bad = manifest_problems(name, doc)
    if bad:
        raise ValueError(bad[0])
    web = (doc or {}).get("web", {})
    acts = [{k: v for k, v in a.items() if k != "requires"} for a in web.get("actions", []) if not _off(a.get("requires"), on)]
    if acts and not any(a.get("main") for a in acts):
        acts[0]["main"] = True
    checks = [{k: v for k, v in h.items() if k != "requires"} for h in doc.get("health", []) if not _off(h.get("requires"), on)]
    if not acts and not checks:
        return None
    return {"name": name, "title": doc.get("title") or name, "actions": acts, "health": checks}


def requires_off(doc, on):
    """[(slot, required name)] for every slot of a manifest whose `requires` is off now (the install dialog says: adds a card once <name> is on)."""
    doc = doc if isinstance(doc, dict) else {}
    web = doc.get("web", {}) if isinstance(doc.get("web", {}), dict) else {}
    found = []
    page = web.get("page") if isinstance(web.get("page"), dict) else {}
    found += [("page", page.get("requires"))]
    found += [("tab", t.get("requires")) for t in page.get("tabs", []) if isinstance(t, dict)] if isinstance(page.get("tabs", []), list) else []
    found += [("state card", page["state"].get("requires"))] if isinstance(page.get("state"), dict) else []
    found += [("action", a.get("requires")) for a in web.get("actions", []) if isinstance(a, dict)] if isinstance(web.get("actions", []), list) else []
    found += [("health check", h.get("requires")) for h in doc.get("health", []) if isinstance(h, dict)] if isinstance(doc.get("health", []), list) else []
    return [(s, r) for s, r in found if _off(r, on)]


# ── what the health check does with a declared health read ──

def _hs_ext():
    spec = importlib.util.spec_from_file_location("hs_ext", os.path.join(os.path.dirname(HERE), "hs_ext.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run_read(name, words, timeout=20):
    """-> [[field, ...]] rows of `hs sys ext <name> <words>`, or None when it failed."""
    hs = os.environ.get("HS_BIN") or os.path.join(HERE, "hs.sh")
    try:
        p = subprocess.run(["bash", hs, "sys", "ext", name] + words.split(), capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    return [ln.split("\t") for ln in p.stdout.splitlines() if ln.strip()]


def check_rows():
    """[(package title, package, check id, level, message)] of every health check of a package that is on; a read that cannot be run is level bad."""
    ext = _hs_ext()
    on = set(ext.capabilities()) | ext.applied_recipes()
    out = []
    for name, d in ext.ext_packages():
        try:
            doc = ext.ext_manifest(d)
            slot = declared(name, doc, on)
        except Exception:      # a package with a wrong manifest adds no check (hs pkg validate says why)
            continue
        for h in (slot or {}).get("health", []):
            title = h.get("title") or slot["title"]
            rows = _run_read(name, h["read"])
            if rows is None:
                out.append((title, name, h["id"], "bad", "the health check %s could not be read" % h["id"]))
                continue
            for r in rows:
                lv = r[0] if r else ""
                msg = (r[1] if len(r) > 1 and r[1] != "-" else "").strip()
                if lv not in LEVELS:
                    out.append((title, name, h["id"], "bad", "the health check %s returned the unknown level %r" % (h["id"], lv)))
                else:
                    out.append((title, name, h["id"], lv, msg))
    return out


def problems():
    """[(key, text)]: one per check that reports warn or bad (ok and info rows, e.g. a PC that is simply switched off, are no problem: not counted, not sent); text names the package ("Title: message"), key is ext:<package>:<id>."""
    seen = {}
    for title, name, cid, lv, msg in check_rows():
        if lv in ("ok", "info"):
            continue
        k = "ext:%s:%s" % (name, cid)
        seen.setdefault(k, [title, []])[1].append(msg or "needs attention")
    return [(k, "%s: %s" % (t, "; ".join(m[:3]))) for k, (t, m) in seen.items()]


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "problems":
        for k, t in problems():
            sys.stdout.write("%s\t%s\n" % (k, " ".join(t.split())))
    elif cmd == "list":
        for title, name, cid, lv, msg in check_rows():
            sys.stdout.write("%s\t%s\t%s\t%s\n" % (name, cid, lv, msg or "-"))
    elif cmd == "requires" and len(argv) == 2:
        import tomllib
        ext = _hs_ext()
        on = set(ext.capabilities()) | ext.applied_recipes()
        try:
            with open(argv[1], "rb") as f:
                doc = tomllib.load(f)
        except (OSError, tomllib.TOMLDecodeError):
            return 0
        for slot, r in requires_off(doc, on):
            sys.stdout.write("%s\t%s\n" % (slot, r))
    else:
        sys.stderr.write("usage: pkg_slots.py problems | list | requires <file>\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
