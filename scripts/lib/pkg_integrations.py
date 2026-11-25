"""The [integrations.<name>] blocks of a package.toml (hobnix/core#926, docs/PLAN-packages.md "Integrations"). Python stdlib only, no CLI.
A package (recipe, extension or capability) says what it offers to others, so another package finds it and its local API without copy and paste:
  [integrations.media]                         <name> is any lowercase id; the core knows no names
  api_url    = "http://{host}:7878"            the local API; {host} is the address of the instance (the consumer fills it in),
                                                 {port} the port of its service record (services.d/<package>.toml), only http(s), no spaces
  key_file   = "/var/lib/hs/radarr/api-key"    absolute path of the API key on the server (read only through scripts/lib/secret.sh), no ".."
  key_header = "X-Api-Key"                     optional: the header the app wants the key in (default X-Api-Key)
  <any other key> = "text"                     passed through as a plain string (at most 200 chars, no control chars, no comma)
All envelope keys are optional. A package may offer several integrations. Nothing here reads a key: rows give its path, the shell side asks
secret_state. A package that wants a key declares `permissions = ["integration:<name>"]` (pkg_perms.py); `grant` checks it.
"""
import os
import re
import tomllib

NAME = re.compile(r"^[a-z][a-z0-9-]*$")
ENVELOPE = ("api_url", "key_file", "key_header")
URL = re.compile(r"^https?://[A-Za-z0-9._{}-]+(:([0-9]{1,5}|\{port\}))?(/[^\s]*)?$")
HEADER = re.compile(r"^[A-Za-z][A-Za-z0-9-]{0,39}$")
PLAIN = re.compile(r"^[^\x00-\x1f\x7f,]{0,200}$")
MAX_EXTRA = 20
PLACEHOLDER = re.compile(r"\{([^{}]*)\}")
KNOWN = ("host", "port")


STATE_ROOT = "/var/lib/hs"
# Folders below /var/lib/hs that the core itself uses (state files, secrets, other packages' state). No package may offer an integration under one
# of these names, so a manifest cannot point key_file at them. The ONE list (tests/ext-service-reach.sh scans the code and fails when the core
# uses a folder that is neither here nor a documented example): add a name here when the core starts to use a new folder. A prefix covers a family.
RESERVED = frozenset("""adopting apps capabilities detached disks docs-site expiry ext generated golden iso jobs lock metrics nodes packages posters
recovering removals removed reports runs settings src state unifi matrix-hook media-ntfy dhcp-ranges setup-choice blueprints""".split())
RESERVED_PREFIXES = ("apps-", "backup", "remote", "node-key", "node-known", "docker", "recipe", "capabilities-", "disk", "vault", "notify", "luks", "ports",
                     "dc-ca", "machine", "last-rebuild", "live-measure", "restic", "health", "heartbeat", "migrate", "pkg-", "services", "share-",
                     "snapshots", "scrub", "selftest", "update-", "vps-", "wear-", "zoraxy", "grafana", "testlab", "ext-", "bulk-", "deck-", "event-",
                     "first-run", "gateway", "homepage", "incident", "parity-", "pci-", "spindown", "sync-", "cf-", "api-tokens", "tailscale", "unifi-",
                     "iso-", "src-", "state", "stat-", "hs-")


def is_reserved(name):
    return name in RESERVED or any(name.startswith(x) for x in RESERVED_PREFIXES)


MAX_KEY = 64 << 10


def _within(p, d):
    return p == d or p.startswith(d.rstrip("/") + "/")


def designated(path, root=STATE_ROOT):
    """The ONE vault file secret.sh designates for the state file `path` (secret_prepare: <vault>/secrets/<name relative to the state dir>), resolved.
    A key file may be a link only to exactly this file: no other file of the vault (other packages' keys, the vault's own) can be reached by a link."""
    vault = os.path.realpath(os.environ.get("HS_VAULT_DIR") or "/var/lib/hs-vault")
    return os.path.join(vault, "secrets", path[len(root.rstrip("/")) + 1:])


