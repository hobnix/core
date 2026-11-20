"""The role of a package's web entries (docs/PLAN-extensions-access.md step 18, ADR 0012, decision D13). Python stdlib only, no CLI.

Every [[web.reads]] and [[web.changes]] entry of a capability.toml may say `role = "viewer" | "app-manager" | "admin"`: the least role that may
use it. No `role` means admin, so a manifest written before roles existed stays admin-only. The web interface applies the higher of this role and
the role of the sys row the entry calls (scripts/web-serve.py), so a package can never open something wider than the core allows.
"""

ROLES = ("viewer", "app-manager", "admin")
DEFAULT = "admin"


def of(entry):
    """The role of one entry dict, or None when it is not a valid role (the entry has no `role` = the default)."""
    r = entry.get("role", DEFAULT) if isinstance(entry, dict) else None
    return r if isinstance(r, str) and r in ROLES else None


def manifest_problems(web):
    """[text] for the `role` keys of the parsed capability.toml `web` (its [web] tables are checked, the rest is ignored)."""
    wm = (web or {}).get("web", {})
    if not isinstance(wm, dict):
        return []
    out = []
    for table in ("reads", "changes"):
        entries = wm.get(table, [])
        if not isinstance(entries, list):
            continue
        for i, e in enumerate(entries):
            if isinstance(e, dict) and "role" in e and of(e) is None:
                out.append("web.%s[%d]: role must be one of %s" % (table, i, ", ".join(ROLES)))
    return out
