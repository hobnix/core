#!/usr/bin/env python3
"""Package version, app version and update policy per installed app (docs/PLAN-app-lifecycle.md Q6, D11-D13). Read only except `policy`.

  app_version.py list                       name instance package_version app_offered app_running policy state   (empty field: -)
  app_version.py policy <instance> [value]  print or set the policy (notify | pinned) in the app record
  app_version.py plan update <name>         the lines of `hs sys apps plan update <name>` (nothing runs, nothing is written)
  app_version.py summary                    one `hs notify` message for the apps that have an update offered
The running version is read on this server only (D11): image-tag = tag of the pinned image, http-json = GET on the app address + JSON pointer,
exec = a command inside the instance. No call goes anywhere but the app itself. Anything that fails or is absent is `-`.
Test knobs: HS_RECIPES_DIR, HS_STATE_DIR, HS_INCUS, HS_APP_HEALTH_HOST, HS_APP_IMAGE_TAG_CMD (prints the tag for the instance given as $1),
HS_RECIPE_CMD (replaces `bash scripts/recipe.sh`), HS_NOTIFY_CMD (replaces `bash scripts/notify.sh`), HS_RECIPES_LIST (replaces recipes-list.sh).
"""
import http.client
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
WORD = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")
INSTANCE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$")
VERSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+~:-]{0,39}$")
LOOSE = re.compile(r"v?\d+(?:\.\d+)+[A-Za-z0-9._+~-]*")
POLICIES = ("notify", "pinned")


def state_dir():
    return os.environ.get("HS_STATE_DIR", "/var/lib/hs")


def incus():
    return shlex.split(os.environ.get("HS_INCUS", "incus"))


def recipe_dirs():
    if os.environ.get("HS_RECIPES_DIR"):
        return [os.environ["HS_RECIPES_DIR"]]
    d = [os.path.join(os.path.dirname(HERE), "packages"), "/etc/nixos/packages", os.path.join(state_dir(), "packages", "current")]
    return [x for x in d if os.path.isdir(x)]


def manifest(name):
    """The package.toml of a recipe (the first folder that has it wins), {} when there is none."""
    if not WORD.match(name):
        return {}
    for d in recipe_dirs():
        p = os.path.join(d, name, "package.toml")
        if os.path.isfile(p):
            try:
                with open(p, "rb") as f:
                    return tomllib.load(f)
            except (OSError, tomllib.TOMLDecodeError):
                return {}
    return {}


def run(cmd, timeout):
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def clean_version(text):
    """One version word out of whatever the app printed, or None."""
    if not text:
        return None
    line = next((x.strip() for x in text.splitlines() if x.strip()), "")
    if VERSION.match(line):
        return line
    m = LOOSE.search(line)
    return m.group(0) if m and VERSION.match(m.group(0)) else None


def recipes_rows():
    cmd = shlex.split(os.environ["HS_RECIPES_LIST"]) if os.environ.get("HS_RECIPES_LIST") else ["bash", os.path.join(HERE, "recipes-list.sh"), "--list"]
    out = run(cmd, 60) or ""
    return [ln.split("\t") for ln in out.splitlines() if ln.count("\t") >= 3]


def existing():
    out = run(incus() + ["list", "-f", "csv", "-c", "n"], 20)
    return None if out is None else {ln.strip().strip('"') for ln in out.splitlines() if ln.strip()}


def addresses():
    out = run(incus() + ["list", "-f", "csv", "-c", "n4"], 20) or ""
    res = {}
    for ln in out.splitlines():
        n, _, a = ln.partition(",")
        a = a.strip().strip('"').split()
        if n and a:
            res[n.strip('"')] = a[0]
    return res


def instances():
    """[(recipe, instance)] of the installed apps: the instances of a recipe that is installed (or partly) and that exist."""
    have = existing()
    res = []
    for r in recipes_rows():
        if r[3] not in ("installed", "partly") or r[2] in ("-", ""):
            continue
        for c in r[2].split(","):
            if c == "docker":   # an app hosted in the docker container has its own record; not covered here yet
                continue
            if have is None or c in have:
                res.append((r[0], c))
    return res


# ── the app record ──
def record_path(inst):
    return os.path.join(state_dir(), "apps", inst + ".toml")


def top_lines(text):
    """The lines before the first [[created]] block."""
    out = []
    for ln in text.splitlines(keepends=True):
        if ln.startswith("[[created]]"):
            break
        out.append(ln)
    return out


def policy_of(inst, default="notify"):
    try:
        with open(record_path(inst), encoding="utf-8") as f:
            for ln in top_lines(f.read()):
                m = re.match(r'^policy\s*=\s*"([a-z]+)"\s*$', ln)
                if m:
                    return m.group(1) if m.group(1) in POLICIES else default
    except OSError:
        pass
    return default