STAT_SECRET = re.compile(r"^stat-[a-z0-9][a-z0-9-]{0,40}$")   # the core's name of the API key of a service (scripts/services.py, secrets.sh, hs services key)


def flat_key(path, provider, root=STATE_ROOT):
    """True for exactly <root>/stat-<provider>: the one flat file in the state folder a package may offer (the recipes declare key_file =
    "/var/lib/hs/stat-<app>", the existing convention). Only the provider's OWN name, nothing else flat."""
    name = "stat-" + provider
    return path == root.rstrip("/") + "/" + name and bool(STAT_SECRET.match(name))


def key_file_problem(path, provider, caller=None, root=STATE_ROOT, resolve=False):
    """The ONE check of a key file before it is handed out (integration_key, `grant`, the validator, the bridge before it copies the key for
    LoadCredential): None or the reason. The file must lie below <root>/<provider>/ (the folder of the package that offers the integration; the
    provider is the REGISTERED package, never read from the path), without ".." or control characters, the provider must not be a core folder
    (RESERVED) and the caller must not be the provider. resolve=True also looks at the disk: the folder must not be a link out of
    <root>/<provider>, and the file must be a regular file, not a link: the one exception is a link to the vault file that secret.sh designates for this very path (`designated`: how it keeps
    secrets, HS_VAULT_DIR, default /var/lib/hs-vault), never to another file of the vault; a dangling link is "locked" and left to the caller. A missing
    file is no problem here either (the caller says "missing"). The check is for early refusal; the bytes are read by `read_key`."""
    if not isinstance(path, str) or not isinstance(provider, str) or not NAME.match(provider):
        return "the key file or the provider is not valid"
    if is_reserved(provider):
        return "%s is a folder the core uses: a package of that name cannot offer a key" % provider
    if caller is not None and caller == provider:
        return "a package does not get its own key through an integration"
    if re.search(r"[\x00-\x20\x7f]", path) or not path.startswith("/") or ".." in path.split("/"):
        return "the key file path is not valid"
    base = root.rstrip("/") + "/" + provider + "/"
    flat = flat_key(path, provider, root)
    if not flat and (not path.startswith(base) or len(path) == len(base) or path.endswith("/") or "//" in path):
        return "the key file must lie below %s (or be %s/stat-%s)" % (base, root.rstrip("/"), provider)
    if resolve:
        import stat
        top = os.path.realpath(base)
        if flat:    # the folder is the state root itself: it must not be a link either
            if os.path.realpath(os.path.dirname(path)) != os.path.realpath(root):
                return "the folder of the key file leads out of %s" % root
        elif not _within(os.path.realpath(os.path.dirname(path)), top):
            return "the folder of the key file leads out of %s" % base
        try:
            st = os.lstat(path)
        except OSError:
            return None
        if stat.S_ISLNK(st.st_mode):
            real = os.path.realpath(path)
            if not os.path.exists(real):
                return None
            if real != designated(path, root) or not stat.S_ISREG(os.stat(real).st_mode):
                return "the key file is a link, and not to the vault file that secret.sh designates for it"
        elif not stat.S_ISREG(st.st_mode):
            return "the key file is not a regular file"
    return None


