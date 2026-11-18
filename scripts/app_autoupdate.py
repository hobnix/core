#!/usr/bin/env python3
"""Automatic app updates (docs/PLAN-app-lifecycle.md step 13, D12; EXPERIMENTAL, hidden, off, not tested on hardware).

  app_autoupdate.py [--dry-run] [--any-time]

Runs from a timer (scripts/apps-autoupdate.sh). Does nothing unless the setting appsAutoupdateEnabled is true AND the local time is inside the
quiet window (setting appsAutoupdateWindow, default 03:00-05:00; --any-time skips only this check, for tests). Then, for every installed app whose
policy is `automatic`:
  1. only an app of a DEFAULT repository (the package's recorded repository is one of config/package-repos.toml); never an added one;
  2. only a patch or minor change: a different major version (the app, or the package) is never applied, it becomes ONE notification;
     a release that changes `needs`/`requires`, commands.tsv, [web.*] or asks for new permissions is not applied either (one notification);
  3. a snapshot of the instance (manage-ct.sh --snapshot autoupdate-<date>), then `hs pkg update <name> --yes`, then `hs recipe <name>`;
  4. the declared health check (`hs sys apps health`, waits up to HS_AUTOUPDATE_WAIT s, default 60);
  5. on a failure: restore the snapshot, put the previous package copy back (`pkg rollback`), set the policy to notify, send ONE message.
A message is sent once per app and reason and version (/var/lib/hs/apps-autoupdate.json), so the next night is quiet.
Exit 0 always (a timer unit must not fail because an app did; the push message says so).
Test knobs: HS_STATE_DIR, HS_SETTINGS_DIR, HS_PKG_CMD, HS_MANAGE_CT, HS_RECIPE_CMD, HS_HEALTH_CMD, HS_NOTIFY_CMD, HS_REPOS_FILE, HS_AUTOUPDATE_NOW (HH:MM),
HS_AUTOUPDATE_WAIT, plus those of app_version.py.
"""
import datetime
import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import app_version as av  # noqa: E402

try:
    import fcntl
except ImportError:  # not on Linux: no lock (tests on other systems only)
    fcntl = None

try:
    import tomllib
except ImportError:  # pragma: no cover
    tomllib = None


def setting(key, default=""):
    d = os.environ.get("HS_SETTINGS_DIR") or os.path.join(av.state_dir(), "settings")
    try:
        with open(os.path.join(d, key), encoding="utf-8") as f:
            return f.readline().strip() or default
    except OSError:
        return default


def in_window(now, window):
    """now 'HH:MM'; window 'HH:MM-HH:MM' (may pass midnight). A window that does not parse falls back to the default."""
    m = re.match(r"^(\d\d):(\d\d)-(\d\d):(\d\d)$", window or "")
    if not m:
        m = re.match(r"^(\d\d):(\d\d)-(\d\d):(\d\d)$", "03:00-05:00")
    a, b = int(m[1]) * 60 + int(m[2]), int(m[3]) * 60 + int(m[4])
    h, mi = now.split(":")
    n = int(h) * 60 + int(mi)
    return a <= n < b if a <= b else (n >= a or n < b)


def cmd_of(env, default):
    return shlex.split(os.environ[env]) if os.environ.get(env) else default


def sh(cmd, timeout=1800):
    """(returncode, stdout, stderr); a command that cannot start is 127."""
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError) as e:
        return 127, "", str(e)
    return r.returncode, r.stdout, r.stderr


def pkg_cmd():
    return cmd_of("HS_PKG_CMD", ["python3", "-I", os.path.join(HERE, "pkg.py")])


def default_repos():
    f = os.environ.get("HS_REPOS_FILE") or os.path.join(os.path.dirname(HERE), "config", "package-repos.toml")
    try:
        with open(f, "rb") as fh:
            return {r.get("name") for r in tomllib.load(fh).get("repo", [])}
    except (OSError, ValueError, AttributeError):
        return set()


