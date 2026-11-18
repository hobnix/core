#!/usr/bin/env python3
"""API tokens (ADR 0012 decisions 4 to 6, D4 of docs/PLAN-extensions-access.md): the store, the rate limit and the owner re-check.

A token is `hn_` + 32 random bytes in base64url (43 characters). Its id is the first 8 of those 43 characters: the id names the token in the list, in the
audit line and in the rate limit; the other 35 characters (210 bits) are what nobody can guess. Only the sha256 of the whole token is stored, in
$HS_STATE_DIR/api-tokens.json (mode 0600, on the system disk, not in the vault: a token must work after a boot before anyone unlocks).
The token is printed once, by `create`, and never again.

CLI (scripts/token.sh is the front end; the token goes to stdout only, never into an argument or the environment):
  token_store.py create --name N --owner U --realm domain|local --role R [--days D] [--cap R]   one line: token<TAB>id<TAB>expires
  token_store.py validate <the same options>        exit 0 when create would be allowed, else the reason on stderr (writes nothing)
  token_store.py list [--owner U]                  id, name, owner, realm, role, created, expires, state (active|expired); one per line
  token_store.py find <name>                       the list line of one token, exit 1 when there is none
  token_store.py revoke <name> [--owner U]         exit 0 revoked, 1 no such token
Test knobs: HS_TOKEN_FILE (the file), HS_STATE_DIR.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sys
import tempfile
import threading
import time

try:
    import fcntl
except ImportError:      # Windows: the tests of the store run without the lock
    fcntl = None

ROLES = ("viewer", "app-manager", "admin")
PREFIX = "hn_"
DEFAULT_DAYS, MAX_DAYS = 90, 365
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$")
TOKEN_RE = re.compile(r"^hn_[A-Za-z0-9_-]{43}$")
RECHECK = 3600            # seconds: how old the owner's role may be before it is read again (ADR 0012 decision 6)
DC_GRACE = 86400          # seconds without a domain controller after which a token above viewer is refused
FAIL_LIMIT, FAIL_WINDOW, LOCK_SECONDS = 60, 60, 300       # D4: 60 failures a minute lock the id for 5 minutes


def role_rank(r):
    return ROLES.index(r) if r in ROLES else -1


def store_path():
    return os.environ.get("HS_TOKEN_FILE") or os.path.join(os.environ.get("HS_STATE_DIR", "/var/lib/hs"), "api-tokens.json")


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def token_id(token):
    return token[len(PREFIX):len(PREFIX) + 8]


class Store:
    """The token file. Every change takes the lock, reads, changes, writes through a temp file and renames (0600)."""

    def __init__(self, path=None):
        self.path = path or store_path()
        self.mem = threading.Lock()

    def _read(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                d = json.load(f)
            return [r for r in d.get("tokens", []) if isinstance(r, dict) and re.fullmatch(r"[0-9a-f]{64}", str(r.get("hash", "")))]
        except (OSError, ValueError, AttributeError):
            return []

    def _write(self, rows):
        d = os.path.dirname(self.path) or "."
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".api-tokens.")
        try:
            os.fchmod(fd, 0o600) if hasattr(os, "fchmod") else None
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump({"tokens": rows}, f)
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    def _locked(self, fn):
        with self.mem:
            lf = None
            if fcntl:
                try:
                    os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
                    lf = open(self.path + ".lock", "a")
                    fcntl.flock(lf, fcntl.LOCK_EX)
                except OSError:
                    lf = None
            try:
                return fn()
            finally:
                if lf:
                    lf.close()

    def rows(self):
        return self._read()

    def check(self, name, owner, realm, role, days=DEFAULT_DAYS, cap=None):
        """Raises ValueError with a sentence for a refusal; writes nothing. `cap` is the role of whoever asks: a token never exceeds it."""
        if not isinstance(name, str) or not NAME_RE.fullmatch(name):
            raise ValueError("The name is 1 to 40 letters, digits, dot, dash or underscore, and starts with a letter or digit.")
        if role not in ROLES:
            raise ValueError("The role is viewer, app-manager or admin.")
        if realm not in ("domain", "local"):
            raise ValueError("The realm is domain or local.")
        if not isinstance(owner, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._\\@-]{0,127}", owner):
            raise ValueError("The owner is not a user name.")
        if not isinstance(days, int) or isinstance(days, bool) or days < 1 or days > MAX_DAYS:
            raise ValueError("A token lives 1 to %d days (default %d); there is no token without an expiry." % (MAX_DAYS, DEFAULT_DAYS))
        if cap is not None and role_rank(role) > role_rank(cap):
            raise ValueError("A token cannot have more than your own role (%s)." % cap)
        if any(r["name"] == name for r in self._read()):
            raise ValueError("There is a token with this name already.")

    def create(self, name, owner, realm, role, days=DEFAULT_DAYS, cap=None, now=None):
        """-> (token, record). Raises ValueError (see check)."""
        now = time.time() if now is None else now
        self.check(name, owner, realm, role, days, cap)

        def work():
            rows = self._read()
            if any(r["name"] == name for r in rows):
                raise ValueError("There is a token with this name already.")
            token = PREFIX + base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")
            rec = {"id": token_id(token), "name": name, "owner": owner, "realm": realm, "role": role, "hash": token_hash(token),
                   "created": int(now), "expires": int(now) + days * 86400}
            if any(r.get("id") == rec["id"] for r in rows):
                raise ValueError("Try again (the new token's id was taken).")      # 1 in 2^48: never in practice
            rows.append(rec)
            self._write(rows)
            return token, rec
        return self._locked(work)

    def find(self, token, now=None):
        """The record of a token (any state), or None. Compares the hash in constant time."""
        if not isinstance(token, str) or not TOKEN_RE.fullmatch(token):
            return None
        h = token_hash(token)
        hit = None
        for r in self._read():
            if hmac.compare_digest(r["hash"], h):
                hit = r
        return hit

    def by_id(self, tid):
        return next((r for r in self._read() if r.get("id") == tid), None)

    def revoke(self, name, owner=None):
        def work():
            rows = self._read()
            keep = [r for r in rows if not (r["name"] == name and (owner is None or r["owner"] == owner))]
            if len(keep) == len(rows):
                return False
            self._write(keep)
            return True
        return self._locked(work)


class Limiter:
    """D4: 60 failures in a minute lock one token id for 5 minutes. A failure is a token that names an id and is wrong, expired, or whose owner is gone.
    The clock is injected so a test can move it."""

    def __init__(self, clock=time.time):
        self.clock, self.lock, self.fails, self.until = clock, threading.Lock(), {}, {}

    def locked(self, tid):
        with self.lock:
            return max(0, int(self.until.get(tid, 0) - self.clock() + 0.999))

    def failed(self, tid):
        now = self.clock()
        with self.lock:
            if len(self.fails) > 4096:
                self.fails = {k: v for k, v in self.fails.items() if v and now - v[-1] < FAIL_WINDOW}
                self.until = {k: v for k, v in self.until.items() if v > now}
            f = [t for t in self.fails.get(tid, []) if now - t < FAIL_WINDOW] + [now]
            self.fails[tid] = f
            if len(f) >= FAIL_LIMIT:
                self.until[tid] = now + LOCK_SECONDS
                self.fails[tid] = []

    def ok(self, tid):
        with self.lock:
            self.fails.pop(tid, None)


class TokenAuth:
    """Turns `Authorization: Bearer <token>` into (record, role) or a refusal. The role of a token is never above its owner's role as the owner
    has it now: it is read from `resolver(record)` at most once an hour per owner (ADR 0012 decision 6), and a token that has not been seen to
    work for a day while the domain controller is down stays at viewer.

    resolver(owner, realm) -> ("role", <role>) the owner has this role now
                              ("gone", None)    the account is disabled, removed, or in none of the three groups any more
                              ("down", None)    the domain controller does not answer (no verdict)
    """

    def __init__(self, store, resolver, clock=time.time, limiter=None):
        self.store, self.resolver, self.clock = store, resolver, clock
        self.limiter = limiter or Limiter(clock)
        self.cache = {}      # (owner, realm) -> {"role", "at" (when read), "good" (last time a verdict was a role)}
        self.lock = threading.Lock()

    def owner_role(self, owner, realm):
        """-> role or None (gone). Reads the resolver when the cached answer is older than RECHECK."""
        now, key = self.clock(), (owner, realm)
        with self.lock:
            c = self.cache.get(key)
        if c and now - c["at"] < RECHECK:
            return c["role"]
        verdict, role = self.resolver(owner, realm)
        with self.lock:
            if verdict == "role" and role in ROLES:
                self.cache[key] = {"role": role, "at": now, "good": now}
                return role
            if verdict == "down" and c:
                # no verdict: keep what we knew, for a day; after that nothing above viewer (ADR 0012 decision 6)
                keep = c["role"] if now - c["good"] <= DC_GRACE else "viewer"
                self.cache[key] = {"role": keep, "at": now, "good": c["good"]}
                return keep
            if verdict == "down":
                self.cache[key] = {"role": "viewer", "at": now, "good": 0}      # never known: the least a token can be
                return "viewer"
            self.cache.pop(key, None)
            return None

    def check(self, header):
        """-> ("ok", info) | ("refused", status, text, tid or None, count_failure). info = {id, name, owner, realm, role, expires}.
        The caller counts failure=True against the address (and this counts it against the id)."""
        h = (header or "").strip()
        if not h[:7].lower() == "bearer ":
            return ("none",)
        token = h[7:].strip()
        if not TOKEN_RE.fullmatch(token):
            return ("refused", 401, "That is not a token.", None, True)
        tid = token_id(token)
        wait = self.limiter.locked(tid)
        if wait:
            return ("refused", 429, "Too many wrong tries for this token. Wait %d seconds." % wait, tid, False)
        rec = self.store.find(token)
        if rec is None:
            known = self.store.by_id(tid) is not None
            if known:
                self.limiter.failed(tid)      # the id exists, the secret is wrong: that is what the per id limit is for
            return ("refused", 401, "That token is not valid.", tid if known else None, True)
        if rec["expires"] <= self.clock():
            self.limiter.failed(tid)
            return ("refused", 401, "That token has expired.", tid, True)
        owner_role = self.owner_role(rec["owner"], rec["realm"])
        if owner_role is None:
            self.limiter.failed(tid)
            return ("refused", 401, "The owner of that token can no longer sign in.", tid, True)
        role = rec["role"] if role_rank(rec["role"]) <= role_rank(owner_role) else owner_role
        self.limiter.ok(tid)
        return ("ok", {"id": rec["id"], "name": rec["name"], "owner": rec["owner"], "realm": rec["realm"], "role": role,
                       "expires": rec["expires"]})


def line(r, now):
    return "\t".join([r["id"], r["name"], r["owner"], r["realm"], r["role"], str(r["created"]), str(r["expires"]),
                      "expired" if r["expires"] <= now else "active"])


def main(argv):
    p = argparse.ArgumentParser(prog="token_store.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create")
    c.add_argument("--name", required=True)
    c.add_argument("--owner", required=True)
    c.add_argument("--realm", required=True)
    c.add_argument("--role", required=True)
    c.add_argument("--days", type=int, default=DEFAULT_DAYS)
    c.add_argument("--cap")
    v = sub.add_parser("validate")
    for k in ("name", "owner", "realm", "role"):
        v.add_argument("--" + k, required=True)
    v.add_argument("--days", type=int, default=DEFAULT_DAYS)
    v.add_argument("--cap")
    ls = sub.add_parser("list")
    ls.add_argument("--owner")
    f = sub.add_parser("find")
    f.add_argument("name")
    r = sub.add_parser("revoke")
    r.add_argument("name")
    r.add_argument("--owner")
    a = p.parse_args(argv)
    st, now = Store(), time.time()
    if a.cmd == "create":
        try:
            token, rec = st.create(a.name, a.owner, a.realm, a.role, a.days, a.cap)
        except ValueError as e:
            sys.stderr.write(str(e) + "\n")
            return 1
        sys.stdout.write("token\t%s\t%s\t%d\n" % (token, rec["id"], rec["expires"]))
        return 0
    if a.cmd == "validate":
        try:
            st.check(a.name, a.owner, a.realm, a.role, a.days, a.cap)
        except ValueError as e:
            sys.stderr.write(str(e) + chr(10))
            return 1
        return 0
    if a.cmd == "list":
        for rec in sorted(st.rows(), key=lambda x: x["created"]):
            if a.owner is None or rec["owner"] == a.owner:
                sys.stdout.write(line(rec, now) + "\n")
        return 0
    if a.cmd == "find":
        rec = next((x for x in st.rows() if x["name"] == a.name), None)
        if rec is None:
            return 1
        sys.stdout.write(line(rec, now) + "\n")
        return 0
    return 0 if st.revoke(a.name, a.owner) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
