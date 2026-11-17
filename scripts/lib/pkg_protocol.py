"""The command protocol and service keys of a package.toml (docs/PLAN-extensions-access.md step 1, ADR 0010 and 0011, hobnix/server#197).
Python stdlib only, no CLI. Parse and validate only: nothing runs these keys yet (the dispatcher is step 2, the service unit step 4).

Keys (all optional; a manifest without them keeps the shell contract and validates unchanged):
  protocol = [1]                 the command protocol versions the package speaks (only 1 exists)
  [service]                      one supervised process (ADR 0011 rule 1)
    exec            = "@/svc.py"   a file in the package (@/file) or a path under scripts/, no "..", no absolute path
    subscribe       = ["pkg.*"]    list of event kind globs, may be empty
    health_interval = 30           seconds, 5 to 300 (default 30)
  commands.tsv flag `timeout:<seconds>` on a row: 1 to 3600 (ADR 0010 rule 6; default 30 s is the dispatcher's)

D9: a manifest may use `protocol` or `[service]` only if it requires an API level at or above PROTOCOL_LEVEL (the level step 2 bumps to).

manifest_problems(m, folder=None, level=PROTOCOL_LEVEL) -> [text]; `folder` = the package folder (commands.tsv is read only then).
"""
import os
import re

PROTOCOL_LEVEL = 10
PROTOCOLS = (1,)
SERVICE_KEYS = {"exec", "subscribe", "health_interval"}
HEALTH_RANGE = (5, 300)
TIMEOUT_RANGE = (1, 3600)
GLOB = re.compile(r"^[a-z0-9*][a-z0-9.*_-]{0,79}$")
REQUIRES = re.compile(r"^>=\s*(\d+)$")
TIMEOUT_FLAG = re.compile(r"^timeout:(.*)$")


def _int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _exec_ok(s):
    if not isinstance(s, str) or not s or "\t" in s or "\n" in s or ".." in s.split("/") or s.startswith("/"):
        return False
    return s.startswith("@/") and len(s) > 2 or s.startswith("scripts/")


def _requires(m):
    rq = REQUIRES.match(str(m.get("requires_core", "")))
    return int(rq.group(1)) if rq else 0


def timeout_problems(path):
    """[text] for the `timeout:<seconds>` flags of a commands.tsv (column 7 of a row, comma separated flags)."""
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return out
    for i, line in enumerate(lines, 1):
        c = line.split("\t")
        if line.startswith("#") or len(c) < 7:
            continue
        seen = 0
        for fl in c[6].split(","):
            mt = TIMEOUT_FLAG.match(fl.strip())
            if not mt:
                continue
            seen += 1
            v = mt.group(1)
            if not re.fullmatch(r"\d{1,5}", v) or not TIMEOUT_RANGE[0] <= int(v) <= TIMEOUT_RANGE[1]:
                out.append("commands.tsv line %d: timeout must be a whole number of seconds from %d to %d" % (i, *TIMEOUT_RANGE))
        if seen > 1:
            out.append("commands.tsv line %d: timeout is given twice" % i)
    return out


def manifest_problems(m, folder=None, level=PROTOCOL_LEVEL):
    out = []
    uses = []
    if "protocol" in m:
        uses.append("protocol")
        p = m["protocol"]
        if not isinstance(p, list) or not p or not all(_int(x) for x in p):
            out.append("protocol must be a list of numbers, [1]")
        elif sorted(set(p)) != list(PROTOCOLS) or len(p) != len(set(p)):
            out.append("protocol must be [1] (the only protocol version there is)")
    if "service" in m:
        uses.append("[service]")
        s = m["service"]
        if not isinstance(s, dict):
            out.append("service must be a [service] table")
        else:
            if "exec" not in s:
                out.append("service: exec missing")
            elif not _exec_ok(s["exec"]):
                out.append("service: exec must be @/<file> in the package or a path under scripts/ (no .., no absolute path)")
            if "subscribe" in s:
                sub = s["subscribe"]
                if not isinstance(sub, list) or not all(isinstance(x, str) and GLOB.match(x) for x in sub):
                    out.append("service: subscribe must be a list of event kind globs (lower-case words, dots and *)")
            if "health_interval" in s:
                h = s["health_interval"]
                if not _int(h) or not HEALTH_RANGE[0] <= h <= HEALTH_RANGE[1]:
                    out.append("service: health_interval must be a whole number of seconds from %d to %d" % HEALTH_RANGE)
            for k in sorted(set(s) - SERVICE_KEYS):
                out.append("service: unknown key %s" % k)
    if uses and _requires(m) < level:
        out.append('%s needs requires_core = ">=%d" or higher (D9: a package that speaks the protocol states the API level it came with)'
                   % (" and ".join(uses), level))
    if folder:
        out += timeout_problems(os.path.join(folder, "commands.tsv"))
    return out
