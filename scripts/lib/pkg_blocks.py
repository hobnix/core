"""The block registry for `[web.page]` (hobnix/server#473, docs/PLAN-package-pages.md). Python stdlib only, no CLI.

web/src/shell/block-registry.json lists the blocks a package page may use: name, component, schema (required keys, allowed keys with a type) and the
`api-level` of the list. The web interface reads the same file (web/src/shell/blocks.js), so what `hs pkg validate` accepts is what the renderer draws.
"""
import json
import os

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


def _check(reg, block, where, out):
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
    for path in sch.get("blocks", []):
        head, _, tail = path.partition(".")
        sub = block.get(head)
        inner = sub.get(tail, []) if isinstance(sub, dict) else []
        for i, b in enumerate(inner if isinstance(inner, list) else []):
            _check(reg, b, "%s.%s[%d]" % (where, path, i), out)


def manifest_problems(cap):
    """[text] for the [web.page] blocks of a parsed capability.toml (None or without a page: nothing)."""
    page = ((cap or {}).get("web") or {}).get("page")
    if not isinstance(page, dict) or not isinstance(page.get("blocks", []), list):
        return []
    reg = registry()
    if reg is None:
        return []
    out = []
    for i, b in enumerate(page.get("blocks", [])):
        _check(reg, b, "web.page.blocks[%d]" % i, out)
    return out
