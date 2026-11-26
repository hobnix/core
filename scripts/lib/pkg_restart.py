#!/usr/bin/env python3
"""Which extension services must restart after a package changed (hobnix/core#1129, ADR 0031). Stdlib only.

  pkg_restart.py <packages-current-dir> <name> [--providers]

Prints one package name per line: <name> itself when its package.toml has a [service] table, and with --providers (install, remove: the
package is a provider) every other package with a [service] table whose `permissions` list `integration:<n>` for an [integrations.<n>]
the package declares. The caller restarts what is active."""
import os
import sys
import tomllib


def load(root, name):
    try:
        with open(os.path.join(root, name, "package.toml"), "rb") as f:
            return tomllib.load(f)
    except (OSError, ValueError):
        return {}


def services(root, name, providers):
    m = load(root, name)
    out = []
    if isinstance(m.get("service"), dict):
        out.append(name)
    ig = m.get("integrations")
    offered = {f"integration:{n}" for n in ig} if isinstance(ig, dict) else set()
    if providers and offered:
        for other in sorted(os.listdir(root)):
            if other == name or other in out:
                continue
            o = load(root, other)
            perms = o.get("permissions")
            if isinstance(o.get("service"), dict) and isinstance(perms, list) and offered & {str(p) for p in perms}:
                out.append(other)
    return out


def main(argv):
    if len(argv) < 2:
        return 2
    for n in services(argv[0], argv[1], "--providers" in argv[2:]):
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
