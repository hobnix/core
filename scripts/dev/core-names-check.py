#!/usr/bin/env python3
"""The packages the core refers to by name must be in the official checkout (hobnix/core#1074, decision D4). CI of the core runs it.
  core-names-check.py <official checkout> [--repos <package-repos.toml>] [--name N ...]
Names: `core = [...]` of the row named "official" in config/package-repos.toml, plus every --name. Until that row exists (the switch, P3 of
#1074) the names are the ones `hs pkg install --core` fetches on a first run (FALLBACK). Each name must be in the index.toml of the checkout
with `core = true`. Prints one line per problem and exits 1 when any; a missing name is named, never skipped."""
import os
import sys
import tomllib

# first run today (docs/PLAN-packages.md); the row of official replaces this list in the switch PR
FALLBACK = ["domain", "monitoring", "ntfy", "zoraxy"]


def wanted(repos_file):
    try:
        with open(repos_file, "rb") as f:
            rows = tomllib.load(f).get("repo", [])
    except (OSError, tomllib.TOMLDecodeError):
        return list(FALLBACK), "built-in list (no readable " + repos_file + ")"
    for r in rows:
        if r.get("name") == "official" and "core" in r:
            return [str(n) for n in r["core"]], "row official of " + repos_file
    return list(FALLBACK), "built-in list (no official row with core = [...] in " + repos_file + " yet)"


def problems(checkout, names):
    try:
        with open(os.path.join(checkout, "index.toml"), "rb") as f:
            idx = tomllib.load(f).get("package", {})
    except (OSError, tomllib.TOMLDecodeError) as e:
        return ["index.toml of %s: %s" % (checkout, e)]
    out = []
    for n in names:
        e = idx.get(n)
        if e is None:
            out.append("%s: the core refers to it by name, but it is not in the index of %s" % (n, checkout))
        elif e.get("core") is not True:
            out.append("%s: is in the index but not flagged core = true, so `hs pkg install --core` would skip it" % n)
        elif not os.path.isfile(os.path.join(checkout, str(e.get("path", "")), "package.toml")):
            out.append("%s: the index points at %s, which has no package.toml" % (n, e.get("path")))
    return out


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    checkout, rest = argv[0], argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    repos = os.path.join(here, "..", "..", "config", "package-repos.toml")
    extra = []
    i = 0
    while i < len(rest):
        if rest[i] == "--repos" and i + 1 < len(rest):
            repos = rest[i + 1]
            i += 2
        elif rest[i] == "--name" and i + 1 < len(rest):
            extra.append(rest[i + 1])
            i += 2
        else:
            print("unknown argument: " + rest[i])
            return 2
    names, source = wanted(repos)
    names += [n for n in extra if n not in names]
    found = problems(checkout, names)
    for t in found:
        print(t)
    print("core-names-check: %d names from the %s, %d problems" % (len(names), source, len(found)), file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
