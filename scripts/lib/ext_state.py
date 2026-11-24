#!/usr/bin/env python3
"""State folder of an extension service that runs as a dynamic user (#1134, slice S1). Python stdlib only, root side.

The state of a service lives in systemd's StateDirectory: the real folder is /var/lib/private/hs-ext/<name>, /var/lib/hs-ext/<name> is the
public path and /var/lib/hs/<name> (the old path, kept for root tools) becomes a link to it. The move is ONE atomic rename, done once, never a
copy; two folders at once or another file system is refused and nothing on disk changes. Nothing calls this yet (the services still run as root).
Not tested on hardware yet.

  ext_state.py prepare <name>   the one-time move: prints "moved|linked|fresh|ok<TAB>text", or the problem on stderr and exit 1
  ext_state.py link <name>      after the unit runs: make the old path a link when it is still missing
  ext_state.py repair <name>    give files of the state folder that a root tool made back to the owner of the top folder

Knobs for tests: HS_STATE_DIR (old root, /var/lib/hs), HS_EXT_STATE_DIR (/var/lib/hs-ext), HS_PRIVATE_DIR (/var/lib/private).
Problems start with a code: state_conflict (both folders exist, wrong link, not a folder), state_move_failed (other file system).
"""
import errno
import os
import re
import sys

NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,40}$")


def _paths(name):
    old = os.path.join(os.environ.get("HS_STATE_DIR", "/var/lib/hs"), name)
    ext = os.environ.get("HS_EXT_STATE_DIR", "/var/lib/hs-ext")
    priv = os.path.join(os.environ.get("HS_PRIVATE_DIR", "/var/lib/private"), "hs-ext", name)
    return old, os.path.join(ext, name), priv, ext


def _fsync_dir(path):
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def prepare(name):
    """(status, problem): status moved, linked, fresh or ok; problem a text or None. Every step is idempotent."""
    if not isinstance(name, str) or not NAME_RE.match(name):
        return None, "state_conflict: %r is not a valid package name" % (name,)
    old, pub, priv, ext = _paths(name)
    os.makedirs(ext, 0o755, exist_ok=True)
    if os.path.islink(old):
        target = os.readlink(old)
        if target == pub:
            return "ok", None
        return None, "state_conflict: %s is a link to %s, not %s" % (old, target, pub)
    if os.path.isdir(old):
        if os.path.lexists(pub) or os.path.lexists(priv):
            return None, "state_conflict: both %s and %s exist; nothing was moved" % (old, pub)
        try:
            os.rename(old, pub)
        except OSError as e:
            if e.errno == errno.EXDEV:
                return None, "state_move_failed: %s is on another file system than %s; nothing was moved" % (old, pub)
            return None, "state_move_failed: %s could not be moved to %s (%s); nothing was moved" % (old, pub, e.strerror)
        _fsync_dir(ext)
        _fsync_dir(os.path.dirname(old))
        os.symlink(pub, old)
        return "moved", None
    if os.path.lexists(old):
        return None, "state_conflict: %s is not a folder" % old
    # old is missing: finish a move that stopped after the rename, or this is a first start
    if os.path.lexists(pub) or os.path.lexists(priv):
        os.makedirs(os.path.dirname(old), exist_ok=True)
        os.symlink(pub, old)
        return "linked", None
    return "fresh", None   # no link yet: a dangling one would break `mkdir -p` of root tools; link_after_start makes it


def link_after_start(name):
    """Called when the unit runs: old path missing and the public folder there -> make the link. Errors are returned, not raised."""
    if not isinstance(name, str) or not NAME_RE.match(name):
        return "state_conflict: %r is not a valid package name" % (name,)
    old, pub, _priv, _ext = _paths(name)
    try:
        if not os.path.lexists(old) and os.path.lexists(pub):
            os.makedirs(os.path.dirname(old), exist_ok=True)
            os.symlink(pub, old)
    except OSError as e:
        return "state_link_failed: %s: %s" % (old, e.strerror)
    return None


def repair_owner(name, limit=100000):
    """(changed, problem): chown what a root tool left behind to the owner of the top folder. Never follows a link, never chmods."""
    if not isinstance(name, str) or not NAME_RE.match(name):
        return 0, "state_conflict: %r is not a valid package name" % (name,)
    _old, pub, priv, _ext = _paths(name)
    if not os.path.lexists(pub):
        return 0, None
    real = os.path.realpath(pub)
    if real != os.path.realpath(priv):
        return 0, "state_conflict: %s resolves to %s, not %s; owners not touched" % (pub, real, priv)
    top = os.lstat(real)
    if top.st_uid == 0:
        return 0, None   # first start: systemd chowns the tree itself
    changed = seen = 0

    def fix(path):
        nonlocal changed
        st = os.lstat(path)
        if st.st_uid != top.st_uid or st.st_gid != top.st_gid:
            os.lchown(path, top.st_uid, top.st_gid)
            changed += 1

    for root, dirs, files in os.walk(real, followlinks=False):
        for n in dirs + files:   # dirs holds links to folders too: lchown touches the link itself
            seen += 1
            if seen > limit:
                return changed, "repair stopped after %d entries" % limit
            try:
                fix(os.path.join(root, n))
            except OSError as e:
                return changed, "repair failed on %s: %s" % (os.path.join(root, n), e.strerror)
    return changed, None


def main(argv):
    if len(argv) != 2 or argv[0] not in ("prepare", "link", "repair"):
        sys.stderr.write("usage: ext_state.py prepare|link|repair <name>\n")
        return 2
    cmd, name = argv
    if cmd == "prepare":
        status, problem = prepare(name)
        text = "-"
    elif cmd == "link":
        problem = link_after_start(name)
        status, text = "ok", "-"
    else:
        changed, problem = repair_owner(name)
        status, text = "ok", str(changed)
    if problem:
        sys.stderr.write(problem + "\n")
        return 1
    sys.stdout.write("%s\t%s\n" % (status, text))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
