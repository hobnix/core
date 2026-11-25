#!/usr/bin/env python3
"""State folder of an extension service that runs as a dynamic user (#1134, slice S1). Python stdlib only, root side.

The state of a service lives in systemd's StateDirectory: the real folder is /var/lib/private/hs-ext/<name>, /var/lib/hs-ext/<name> is the
public path and /var/lib/hs/<name> (the old path, kept for root tools) becomes a link to it. The move is ONE atomic rename, done once, never a
copy; two folders at once or another file system is refused and nothing on disk changes. The bridge of a service calls it before every start
(ext_service.py svc_run). On disk the folder is owned by nobody (65534), mode 0700 (what systemd makes for a DynamicUser; VM run 2026-11-25): only
inside the unit, through systemd's idmapped mount at /var/lib/hs-ext/<name>, is it the dynamic user's, so the unit never binds it. Not tested on hardware yet.

  ext_state.py prepare <name>   the one-time move: prints "moved|linked|fresh|ok<TAB>text", or the problem on stderr and exit 1
  ext_state.py link <name>      after the unit runs: make the old path a link when it is still missing
  ext_state.py repair <name>    give files of the state folder that a root tool made back to the owner of the top folder

Knobs for tests: HS_STATE_DIR (old root, /var/lib/hs), HS_EXT_STATE_DIR (/var/lib/hs-ext), HS_PRIVATE_DIR (/var/lib/private).
Problems start with a code: ext.state-conflict (both folders exist, wrong link, not a folder), ext.state-move-failed (other file system),
ext.state-reserved (the name is a core folder), ext.state-link-failed.
"""
import errno
import os
import re
import stat
import sys

NAME_RE = re.compile(r"[a-z][a-z0-9-]{0,40}")   # used with fullmatch: "$" would let a trailing newline pass

# What the core itself keeps directly under /var/lib/hs (read from scripts/, rust/, capabilities/, web/, configuration.nix, 2026-11-24). A package of
# this name would get a core folder renamed away and chowned to its user (`disks` is the whole array), so prepare refuses it before any change.
# tests/ext-state.sh scans the sources for every /var/lib/hs/<x> and fails when one is missing here (it cannot go stale: it reads the code).
# Not the same as the list of reserved package names: the official packages (posters, media-hub) are fine and must stay allowed.
RESERVED = frozenset("""adopting api-tokens apps apps-autoupdate backup capabilities config deck detached disks docker ext ext-svc expiry generated
health heartbeat hs hs-ext iso jobs last-rebuild live luks machine matrix metrics migrate nodes notify packages parity pci pkg pkg-events ports private
recovering remote removals removed restic scrub selftest services settings share snapshots state sync tailscale testlab vault vps
current repos keys previous lock golden docs-site index index-cache iso-cache runs src src-old reports homepage-hide incident-paused disks-seen
dhcp-ranges cf-dns-api-token dc-ca-key grafana-admin vps-key zoraxy-admin unifi unifi-write-networks matrix-hook media-ntfy node-known-hosts
pkg-index-state update-channel vps-known-hosts wear-cache ext-emit ext-cursors ext-snapshots setup-choice""".split())
RESERVED_PREFIXES = ("backup-", "bulk-", "disk-", "docker-", "health-", "heartbeat-", "live-", "luks-", "machine-", "migrate-", "notify-", "parity-",
                     "pci-", "ports-", "remote-", "restic-", "scrub-", "selftest-", "services-", "share-", "snapshots-", "stat-", "sync-", "tailscale-",
                     "testlab-", "vault-", "last-", "capabilities-", "api-", "apps-", "deck-", "ext-", "node-", "recipe-", "unifi-", "vps-", "zoraxy-",
                     "pkg-", "iso-", "wear-")


def _bad_name(name):
    """None for a usable package name, else the problem text."""
    if not isinstance(name, str) or not NAME_RE.fullmatch(name):
        return "ext.state-conflict: %r is not a valid package name" % (name,)
    if name in RESERVED or name.startswith(RESERVED_PREFIXES):
        return "ext.state-reserved: %s is the name of a folder the server itself keeps in /var/lib/hs; nothing was changed" % name
    return None


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
    """(status, problem): status moved, linked, fresh or ok; problem a text or None. Every step is idempotent. Any other file system error is a
    problem too (never an exception): the caller does not start the service."""
    try:
        return _prepare(name)
    except OSError as e:
        return None, "ext.state-move-failed: the state folder of %r could not be prepared (%s: %s)" % (name, e.filename, e.strerror)


def _close(folder):
    """The top folder of a state that is about to appear under /var/lib/hs-ext becomes 0700 (root). Until the first start systemd has not taken it over
    (it makes it nobody:0700 then), and a root-owned 0755 folder would let every other dynamic user read the state. The files inside are not touched:
    nothing below a 0700 folder is reachable for them. Opened without following a link; a failure is a problem, nothing is moved. Returns the mode it had (a failed move puts it back)."""
    fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        mode = stat.S_IMODE(os.fstat(fd).st_mode)
        if mode & 0o077:
            os.fchmod(fd, 0o700)
        return mode
    finally:
        os.close(fd)


