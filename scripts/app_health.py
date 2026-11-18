#!/usr/bin/env python3
"""The declared health of apps (docs/PLAN-app-lifecycle.md Q4): runs the check of `[app.health]` against the instance address.

  app_health.py --recipes F --running F --addr F
    name<TAB>word, one line per recipe whose package.toml declares [app.health]; word: healthy | unhealthy | stopped
  F: recipes = `hs sys recipes list` rows (name, description, instances, state); running = `incus list -f csv -c ns` (name,STATE);
     addr = lines `instance,address`.
check container: the instance runs. tcp: the port accepts a connection. http: any 2xx or 3xx answer (redirects are not followed).
Test knob: HS_APP_HEALTH_HOST sends every check to that host (a fake target on 127.0.0.1) instead of the instance address.
"""
import http.client
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg  # noqa: E402
import pkg_states  # noqa: E402


def probe(check, host, port, path="/", timeout=5):
    """True when the target answers as healthy."""
    try:
        if check == "tcp":
            with socket.create_connection((host, port), timeout=timeout):
                return True
        if check == "http":
            c = http.client.HTTPConnection(host, port, timeout=timeout)
            try:
                c.request("GET", path or "/")
                return 200 <= c.getresponse().status < 400
            finally:
                c.close()
    except (OSError, http.client.HTTPException):
        return False
    return False


def health_of(declared, instances, running, addr, host_override=None, probe_fn=probe):
    """declared: the [app.health] table; instances: the instance names; running: {name: state}; addr: {name: address}."""
    if not instances or any(running.get(c) != "running" for c in instances):
        return "stopped"
    chk = declared.get("check", "container")
    if chk == "container":
        return "healthy"
    host = host_override or addr.get(instances[0])
    if not host:
        return "unhealthy"
    ok = probe_fn(chk, host, int(declared["port"]), declared.get("path", "/"), int(declared.get("timeout", 5)))
    return "healthy" if ok else "unhealthy"


def addresses(path):
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for ln in f:
                n, _, a = ln.strip().partition(",")
                if n and a:
                    out[n] = a.split()[0]
    except OSError:
        pass
    return out


def main(argv):
    o = {}
    i = 0
    while i < len(argv):
        if argv[i] in ("--recipes", "--running", "--addr") and i + 1 < len(argv):
            o[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            print("usage: app_health.py --recipes F --running F --addr F", file=sys.stderr)
            return 1
    recipes = {r[0]: r for r in pkg_states.rows(o.get("recipes")) if r}
    running = pkg_states.containers(o.get("running"))
    addr = addresses(o.get("addr", ""))
    override = os.environ.get("HS_APP_HEALTH_HOST") or None
    seen = set()
    for _, m in pkg.manifests():
        name = m.get("name")
        h = (m.get("app") or {}).get("health") if m.get("kind") == "recipe" else None
        if name in seen or not isinstance(h, dict) or name not in recipes:
            continue
        seen.add(name)
        cts = pkg_states.col(recipes[name], 2)
        instances = [] if cts == "-" else [c for c in cts.split(",") if c in running]
        sys.stdout.write(f"{name}\t{health_of(h, instances, running, addr, override)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