def recorded_repo(name):
    try:
        with open(os.path.join(av.state_dir(), "packages", "installed.toml"), "rb") as fh:
            return (tomllib.load(fh).get("package", {}).get(name) or {}).get("repo")
    except (OSError, ValueError, AttributeError):
        return None


def stored_policy(inst):
    try:
        with open(av.record_path(inst), encoding="utf-8") as f:
            for ln in av.top_lines(f.read()):
                m = re.match(r'^policy\s*=\s*"([a-z]+)"\s*$', ln)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return ""


def major(v):
    m = re.match(r"^v?(\d+)", v or "")
    return int(m.group(1)) if m else None


def kv(lines):
    d = {}
    for ln in lines.splitlines():
        p = ln.split("\t")
        if len(p) >= 2 and p[0] not in d:
            d[p[0]] = p[1]
    return d


class Seen:
    """One message per app, reason and version."""

    def __init__(self):
        self.path = os.path.join(av.state_dir(), "apps-autoupdate.json")
        try:
            with open(self.path, encoding="utf-8") as f:
                self.d = json.load(f)
        except (OSError, ValueError):
            self.d = {}

    def new(self, inst, key):
        return self.d.get(inst) != key

    def mark(self, inst, key):
        self.d[inst] = key
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path + ".new", "w", encoding="utf-8") as f:
            json.dump(self.d, f)
        os.replace(self.path + ".new", self.path)


def notify(title, msg, category):
    cmd = cmd_of("HS_NOTIFY_CMD", ["bash", os.path.join(HERE, "notify.sh"), "--category", category])
    sh(cmd + [title, msg], 60)


def blocked_by_diff(text):
    """Why a package diff may not be applied unattended (PLAN-packages trust rule), or ''."""
    if "NEW permissions" in text:
        return "it asks for new permissions"
    cur = ""
    for ln in text.splitlines():
        m = re.match(r"^diff --git a/(\S+) b/", ln)
        if m:
            cur = m[1]
            if cur.endswith("commands.tsv"):
                return "it changes its commands"
            continue
        if cur.endswith("package.toml") and re.match(r"^[+-](needs|requires|permissions)\b|^[+-]\s*\[web[.\]]", ln):
            return "it changes what it needs or its web pages"
    return ""


def health_of(inst, wait):
    """healthy | unhealthy | none (no declaration)"""
    cmd = cmd_of("HS_HEALTH_CMD", ["bash", os.path.join(HERE, "apps-list.sh"), "--health"])
    end = time.time() + wait
    while True:
        rc, out, _ = sh(cmd, 60)
        h = ""
        for ln in out.splitlines():
            p = ln.split("\t")
            if p[0] == inst and len(p) > 1:
                h = p[1]
        if not h:
            return "none"
        if h == "healthy":
            return "healthy"
        if time.time() >= end:
            return "unhealthy"
        time.sleep(min(5, max(0.2, end - time.time())))


