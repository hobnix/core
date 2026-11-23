"""The block registry for `[web.page]` (hobnix/server#473, docs/PLAN-package-pages.md). Python stdlib only, no CLI.

web/src/shell/block-registry.json lists the blocks a package page may use: name, component, schema (required keys, allowed keys with a type) and the
`api-level` of the list. The web interface reads the same file (web/src/shell/blocks.js), so what `hs pkg validate` accepts is what the renderer draws.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
TYPES = {"string": (str,), "list": (list,), "dict": (dict,), "bool": (bool,), "number": (int, float), "string|list": (str, list)}


def registry():
    """The parsed registry, or None when the web sources are not beside the scripts (a copy without web/): the check is skipped then."""
    for r in (os.environ.get("HS_PACKAGES_ROOT"), os.path.dirname(os.path.dirname(HERE)), os.environ.get("HS_NIXOS_DIR", "/etc/nixos")):
        p = os.path.join(r or "", "web", "src", "shell", "block-registry.json")
        if os.path.isfile(p):
            with open(p, encoding="utf-8") as f:
                return json.load(f)
    return None


FIELD_TYPES = ("text", "number", "toggle", "select", "secret")
FIELD_KEYS = {"key": str, "label": str, "type": str, "required": bool, "pattern": str, "invalid": str, "hint": str, "placeholder": str,
              "min": (int, float), "max": (int, float), "options": list, "default": (str, int, float, bool)}   # a bool is only a toggle default; a number only a number field (a wrong one is a type error)
FIELD_KEY = re.compile(r"^[a-z][a-z0-9_]{0,30}$")
PLACEHOLDER = re.compile(r"\{(\w+)(?:\|\w+)?\}")


def form_problems(name, block, where, changes):
    """[text] for one `form` block (docs/extensions.md "The form block"): fields are data, the submit goes to the package's own plan area
    (`ext/<name>`) and ends in the plan dialog. `changes`: the [[web.changes]] entries of the package. A secret field travels on stdin only: it
    needs `stdin = "<its key>"`, a change that takes stdin, and it may not appear in `plan` or `planTitle` (those are argv and the Tasks list)."""
    out = []
    plan = block.get("plan")
    if isinstance(plan, list):
        if not plan or not all(isinstance(w, str) for w in plan) or plan[0] != "ext/" + name:
            out.append("%s: a form may only plan changes of its own area (plan starts with ext/%s)" % (where, name))
        elif len(plan) < 2 or not changes:
            out.append("%s: the plan is not allowlisted: the package declares no [[web.changes]] for it" % where)
    fields = block.get("fields")
    keys, secrets = {}, []
    if isinstance(fields, list):
        if not 1 <= len(fields) <= 20:
            out.append("%s: a form has 1 to 20 fields" % where)
        for i, f in enumerate(fields):
            w = "%s.fields[%d]" % (where, i)
            if not isinstance(f, dict):
                out.append("%s: a field is a table" % w)
                continue
            for k, v in f.items():
                t = FIELD_KEYS.get(k)
                if t is None:
                    out.append("%s: a field has no key %s" % (w, k))
                elif not isinstance(v, t) or (isinstance(v, bool) and bool not in (t if isinstance(t, tuple) else (t,))):
                    out.append("%s: %s has the wrong type" % (w, k))
            ft = f.get("type")
            if ft not in FIELD_TYPES:
                out.append("%s: unknown field type %r (known: %s)" % (w, ft, ", ".join(FIELD_TYPES)))
            k = f.get("key")
            if not isinstance(k, str) or not FIELD_KEY.match(k):
                out.append("%s: key must be a-z, 0-9 and _, starting with a letter" % w)
            elif k in keys:
                out.append("%s: the key %s is used twice" % (w, k))
            else:
                keys[k] = ft
                if ft == "secret":
                    secrets.append(k)
            if not isinstance(f.get("label"), str) or not 1 <= len(f.get("label", "")) <= 80:
                out.append("%s: a field needs a label of 1 to 80 characters" % w)
            if isinstance(f.get("pattern"), str):
                try:
                    re.compile(f["pattern"])
                except re.error:
                    out.append("%s: pattern is not a valid regular expression" % w)
            if ("min" in f or "max" in f) and ft != "number":
                out.append("%s: min and max are for number fields" % w)
            if "min" in f and "max" in f and isinstance(f["min"], (int, float)) and isinstance(f["max"], (int, float)) and f["min"] > f["max"]:
                out.append("%s: min is above max" % w)
            if "pattern" in f and ft not in ("text", "secret"):
                out.append("%s: pattern is for text and secret fields" % w)
            o = f.get("options")
            if ft == "select":
                if not isinstance(o, list) or not 1 <= len(o) <= 50 or not all(isinstance(x, str) and 1 <= len(x) <= 80 for x in o) or len(set(o)) != len(o):
                    out.append("%s: a select needs options: 1 to 50 different strings" % w)
            elif "options" in f:
                out.append("%s: options are for select fields" % w)
            if ft == "secret" and ("default" in f or "options" in f):
                out.append("%s: a secret field has no default (it is never stored or shown back)" % w)
    if len(secrets) > 1:
        out.append("%s: at most one secret field (stdin carries one line)" % where)
    sk = block.get("stdin")
    if secrets and sk is None:
        out.append("%s: the secret field %s needs stdin = \"%s\" (a secret goes on stdin, never in the plan)" % (where, secrets[0], secrets[0]))
    elif sk is not None and sk not in secrets:
        out.append("%s: stdin must name the secret field" % where)
    if secrets and not any(isinstance(c, dict) and c.get("stdin") for c in changes):
        out.append("%s: a secret field needs a [[web.changes]] entry with stdin = true" % where)
    for what in ("plan", "planTitle"):
        v = block.get(what)
        for word in (v if isinstance(v, list) else [v]):
            for ph in PLACEHOLDER.findall(word if isinstance(word, str) else ""):
                if ph in secrets:
                    out.append("%s: %s may not use the secret field {%s}" % (where, what, ph))
                elif ph not in keys and isinstance(fields, list):
                    out.append("%s: %s uses {%s}, which is not a field" % (where, what, ph))
    return out


def _check(reg, block, where, out, name=None, changes=()):
    if not isinstance(block, dict):
        out.append("%s: a block is a table" % where)
        return
    t = block.get("type")
    spec = reg["blocks"].get(t) if isinstance(t, str) else None
    if spec is None:
        out.append("%s: unknown block %r (known: %s; block list api-level %s)" % (where, t, ", ".join(sorted(reg["blocks"])), reg["api-level"]))
        return
    sch = spec["schema"]
    keys = {**reg.get("common", {}), **sch["keys"]}
    for k in sch["required"]:
        if k not in block:
            out.append("%s: block %s needs %s" % (where, t, k))
    for k, v in block.items():
        if k not in keys:
            out.append("%s: block %s has no key %s" % (where, t, k))
        elif not isinstance(v, TYPES[keys[k]]) or (keys[k] == "number" and isinstance(v, bool)):
            out.append("%s: %s of block %s must be a %s" % (where, k, t, keys[k]))
    if t == "form" and name:
        out += form_problems(name, block, where, changes)
    for path in sch.get("blocks", []):
        head, _, tail = path.partition(".")
        sub = block.get(head)
        inner = sub.get(tail, []) if isinstance(sub, dict) else []
        for i, b in enumerate(inner if isinstance(inner, list) else []):
            _check(reg, b, "%s.%s[%d]" % (where, path, i), out, name, changes)


def manifest_problems(cap):
    """[text] for the [web.page] blocks of a parsed capability.toml (None or without a page: nothing)."""
    page = ((cap or {}).get("web") or {}).get("page")
    if not isinstance(page, dict) or not isinstance(page.get("blocks", []), list):
        return []
    reg = registry()
    if reg is None:
        return []
    out = []
    changes = ((cap or {}).get("web") or {}).get("changes") or []
    for i, b in enumerate(page.get("blocks", [])):
        _check(reg, b, "web.page.blocks[%d]" % i, out, (cap or {}).get("name"), changes)
    for j, t in enumerate(page.get("tabs", []) if isinstance(page.get("tabs", []), list) else []):
        for i, b in enumerate(t.get("blocks", []) if isinstance(t, dict) and isinstance(t.get("blocks", []), list) else []):
            _check(reg, b, "web.page.tabs[%d].blocks[%d]" % (j, i), out, (cap or {}).get("name"), changes)
    return out
