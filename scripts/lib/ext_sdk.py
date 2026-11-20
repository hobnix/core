"""Python helper of the extension SDK (hobnix/server#197, docs/extensions-sdk.md). One file, standard library only.

An extension that speaks the command protocol (ADR 0010, docs/api/ext-protocol-v1.schema.json):

    import os, sys
    sys.path.insert(0, os.path.join(os.environ["HS_SCRIPTS"], "lib"))     # the core sets HS_SCRIPTS; python3 -I does not search this folder
    import ext_sdk

    def handle(req, ctx):
        if req.words == ["greet"]:
            ctx.progress(0.5, "halfway")
            return ext_sdk.ok({"greeting": "hello"}, text="hello")
        raise ext_sdk.Failure("not_found", "no such command")

    ext_sdk.run(handle)

handle(request, ctx) returns ok(...) or raises Failure(code, message); any other exception is answered as `failed` (traceback on stderr).
"""
import json
import sys

VERSION = 1
CODES = ("failed", "not_found", "bad_request", "cancelled")
MAX_LINE = 1 << 20


class Failure(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code if code in CODES else "failed"
        self.message = " ".join(str(message).split()) or "failed"


class Success:
    def __init__(self, data=None, text=None):
        self.data = data
        self.text = text


def ok(data=None, text=None):
    return Success(data, text)


class Request:
    def __init__(self, raw):
        self.id = raw["id"]
        self.words = list(raw["command"])
        self.argv = list(raw["argv"])
        self.lang = raw["lang"]
        self.caller = raw["caller"]
        self.timeout_ms = raw["timeout_ms"]


class Ctx:
    """Messages before the result. Each call writes one line to stdout."""

    def _send(self, **m):
        m["v"] = VERSION
        line = json.dumps(m, ensure_ascii=False, separators=(",", ":"))
        if len(line) + 1 > MAX_LINE:
            raise ValueError("a message must be shorter than 1 MiB")
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    def progress(self, fraction=None, text=""):
        m = {"type": "progress"}
        if fraction is not None:
            m["fraction"] = float(fraction)
        if text:
            m["text"] = text[:200]
        self._send(**m)

    def log(self, level, text):
        if level not in ("debug", "info", "warn", "error"):
            raise ValueError("level is debug|info|warn|error")
        self._send(type="log", level=level, text=str(text)[:1000])

    def event(self, kind, subject, text=None, level=None, payload=None):
        m = {"type": "event", "kind": kind, "subject": subject}
        for k, v in (("text", text), ("level", level), ("payload", payload)):
            if v is not None:
                m[k] = v
        self._send(**m)


def run(handler):
    """Read the request, call handler(request, ctx), write the result and exit with the status the protocol wants."""
    ctx = Ctx()
    try:
        raw = json.loads(sys.stdin.readline())
        if not isinstance(raw, dict) or raw.get("v") != VERSION:
            raise ValueError("version")
    except ValueError:
        ctx._send(type="result", ok=False, error={"code": "unsupported_version", "message": "this extension speaks protocol version 1 only", "supported": [VERSION]})
        sys.exit(1)
    try:
        res = handler(Request(raw), ctx)
        if not isinstance(res, Success):
            res = Success(res)
        m = {"type": "result", "ok": True}
        if res.data is not None:
            m["data"] = res.data
        if res.text:
            m["text"] = res.text
        ctx._send(**m)
    except Failure as e:
        ctx._send(type="result", ok=False, error={"code": e.code, "message": e.message})
        sys.exit(1)
    except Exception as e:   # a bug in the extension: say so, keep the traceback for stderr
        import traceback
        traceback.print_exc(file=sys.stderr)
        ctx._send(type="result", ok=False, error={"code": "failed", "message": "internal error: %s" % " ".join(str(e).split())})
        sys.exit(1)
    sys.exit(0)