def update_one(r, market, seen, dry):
    name, inst = r["name"], r["instance"]
    pkg = pkg_cmd()
    ct = cmd_of("HS_MANAGE_CT", ["bash", os.path.join(HERE, "manage-ct.sh")])
    repo = recorded_repo(name)
    if repo not in default_repos():
        return "skip: %s is not from a default repository" % name
    row = market.get(name)
    target, pkg_new = r["offered"], None
    if row and row[5] == "update":
        rc, out, _ = sh(pkg + ["show", name], 120)
        info = kv(out) if rc == 0 else {}
        if info.get("status") != "ok":
            return "skip: %s: the new release cannot be read" % name
        pkg_new = info.get("version")
        target = info.get("app_version") if info.get("app_version", "-") != "-" else r["offered"]
        if info.get("repo") not in default_repos():
            return "skip: %s: the release is not from a default repository" % name
    elif r["offered"] in ("-", "") or r["offered"] == r["running"]:
        return "current: %s" % name
    if r["running"] in ("-", "") or target in ("-", "", None):
        return "skip: %s: the running or the offered version is not known" % name
    new_pkg_major = major(pkg_new) if pkg_new else None
    why = ""
    if major(target) is None or major(target) != major(r["running"]):
        why = "major"
    elif new_pkg_major is not None and row and major(row[4]) is not None and new_pkg_major != major(row[4]):
        why = "major"
    if why:
        key = "major:%s" % target
        if seen.new(inst, key) and not dry:
            notify("App update waiting", "%s %s is a major update (now %s). It is not applied automatically: update it yourself." % (name, target, r["running"]), "info")
            seen.mark(inst, key)
        return "major: %s %s -> %s not applied" % (name, r["running"], target)
    if row and row[5] == "update":
        rc, out, _ = sh(pkg + ["update", name], 120)   # without --yes: prints the diff, then refuses without a terminal
        reason = blocked_by_diff(out)
        if reason:
            key = "manual:%s" % target
            if seen.new(inst, key) and not dry:
                notify("App update waiting", "%s %s is not applied automatically: %s. Update it yourself." % (name, target, reason), "info")
                seen.mark(inst, key)
            return "manual: %s: %s" % (name, reason)
    if dry:
        return "would update: %s %s -> %s" % (name, r["running"], target)

    label = "autoupdate-" + datetime.date.today().strftime("%Y%m%d")
    steps = []

    def fail_update(what):
        # the way back: the instance first (its data), then the package copy, so both agree again
        restored = rc_restore = 0
        if "snapshot" in steps:
            rc_restore, _, _ = sh(ct + [inst, "--restore", label], 900)
        if "package" in steps:
            sh(pkg + ["rollback", name], 120)
        av.set_policy(inst, "notify")
        key = "failed:%s" % target
        if seen.new(inst, key):
            tail = "It was put back as it was." if rc_restore == 0 else "Putting it back FAILED: check the instance %s and its snapshot %s." % (inst, label)
            notify("App update failed", "%s %s did not work (%s). %s Automatic updates are off for it." % (name, target, what, tail), "problem")
            seen.mark(inst, key)
        return "failed: %s: %s" % (name, what)

    rc, _, _ = sh(ct + [inst, "--snapshot", label], 900)
    if rc != 0:
        return fail_update("no snapshot could be made")
    steps.append("snapshot")
    if row and row[5] == "update":
        rc, _, _ = sh(pkg + ["update", name, "--yes"], 600)
        if rc != 0:
            return fail_update("the package could not be updated")
        steps.append("package")
    recipe = cmd_of("HS_RECIPE_CMD", ["bash", os.path.join(HERE, "recipe.sh")]) + [name] + (["--name", inst] if inst != name else [])
    rc, _, _ = sh(recipe, 3600)
    if rc != 0:
        return fail_update("its recipe failed")
    h = health_of(inst, int(os.environ.get("HS_AUTOUPDATE_WAIT", "60") or 60))
    if h == "unhealthy":
        return fail_update("it does not answer its health check")
    seen.mark(inst, "done:%s" % target)
    return "updated: %s %s -> %s" % (name, r["running"], target)


def main(argv):
    dry = "--dry-run" in argv
    if setting("appsAutoupdateEnabled") != "true":
        return 0
    now = os.environ.get("HS_AUTOUPDATE_NOW") or datetime.datetime.now().strftime("%H:%M")
    if "--any-time" not in argv and not in_window(now, setting("appsAutoupdateWindow", "03:00-05:00")):
        return 0
    os.makedirs(av.state_dir(), exist_ok=True)
    lock = open(os.path.join(av.state_dir(), "apps-autoupdate.lock"), "w")
    try:
        if fcntl:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0
    todo = [r for r in av.rows() if stored_policy(r["instance"]) == "automatic"]
    if not todo:
        return 0
    if not dry:
        sh(pkg_cmd() + ["fetch"], 600)
    rc, out, _ = sh(pkg_cmd() + ["market"], 120)
    market = {}
    for ln in out.splitlines() if rc == 0 else []:
        p = ln.split("\t")
        if len(p) >= 6:
            market[p[0]] = p
    seen = Seen()
    for r in todo:
        try:
            print(update_one(r, market, seen, dry))
        except Exception as e:  # noqa: BLE001 - one app never stops the others
            print("error: %s: %s" % (r["name"], e))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
