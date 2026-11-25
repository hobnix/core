#!/usr/bin/env python3
"""Put one file into the state folder of a service that runs as a dynamic user, as root, without ever following a link the service planted
(ext_state.py: the folder is the service's, so every name below it is untrusted). Python stdlib only.

  state_put.py same <src> <top> <rel>            exit 0 when the file at <top>/<rel> is a regular file with the content of <src>, 1 when it differs or is missing
  state_put.py put  <src> <top> <rel> <stamp>    write <src> to <top>/<rel>; exit 0, or 2 with the reason on stderr (a problem is never silent)

<top> is the state root (/var/lib/hs/<name>, a link that ONLY root can change: it is resolved once). Below it every folder is opened with O_NOFOLLOW
relative to the descriptor of its parent; a missing folder is made (0700); a link or file where a folder should be is refused. The file is written
to a new name (O_EXCL) and renamed over the old one: a planted link at the destination is replaced, never written through. What was there is moved
aside as <file>.before-restore-<stamp> (renamed, never read or copied). The owner of the new file is the owner of <top>, its mode the mode of <src>.
"""
import os
import stat
import sys

DIRFLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def walk(top, parts, make, owner=None):
    """descriptor of the folder holding the last name; raises OSError (ELOOP/ENOTDIR for a link or file in the way). A folder it makes is 0700 and
    belongs to `owner` (the owner of <top>): the service must be able to enter it (a root-owned 0700 folder would lock it out)."""
    fd = os.open(os.path.realpath(top), os.O_RDONLY | os.O_DIRECTORY)
    try:
        for p in parts:
            try:
                nxt = os.open(p, DIRFLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not make:
                    raise
                os.mkdir(p, 0o700, dir_fd=fd)
                nxt = os.open(p, DIRFLAGS, dir_fd=fd)
                if owner is not None:
                    os.fchown(nxt, owner.st_uid, owner.st_gid)
            os.close(fd)
            fd = nxt
        return fd
    except BaseException:
        os.close(fd)
        raise


def parts_of(rel):
    parts = [x for x in rel.split("/") if x]
    if not parts or any(x in (".", "..") for x in parts):
        raise OSError(0, "bad path " + rel)
    return parts[:-1], parts[-1]


def same(src, top, rel):
    dirs, name = parts_of(rel)
    try:
        fd = walk(top, dirs, False)
    except OSError:
        return 1
    try:
        f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except OSError:
        return 1
    finally:
        os.close(fd)
    with os.fdopen(f, "rb") as a:
        st = os.fstat(a.fileno())
        # never read what the service made: a FIFO would hang, a sparse terabyte would fill the memory. Only a regular file of the size of <src> is compared.
        if not stat.S_ISREG(st.st_mode) or st.st_size != os.stat(src).st_size:
            return 1
        with open(src, "rb") as b:
            while True:
                x, y = a.read(1 << 20), b.read(1 << 20)
                if x != y:
                    return 1
                if not x:
                    return 0


def put(src, top, rel, stamp):
    dirs, name = parts_of(rel)
    if not os.path.lexists(top):    # a fresh install: the state is made like a moved one (0700, root until systemd takes the folder over at the first start)
        os.makedirs(os.path.dirname(top), 0o755, exist_ok=True)
        os.mkdir(top, 0o700)
    owner = os.stat(top)
    mode = stat.S_IMODE(os.stat(src).st_mode)
    fd = walk(top, dirs, True, owner)
    tmp = ".restore-%d-%s" % (os.getpid(), name)
    try:
        try:
            old = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            old = None
        if old is not None:
            if stat.S_ISDIR(old.st_mode):
                raise OSError(0, "%s is a folder there" % rel)
            # the old name is moved aside, never copied or read: whatever the service made there (a link, a FIFO, a huge file) stays as it is
            os.rename(name, "%s.before-restore-%s" % (name, stamp), src_dir_fd=fd, dst_dir_fd=fd)
        w = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
        try:
            with os.fdopen(w, "wb", closefd=False) as wf, open(src, "rb") as f:
                while True:
                    chunk = f.read(1 << 20)
                    if not chunk:
                        break
                    wf.write(chunk)
            os.fchown(w, owner.st_uid, owner.st_gid)
            os.fchmod(w, mode)
        finally:
            os.close(w)
        os.rename(tmp, name, src_dir_fd=fd, dst_dir_fd=fd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=fd)
        except OSError:
            pass
        raise
    finally:
        os.close(fd)
    return 0


def main(argv):
    try:
        if len(argv) == 4 and argv[0] == "same":
            return same(*argv[1:])
        if len(argv) == 5 and argv[0] == "put":
            return put(*argv[1:])
    except OSError as e:
        sys.stderr.write("state_put.py: %s: %s\n" % (argv[3] if len(argv) > 3 else "?", e.strerror or e))
        return 2
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