def default_policy(m):
    d = ((m.get("app") or {}).get("update") or {}).get("default", "notify")
    return d if d in POLICIES else "notify"


def set_policy(inst, value):
    p = record_path(inst)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    try:
        with open(p, encoding="utf-8", newline="") as f:
            text = f.read()
    except OSError:
        text = 'app = "%s"\n' % inst
    head = top_lines(text)
    rest = text[len("".join(head)):]
    line = 'policy = "%s"\n' % value
    for i, ln in enumerate(head):
        if re.match(r"^policy\s*=", ln):
            head[i] = line
            break
    else:
        if head and not head[-1].endswith("\n"):
            head[-1] += "\n"
        # before a trailing blank line, so the file keeps its look
        k = len(head)
        while k > 0 and not head[k - 1].strip():
            k -= 1
        head.insert(k, line)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), prefix=os.path.basename(p) + ".")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write("".join(head) + rest)
    os.chmod(tmp, 0o644)
    os.replace(tmp, p)


# ── the running version ──
def pointer(doc, ptr):
    for part in ptr.split("/")[1:]:
        part = part.replace("~1", "/").replace("~0", "~")
        if isinstance(doc, list) and part.isdigit() and int(part) < len(doc):
            doc = doc[int(part)]
        elif isinstance(doc, dict) and part in doc:
            doc = doc[part]
        else:
            return None
    return doc if isinstance(doc, (str, int, float)) and not isinstance(doc, bool) else None


def app_port(m):
    app = m.get("app") or {}
    h = app.get("health") or {}
    if isinstance(h.get("port"), int):
        return h["port"]
    for r in (app.get("routes") or {}).values():
        if isinstance(r, dict) and isinstance(r.get("port"), int):
            return r["port"]
    return 80


def running_version(m, inst, addr):
    v = (m.get("app") or {}).get("version")
    if not isinstance(v, dict):
        return None
    src = v.get("source")
    if src == "exec":
        cmd = v.get("command")
        if not isinstance(cmd, list) or not cmd:
            return None
        return clean_version(run(incus() + ["exec", inst, "--"] + [str(x) for x in cmd], 5))
    if src == "image-tag":
        if os.environ.get("HS_APP_IMAGE_TAG_CMD"):
            out = run(shlex.split(os.environ["HS_APP_IMAGE_TAG_CMD"]) + [inst], 5)
        else:
            out = run(incus() + ["exec", inst, "--", "sh", "-c",
                                 "cat /opt/*/compose.y*ml /opt/*/docker-compose.y*ml /opt/apps/*/compose.y*ml 2>/dev/null"], 5)
            out = image_tag(out)
        return clean_version(out)
    if src == "http-json":
        host = os.environ.get("HS_APP_HEALTH_HOST") or addr.get(inst)
        if not host:
            return None
        try:
            c = http.client.HTTPConnection(host, app_port(m), timeout=3)
            try:
                c.request("GET", v.get("path", "/"))
                r = c.getresponse()
                if not 200 <= r.status < 300:
                    return None
                got = pointer(json.loads(r.read(1 << 20).decode("utf-8", "replace")), v.get("pointer", ""))
            finally:
                c.close()
        except (OSError, http.client.HTTPException, ValueError):
            return None
        return clean_version(None if got is None else str(got))
    return None


def image_tag(compose):
    """The tag of the first `image: name:tag` line of a compose file, None when there is none."""
    for ln in (compose or "").splitlines():
        m = re.match(r"^\s*image:\s*[\"']?([^\s\"'#]+)", ln)
        if m:
            ref = m.group(1).split("@")[0]
            tail = ref.rsplit("/", 1)[-1]
            if ":" in tail:
                return tail.rsplit(":", 1)[1]
    return None


def rows():
    """[dict] one per installed instance."""
    addr = None
    res = []
    for name, inst in instances():
        m = manifest(name)
        if (m.get("app") or {}).get("version", {}).get("source") == "http-json" and addr is None:
            addr = addresses()
        offered = m.get("app_version") if isinstance(m.get("app_version"), str) and VERSION.match(m.get("app_version", "")) else None
        running = running_version(m, inst, addr or {})
        policy = policy_of(inst, default_policy(m))
        if policy == "pinned":
            state = "pinned"
        elif offered and running and offered != running:
            state = "update"
        else:
            state = "current"
        res.append({"name": name, "instance": inst, "package": str(m.get("version") or "-"), "offered": offered or "-",
                    "running": running or "-", "policy": policy, "state": state})
    return res


