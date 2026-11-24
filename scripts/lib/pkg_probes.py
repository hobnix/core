#!/usr/bin/env python3
"""Probes and tools that packages bring for `hs smoke` (docs/PLAN-packages.md, #1072).

  pkg_probes.py probes <dir>...   one line per [[probe]]: label TAB words TAB ok codes (space separated) TAB limit (empty = default)
  pkg_probes.py tools  <dir>...   the programs named in `tools = [...]`, one per line

A <dir> is a package folder (capability.toml or package.toml). The caller (scripts/smoke.sh) passes only the packages that are ON, so
nothing of an off package is probed. A malformed entry is left out; a folder without a manifest says nothing."""
import os
import re
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11: nothing to read with, say nothing
    tomllib = None

TOOL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")


def manifest(folder):
    if tomllib is None:
        return {}
    for f in ("capability.toml", "package.toml"):
        p = os.path.join(folder, f)
        if os.path.isfile(p):
            try:
                with open(p, "rb") as fh:
                    return tomllib.load(fh)
            except (OSError, tomllib.TOMLDecodeError):
                return {}
    return {}


def clean(s):
    return re.sub(r"[\t\r\n]+", " ", s).strip()


def probes(m):
    for p in m.get("probe", []) if isinstance(m.get("probe"), list) else []:
        if not isinstance(p, dict):
            continue
        label, words, ok = p.get("label"), p.get("words"), p.get("ok", [0])
        if not isinstance(label, str) or not isinstance(words, str) or not clean(label) or not clean(words):
            continue
        if not isinstance(ok, list) or not ok or not all(isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 255 for x in ok):
            continue
        limit = p.get("limit", "")
        if limit != "" and (isinstance(limit, bool) or not isinstance(limit, int) or limit < 1):
            continue
        yield "\t".join((clean(label), clean(words), " ".join(str(x) for x in ok), str(limit)))


def tools(m):
    t = m.get("tools", [])
    for x in t if isinstance(t, list) else []:
        if isinstance(x, str) and TOOL.match(x):
            yield x


def main(argv):
    if len(argv) < 2 or argv[1] not in ("probes", "tools"):
        print("usage: pkg_probes.py probes|tools <dir>...", file=sys.stderr)
        return 2
    seen = set()
    for d in argv[2:]:
        for line in (probes if argv[1] == "probes" else tools)(manifest(d)):
            if line not in seen:
                seen.add(line)
                print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