def read_key(path, provider, caller=None, root=STATE_ROOT):
    """(bytes, None) or (None, reason): the key, read ONCE from a file that was checked after it was opened (no time between check and use for
    a link swap): the file is opened without following a link (the real path was resolved first), must be a regular file that is not world
    writable and at most 64 KiB, and the path the open descriptor stands for (/proc/self/fd) must still lie in the provider's folder or the vault.
    The bridge writes these bytes to its own 0600 file and hands THAT copy to systemd, which therefore never opens a path somebody else can change."""
    import stat
    why = key_file_problem(path, provider, caller, root, resolve=True)
    if why:
        return None, why
    real = os.path.realpath(path)
    try:
        fd = os.open(real, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
    except OSError as e:
        return None, "the key file cannot be opened (%s)" % e.strerror
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o002 or st.st_size > MAX_KEY:
            return None, "the key file is not a plain file (regular, not world writable, at most 64 KiB)"
        try:
            now = os.readlink("/proc/self/fd/%d" % fd)
        except OSError:
            return None, "cannot verify the opened key file"
        own = os.path.realpath(path) if flat_key(path, provider, root) else None
        if not (_within(now, os.path.realpath(root.rstrip("/") + "/" + provider)) or now == designated(path, root) or now == own):
            return None, "the opened key file lies outside the provider's folder"
        return os.read(fd, MAX_KEY + 1)[:MAX_KEY], None
    finally:
        os.close(fd)


def manifest_problems(m):
    """[text] for the integrations table of one package.toml dict."""
    ig = m.get("integrations")
    if ig is None:
        return []
    if not isinstance(ig, dict):
        return ["integrations must be a table"]
    out = []
    for n, b in ig.items():
        p = f"integrations.{n}"
        if not NAME.match(str(n)):
            out.append(f"{p}: the name is not a lowercase id")
        if not isinstance(b, dict):
            out.append(f"{p} must be a table")
            continue
        u = b.get("api_url")
        if u is not None and (not isinstance(u, str) or not URL.match(u)):
            out.append(f"{p}.api_url must be an http(s) URL without spaces ({{host}} stands for the instance, {{port}} for its port)")
        elif u is not None:
            bad = sorted({w for w in PLACEHOLDER.findall(u) if w not in KNOWN})
            if bad or re.sub(PLACEHOLDER, "", u).count("{") + re.sub(PLACEHOLDER, "", u).count("}"):
                out.append(f"{p}.api_url: only {{host}} and {{port}} are placeholders" + (f" (not {{{bad[0]}}})" if bad else ""))
        f = b.get("key_file")
        if f is not None and (not isinstance(f, str) or not f.startswith("/") or ".." in f.split("/") or re.search(r"\s", f)):
            out.append(f"{p}.key_file must be an absolute path without .. or spaces")
        elif f is not None and m.get("name") and key_file_problem(f, str(m["name"])):
            out.append(f"{p}.key_file: " + key_file_problem(f, str(m["name"])))
        h = b.get("key_header")
        if h is not None and (not isinstance(h, str) or not HEADER.match(h)):
            out.append(f"{p}.key_header must be a header name")
        extra = [k for k in b if k not in ENVELOPE]
        if len(extra) > MAX_EXTRA:
            out.append(f"{p} has more than {MAX_EXTRA} extra keys")
        for k in extra:
            if not re.match(r"^[a-z][a-z0-9_]{0,39}$", str(k)):
                out.append(f"{p}.{k}: the key is not a lowercase word")
            elif not isinstance(b[k], str) or not PLAIN.match(b[k]):
                out.append(f"{p}.{k} must be plain text (at most 200 characters, no comma, no control character)")
    return out


def _dash(v):
    return v if v else "-"


def service_port(services_dir, package):
    """The port in <services_dir>/<package>.toml (the service record of the instance, written by `hs services declare`), or None."""
    try:
        with open(os.path.join(services_dir, package + ".toml"), "rb") as fh:
            port = tomllib.load(fh).get("port")
    except (OSError, tomllib.TOMLDecodeError):
        return None
    return port if isinstance(port, int) and not isinstance(port, bool) and 1 <= port <= 65535 else None


def rows(manifests, on, only=None, services_dir=None, unresolved=None):
    """[[package, integration, source, api_url, key_file, extras, key_header]] of the valid blocks of the packages whose name is in `on` (recipe installed,
    extension or capability on), sorted; empty fields are "-"; extras = k=v comma list of the keys beyond the envelope.
    {port} in api_url is filled from the service record of the package; without a record or a port the api_url is "-" (never guessed) and
    "package/integration" is appended to `unresolved`."""
    out = []
    for _, m in manifests:
        if m.get("name") not in on or manifest_problems(m):
            continue
        for n, b in sorted((m.get("integrations") or {}).items()):
            if only and n != only:
                continue
            ex = ",".join(f"{k}={b[k]}" for k in sorted(b) if k not in ENVELOPE)
            u = b.get("api_url")
            if u and "{port}" in u:
                port = service_port(services_dir, m["name"]) if services_dir else None
                if port is None:
                    u = None
                    if unresolved is not None:
                        unresolved.append(f"{m['name']}/{n}")
                else:
                    u = u.replace("{port}", str(port))
            out.append([m["name"], n, m.get("kind", "-"), _dash(u), _dash(b.get("key_file")), _dash(ex), _dash(b.get("key_header"))])
    return sorted(out)


def grant(manifests, on, integration, caller, provider=None):
    """(key_file, None) or (None, (code, reason)): see grant_full."""
    path, _, why = grant_full(manifests, on, integration, caller, provider)
    return path, why


def _permitted(manifests, integration, caller):
    """None when `caller` may ask for keys of `integration`, else (code, reason)."""
    me = next((m for _, m in manifests if m.get("name") == caller), None)
    if me is None:
        return ("integration.denied", f"{caller}: no such package")
    if me.get("kind") == "recipe":
        return ("integration.denied", f"{caller} is a recipe: only an extension or a capability may ask for a key")
    if me.get("kind") == "extension" and f"integration:{integration}" not in (me.get("permissions") or []):
        return ("integration.denied", f"{caller} does not declare permissions = [\"integration:{integration}\"]")
    return None


def grant_full(manifests, on, integration, caller, provider=None):
    """(key_file, provider, None) when `caller` may have the key of `integration`, else (None, None, (code, reason)) with a code of scripts/lib/error-codes.tsv.
    A capability needs no permission; an extension must declare integration:<name> (a declared check only: permissions are not enforced yet,
    hobnix/server#239); a recipe is refused. `provider` is the package whose key is wanted: it must be there and offer the integration with a
    key_file. Without a provider (the old two-argument form, kept for one release) the first package with a key_file is taken."""
    why = _permitted(manifests, integration, caller)
    if why:
        return None, None, why
    offers = rows(manifests, on, integration)
    if provider is not None:
        mine = [r for r in offers if r[0] == provider]
        if not mine:
            return None, None, ("integration.unknown", f"{provider} is not there or does not offer {integration}")
        if mine[0][4] == "-":
            return None, None, ("integration.nokey", f"{provider} offers {integration} without a key_file")
        return _checked(mine[0], caller)
    hits = [r for r in offers if r[4] != "-"]
    if not hits:
        return None, None, ("integration.nokey", f"no available package offers {integration} with a key_file")
    return _checked(hits[0], caller)


def grant_all(manifests, on, integration, caller):
    """([(key_file, provider)], [(provider, reason)], None) or ([], [], (code, reason)): one grant per provider that offers `integration` with a key_file
    (a service gets one credential per provider, named integration-<integration>-<provider>, hobnix/core#1135). The permission rules are those of grant_full
    (a recipe is refused, an extension must declare integration:<name>, else the third item says why); a provider without a key_file gives nothing and no
    failure; one that fails the strict key file check (or is the caller itself) is listed with its reason in the second list."""
    why = _permitted(manifests, integration, caller)
    if why:
        return [], [], why
    ok, bad = [], []
    for r in rows(manifests, on, integration):
        if r[4] == "-":
            continue
        p, prov, why = _checked(r, caller)
        if why:
            bad.append((r[0], why[1]))
        elif (p, prov) not in ok:
            ok.append((p, prov))
    return ok, bad, None


def _checked(row, caller):
    """(key_file, provider, None) after the strict key file check (key_file_problem: below the provider's own folder, a regular file), else (None, None, (code, reason))."""
    bad = key_file_problem(row[4], row[0], caller, resolve=True)
    if bad:
        return None, None, ("integration.denied", f"{row[0]}: {bad}")
    return row[4], row[0], None
