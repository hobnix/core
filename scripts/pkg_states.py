#!/usr/bin/env python3
"""Package lifecycle states (ADR 0027, docs/PLAN-app-lifecycle.md Q1): one merge of what the market, the parts list, the pending rebuilds,
the recipe list and the container list say about every package. Pure: the five inputs are files (tests feed fixtures), `hs pkg --states`
makes them.

  pkg.py states --market F --parts F --pending F --recipes F --running F [--kind K] [--health F]
    name, kind, stage, flags, repo, available, installed, instances, title   (tab separated, empty = -, sorted by name)

stage: available | installed | on | running. flags (comma list or -): update, waits, orphan, pending, failed, unhealthy, stopped.
"""
import sys

FLAGS = ("update", "waits", "orphan", "pending", "failed", "unhealthy", "stopped")


def rows(path):
    """The tab separated lines of a file as lists; a missing or empty file is no rows."""
    if not path:
        return []
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return []
    return [ln.rstrip("\r").split("\t") for ln in text.split("\n") if ln.strip()]


def containers(path):
    """`incus list -f csv -c ns`: name,STATE per line -> {name: lower case state}; a failed call left an empty file."""
    out = {}
    if not path:
        return out
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return out
    for ln in text.split("\n"):
        ln = ln.strip()
        if "," in ln:
            n, s = ln.rsplit(",", 1)
            out[n.strip()] = s.strip().lower()
    return out


def col(r, i, default="-"):
    v = r[i].strip() if len(r) > i else ""
    return v or default


def states(market, parts, pending, recipes, running, kind=None, health=None):
    mk = {r[0]: r for r in market if r}
    pt = {r[0]: r for r in parts if r}
    pend = {r[0] for r in pending if r}
    rc = {r[0]: r for r in recipes if r}
    hl = {r[0]: r[1] for r in (health or []) if len(r) > 1}
    out = []
    for name in sorted(set(mk) | set(pt) | set(rc)):
        m, p, rr = mk.get(name), pt.get(name), rc.get(name)
        k = col(m, 1) if m else "?"
        if k == "?":
            if rr:
                k = "recipe"
            elif p:
                k = "extension" if col(p, 2) == "extension" else "capability"
        mstate = col(m, 5) if m else "-"
        copy = bool(m) and col(m, 4) != "-"
        flags = set()
        if mstate in ("update", "waits", "orphan"):
            flags.add(mstate)
        instances = []
        if k == "recipe":
            cts = [] if not rr or col(rr, 2) == "-" else col(rr, 2).split(",")
            rstate = col(rr, 3) if rr else "-"
            on = rstate in ("installed", "partly")
            if running:
                instances = [c for c in cts if c in running]
                on = on or bool(instances)
            elif rstate == "installed":
                instances = cts
            if on:
                stage = "on"
                if running and instances:
                    if all(running[c] == "running" for c in instances):
                        # a declared check that fails: the instance runs but the app is not up (Q1: running needs the check to pass)
                        if hl.get(name) == "unhealthy":
                            flags.add("unhealthy")
                        else:
                            stage = "running"
                    else:
                        flags.add("stopped")
            elif copy or (rr and not m):
                stage = "installed"
            else:
                stage = "available"
        else:
            if p:
                if col(p, 1) == "on":
                    stage = "running" if name not in pend else "on"
                else:
                    stage = "installed"
            elif copy:
                stage = "installed"
            else:
                stage = "available"
            if name in pend:
                flags.add("pending")
        if kind and k != kind:
            continue
        title = col(m, 8) if m else "-"
        if title == "-":
            title = col(p, 5) if p else (col(rr, 1) if rr else "-")
        out.append([name, k, stage, ",".join(f for f in FLAGS if f in flags) or "-", col(m, 2) if m else "-",
                    col(m, 3) if m else "-", col(m, 4) if m else "-", ",".join(instances) or "-", title.replace("\t", " ")])
    return out


def run(args):
    opts = {}
    i = 0
    while i < len(args):
        if args[i] in ("--market", "--parts", "--pending", "--recipes", "--running", "--kind", "--health") and i + 1 < len(args):
            opts[args[i][2:]] = args[i + 1]
            i += 2
        else:
            print("usage: pkg.py states --market F --parts F --pending F --recipes F --running F [--kind K] [--health F]", file=sys.stderr)
            return 1
    for r in states(rows(opts.get("market")), rows(opts.get("parts")), rows(opts.get("pending")), rows(opts.get("recipes")),
                    containers(opts.get("running")), opts.get("kind"), rows(opts.get("health"))):
        sys.stdout.write("\t".join(r) + "\n")
    return 0