def cmd_list():
    for r in rows():
        sys.stdout.write("\t".join(r[k] for k in ("name", "instance", "package", "offered", "running", "policy", "state")) + "\n")
    return 0


def cmd_policy(args):
    if not args or not INSTANCE.match(args[0]):
        print("usage: hs sys apps policy <instance> [notify|pinned]", file=sys.stderr)
        return 1
    inst = args[0]
    if inst == "docker":
        print("apps that run inside Docker have no update policy yet", file=sys.stderr)
        return 1
    known = os.path.isfile(record_path(inst)) or inst in (existing() or set())
    if not known:
        print("no such app: %s" % inst, file=sys.stderr)
        return 1
    if len(args) == 1:
        owner = next((n for n, i in instances() if i == inst), "")
        sys.stdout.write(policy_of(inst, default_policy(manifest(owner))) + "\n")
        return 0
    if args[1] == "automatic":
        print("automatic updates are not available yet (notify or pinned)", file=sys.stderr)
        return 1
    if args[1] not in POLICIES:
        print("the policy is notify or pinned", file=sys.stderr)
        return 1
    set_policy(inst, args[1])
    subprocess.run(["bash", "-c", '. "$1/lib/live.sh"; live_refresh apps-list', "_", HERE], stdin=subprocess.DEVNULL, capture_output=True, check=False)
    return 0


def refuse(why):
    sys.stdout.write("status\trefused\nreason\t%s\n" % why)
    return 1


def cmd_plan(args):
    if len(args) != 2 or args[0] != "update":
        return refuse("unknown action (update)")
    name = args[1]
    if not WORD.match(name):
        return refuse("not a package name (lower case letters, digits and dashes)")
    m = manifest(name)
    if not m or m.get("kind", "recipe") != "recipe":
        return refuse("%s is not an app of this server" % name)
    mine = [r for r in rows() if r["name"] == name]
    if not mine:
        return refuse("%s is not installed" % name)
    r = mine[0]
    cmd = shlex.split(os.environ["HS_RECIPE_CMD"]) if os.environ.get("HS_RECIPE_CMD") else ["bash", os.path.join(HERE, "recipe.sh")]
    out = run(cmd + [name, "--check"], 120) or ""
    pieces = []
    for ln in out.splitlines():
        mm = re.match(r"^\s*would update:?\s+(.+?)\s+\(([^()]*?)\s*->\s*([^()]*?)\)\s*$", ln)
        if mm:
            pieces.append(mm.groups())
    o = ["status\tok", "heading\tUpdate %s" % (m.get("title") or name), "package\t%s" % name, "version\t%s" % r["package"]]
    for p in pieces:
        o.append("piece\t%s\t%s\t%s" % p)
    if not pieces:
        o.append("note\tnothing to update")
    applied = run(["python3", "-I", os.path.join(HERE, "pkg.py"), "applied"], 20) or ""
    have = next((ln.split("\t")[1] for ln in applied.splitlines() if ln.split("\t")[0] == name and "\t" in ln), "-")
    o.append("package_version\t%s -> %s" % (have or "-", r["package"]))
    o.append("app\t%s -> %s" % (r["running"], r["offered"]))
    o.append("policy\t%s" % r["policy"])
    if r["policy"] == "pinned":
        o.append("note\tthis app is pinned: the update runs only if you start it yourself")
    o.append("step\tsnapshot the instance %s" % r["instance"])
    o.append("step\trun the recipe: hs recipe %s" % name)
    o.append("step\tcheck the app")
    o.append("note\tstarting an update from here comes later")
    sys.stdout.write("\n".join(o) + "\n")
    return 0


def cmd_summary():
    ups = [r for r in rows() if r["state"] == "update"]
    if not ups:
        return 0
    names = ", ".join(r["name"] for r in ups)
    n = len(ups)
    msg = "%d app%s ha%s an update offered: %s" % (n, "" if n == 1 else "s", "s" if n == 1 else "ve", names)
    cmd = shlex.split(os.environ["HS_NOTIFY_CMD"]) if os.environ.get("HS_NOTIFY_CMD") else ["bash", os.path.join(HERE, "notify.sh"), "--category", "info"]
    run(cmd + ["App updates", msg], 60)
    return 0


def main(argv):
    if not argv:
        print("usage: app_version.py list|policy|plan|summary", file=sys.stderr)
        return 1
    if argv[0] == "list":
        return cmd_list()
    if argv[0] == "policy":
        return cmd_policy(argv[1:])
    if argv[0] == "plan":
        return cmd_plan(argv[1:])
    if argv[0] == "summary":
        try:
            return cmd_summary()
        except Exception:  # noqa: BLE001 - a summary never fails the weekly unit
            return 0
    print("usage: app_version.py list|policy|plan|summary", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