def _prepare(name):
    bad = _bad_name(name)
    if bad:
        return None, bad
    old, pub, priv, ext = _paths(name)
    os.makedirs(ext, 0o755, exist_ok=True)
    if os.path.islink(old):
        target = os.readlink(old)
        if target == pub:
            return "ok", None
        return None, "ext.state-conflict: %s is a link to %s, not %s" % (old, target, pub)
    if os.path.isdir(old):
        if os.path.lexists(pub) or os.path.lexists(priv):
            return None, "ext.state-conflict: both %s and %s exist; nothing was moved" % (old, pub if os.path.lexists(pub) else priv)
        was = _close(old)
        try:
            os.rename(old, pub)
        except OSError as e:
            os.chmod(old, was)    # a failed move changes nothing
            if e.errno == errno.EXDEV:
                return None, "ext.state-move-failed: %s is on another file system than %s; nothing was moved" % (old, pub)
            return None, "ext.state-move-failed: %s could not be moved to %s (%s); nothing was moved" % (old, pub, e.strerror)
        _fsync_dir(ext)
        _fsync_dir(os.path.dirname(old))
        os.symlink(pub, old)
        return "moved", None
    if os.path.lexists(old):
        return None, "ext.state-conflict: %s is not a folder" % old
    # old is missing: finish a move that stopped after the rename, or this is a first start
    if os.path.isdir(pub) and not os.path.islink(pub):
        _close(pub)    # a folder left open by an earlier version or a restore: closed before the next start
    if os.path.lexists(pub) or os.path.lexists(priv):
        os.makedirs(os.path.dirname(old), exist_ok=True)
        os.symlink(pub, old)
        return "linked", None
    return "fresh", None   # no link yet: a dangling one would break `mkdir -p` of root tools; link_after_start makes it


def link_after_start(name):
    """Called when the unit runs: old path missing and the public folder there -> make the link. Errors are returned, not raised."""
    bad = _bad_name(name)
    if bad:
        return bad
    old, pub, _priv, _ext = _paths(name)
    try:
        if not os.path.lexists(old) and os.path.lexists(pub):
            os.makedirs(os.path.dirname(old), exist_ok=True)
            os.symlink(pub, old)
    except OSError as e:
        return "ext.state-link-failed: %s: %s" % (old, e.strerror)
    return None


def repair_owner(name, limit=100000):
    """(changed, problem): chown what a root tool left behind to the owner of the top folder. Never follows a link, never chmods, and never changes
    a file that has a second name (a hard link): the other name may be outside the folder, and the service would own that file."""
    bad = _bad_name(name)
    if bad:
        return 0, bad
    _old, pub, priv, _ext = _paths(name)
    if not os.path.lexists(pub) or (os.path.isdir(pub) and not os.path.islink(pub) and not os.path.lexists(priv)):
        return 0, None   # no state, or just moved: systemd takes the folder into the private root (and chowns it) at the start
    real = os.path.realpath(pub)
    if real != os.path.realpath(priv):
        return 0, "ext.state-conflict: %s resolves to %s, not %s; owners not touched" % (pub, real, priv)
    try:
        top = os.lstat(real)
    except FileNotFoundError:
        return 0, None
    except OSError as e:
        return 0, "repair failed on %s: %s" % (real, e.strerror)
    if top.st_uid == 0:
        return 0, None   # first start: systemd chowns the tree itself
    changed = seen = 0
    linked = []

    # fwalk works on directory descriptors and does not follow links: a folder the service swaps for a link while we walk is not entered, and
    # every change is made relative to the descriptor of its folder (follow_symlinks=False), never through a path the service could redirect.
    for root, dirs, files, rootfd in os.fwalk(real, follow_symlinks=False):
        for n in dirs + files:   # dirs holds links to folders too: they are changed as links
            seen += 1
            if seen > limit:
                return changed, "repair stopped after %d entries" % limit
            try:
                st = os.stat(n, dir_fd=rootfd, follow_symlinks=False)
                if st.st_uid != top.st_uid or st.st_gid != top.st_gid:
                    if not stat.S_ISDIR(st.st_mode) and st.st_nlink > 1:
                        linked.append(os.path.join(root, n))
                        continue
                    os.chown(n, top.st_uid, top.st_gid, dir_fd=rootfd, follow_symlinks=False)
                    changed += 1
            except OSError as e:
                return changed, "repair failed on %s: %s" % (os.path.join(root, n), e.strerror)
    if linked:
        return changed, "repair left %d file(s) with a second hard link as they are, first: %s" % (len(linked), linked[0])
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
