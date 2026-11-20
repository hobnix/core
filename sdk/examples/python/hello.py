#!/usr/bin/env python3
"""Example command extension in Python: `hs ext hello greet [name]` and `hs ext hello count <n>` (docs/extensions-sdk.md).
Try it without the core: python3 scripts/lib/ext_proto.py call --command greet --arg Ada -- sdk/examples/python/hello.py"""
import os
import sys

# python3 -I (how the core starts a .py extension) does not look in the script's folder: name the helper's folder yourself
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.environ.get("HS_SCRIPTS", os.path.join(HERE, "..", "..", "..", "scripts")), "lib"))
import ext_sdk  # noqa: E402


def handle(req, ctx):
    if req.words == ["greet"]:
        name = req.argv[0] if req.argv else "world"
        ctx.log("info", "greeting")
        ctx.event("pkg.hello.greeted", name)
        return ext_sdk.ok({"greeting": "hello " + name}, text="hello " + name)
    if req.words == ["count"]:
        if not (req.argv and req.argv[0].isdigit() and 1 <= int(req.argv[0]) <= 10):
            raise ext_sdk.Failure("bad_request", "count needs a number from 1 to 10")
        n = int(req.argv[0])
        for i in range(1, n + 1):
            ctx.progress(i / n, "step %d of %d" % (i, n))
        return ext_sdk.ok({"counted": n})
    raise ext_sdk.Failure("not_found", "no such command")


ext_sdk.run(handle)
