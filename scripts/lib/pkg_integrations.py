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


def key_file_problem(path, provider, caller=None, root=STATE_ROOT, resolve=False):
    """The ONE check of a key file before it is handed out (integration_key, `grant`, the validator, LoadCredential of the service bridge): None or the
    reason. The file must lie below <root>/<provider>/ (the folder of the package that offers the integration), without ".." or control characters,
    and the caller must not be the provider. resolve=True also looks at the disk: the folder must not be a link out of <root>/<provider>, and a link
    as the file itself may only lead into that folder or the vault (HS_VAULT_DIR, default /var/lib/hs-vault). systemd reads a credential as root, so
    a path like /etc/shadow must never get here."""
    if not isinstance(path, str) or not isinstance(provider, str) or not NAME.match(provider):
        return "the key file or the provider is not valid"
    if caller is not None and caller == provider:
        return "a package does not get its own key through an integration"
    if re.search(r"[\x00-\x20\x7f]", path) or not path.startswith("/") or ".." in path.split("/"):
        return "the key file path is not valid"
    base = root.rstrip("/") + "/" + provider + "/"
    if not path.startswith(base) or len(path) == len(base) or path.endswith("/") or "//" in path:
        return "the key file must lie below %s" % base
    if resolve:
        top = os.path.realpath(base)
        within = lambda p, d: p == d or p.startswith(d.rstrip("/") + "/")
        if not within(os.path.realpath(os.path.dirname(path)), top):
            return "the folder of the key file leads out of %s" % base
        vault = os.path.realpath(os.environ.get("HS_VAULT_DIR") or "/var/lib/hs-vault")
        real = os.path.realpath(path)
        if not (within(real, top) or within(real, vault)):
            return "the key file is a link that leaves %s" % base
    return None


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
    """[[package, integration, source, api_url, key_file, extras]] of the valid blocks of the packages whose name is in `on` (recipe installed,
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
            out.append([m["name"], n, m.get("kind", "-"), _dash(u), _dash(b.get("key_file")), _dash(ex)])
    return sorted(out)


def grant(manifests, on, integration, caller):
    """(key_file, None) when `caller` may have the key of `integration`, else (None, reason). A capability needs no permission; an extension
    must declare integration:<name> (a declared check only: permissions are not enforced yet, hobnix/server#239); a recipe is refused."""
    me = next((m for _, m in manifests if m.get("name") == caller), None)
    if me is None:
        return None, f"{caller}: no such package"
    if me.get("kind") == "recipe":
        return None, f"{caller} is a recipe: only an extension or a capability may ask for a key"
    if me.get("kind") == "extension" and f"integration:{integration}" not in (me.get("permissions") or []):
        return None, f"{caller} does not declare permissions = [\"integration:{integration}\"]"
    hits = [r for r in rows(manifests, on, integration) if r[4] != "-"]
    if not hits:
        return None, f"no available package offers {integration} with a key_file"
    bad = key_file_problem(hits[0][4], hits[0][0], caller, resolve=True)
    if bad:
        return None, f"{hits[0][0]}: {bad}"
    return hits[0][4], None
