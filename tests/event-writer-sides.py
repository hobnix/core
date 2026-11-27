#!/usr/bin/env python3
"""Both event writers write the same seeded random events, each into its own database; every byte of every column and every exit code
must be equal (tests/event-writer-rust.sh). Arguments: state-db.py, the hobnix binary, an empty work directory."""
import json
import os
import random
import sqlite3
import struct
import subprocess
import sys

STATE_DB, BIN, WORK = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
BACKSLASH = chr(92)
# what str.strip and the break rule treat as special, and neighbours that they must leave alone
SPACES = [chr(n) for n in [*range(1, 33), 0x7f, 0x85, 0xa0, 0x1680, 0x180e, *range(0x2000, 0x200e), 0x2028, 0x2029, 0x202f, 0x205f, 0x2060,
                           0x3000, 0xfeff]]


def run(command, db, args):
    env = dict(os.environ, HS_STATE_DB=db)
    return subprocess.run(command + args, env=env, capture_output=True, timeout=60).returncode


def rows(db):
    c = sqlite3.connect(db)
    try:
        return c.execute("SELECT id, time, source, kind, subject, level, hex(CAST(text AS BLOB)), hex(CAST(subject AS BLOB)), payload,"
                         " typeof(payload), v FROM events ORDER BY id").fetchall()
    finally:
        c.close()


def a_float(r):
    if r.random() < 0.5:                                    # any bit pattern that is a finite number
        while True:
            x = struct.unpack("<d", struct.pack("<Q", r.getrandbits(64)))[0]
            if x == x and x not in (float("inf"), float("-inf")):
                return repr(x) if r.random() < 0.5 else "%.17e" % x
    if r.random() < 0.5:                                    # around the places where the notation changes
        return "%s%d.%0*de%d" % (r.choice(["", "-"]), r.randrange(10), r.randrange(1, 20), r.randrange(10 ** 6), r.randrange(-9, 25))
    return "%s%de%s%d" % (r.choice(["", "-"]), r.randrange(1, 10 ** r.randrange(1, 25)), r.choice(["", "+", "-"]), r.randrange(0, 40))


def a_string(r):
    out = []
    for _ in range(r.randrange(12)):
        pick = r.random()
        if pick < 0.35:                                     # an escape of any UTF-16 unit, lone surrogates too
            out.append(BACKSLASH + "u%04x" % r.choice([r.randrange(0x80), r.randrange(0xd800, 0xe000), r.randrange(0x10000)]))
        elif pick < 0.45:
            out.append(BACKSLASH + r.choice(['"', BACKSLASH, "/", "b", "f", "n", "r", "t"]))
        else:
            c = chr(r.choice([r.randrange(0x20, 0x80), r.randrange(0x80, 0xd800), r.randrange(0xe000, 0x110000)]))
            out.append(BACKSLASH + c if c in ('"', BACKSLASH) else c)
    return '"%s"' % "".join(out)


def a_value(r, depth):
    pick = r.randrange(8 if depth < 4 else 6)
    if pick == 0:
        return r.choice(["true", "false", "null", "-0", "0", "-0.0"])
    if pick == 1:
        return str(r.randrange(-10 ** 40, 10 ** 40))
    if pick in (2, 3):
        return a_float(r)
    if pick in (4, 5):
        return a_string(r)
    space = r.choice(["", " ", "\n", "\t", "\r "])
    if pick == 6:
        return "[%s]" % ("," + space).join(a_value(r, depth + 1) for _ in range(r.randrange(5)))
    return an_object(r, depth + 1)


def an_object(r, depth, size=None):
    keys = ['"a"', '"b"', '"c"', '"' + BACKSLASH + 'u0061"', a_string(r)]      # repeated keys, also written differently
    return "{%s}" % ",".join("%s:%s" % (r.choice(keys) if depth else '"k%d"' % i, a_value(r, depth))
                             for i, _ in enumerate(range(size if size is not None else r.randrange(5))))


def damaged(r, text):
    at = r.randrange(len(text))
    return text[:at] + r.choice(["", ",", "}", "]", '"', ".", "e", "0", "-", "+", " ", "N", chr(0xa0)]) + text[at + r.randrange(2):]


def a_line(r):
    word = lambda: r.choice(["", "a", "z" * r.randrange(600), chr(0xe4), chr(0x1f600) * r.randrange(300), "-"])
    return "".join(r.choice([r.choice(SPACES), word()]) for _ in range(r.randrange(12)))


def main():
    os.makedirs(WORK, exist_ok=True)
    r = random.Random(1336)
    events = []
    for _ in range(40):                                     # many values in one payload
        events.append(["storage.new", "s", "t", "--payload", an_object(r, 0, 150)])
    for _ in range(120):                                    # mostly not JSON any more
        events.append(["storage.new", "s", "t", "--payload", damaged(r, an_object(r, 0, 3))])
    for _ in range(80):
        events.append(["storage.new", "--level", "warn", a_line(r), a_line(r)])
    databases = [os.path.join(WORK, name + ".db") for name in ("python", "rust")]
    writers = [[sys.executable, STATE_DB, "emit"], [BIN, "event-emit"]]
    for db in databases:
        subprocess.run([sys.executable, STATE_DB, "forget", "nothing"], env=dict(os.environ, HS_STATE_DB=db), capture_output=True)
    for number, args in enumerate(events):
        codes = [run(w, db, args) for w, db in zip(writers, databases)]
        newest = [rows(db)[-1:] for db in databases]
        if codes != [0, 0] or newest[0] != newest[1]:
            print("event %d, exit codes %s\narguments %s\npython %s\nrust   %s" % (number, codes, json.dumps(args)[:2000], newest[0], newest[1]))
            return 1
    python, rust = (rows(db) for db in databases)
    stored = sum(1 for row in python if row[9] != "null")
    if python != rust or len(python) != len(events) or not 40 <= stored < len(events):
        print("rows: python %d, rust %d, equal %s, with a payload %d" % (len(python), len(rust), python == rust, stored))
        return 1
    print("%d events, %d of them with a payload: both writers stored the same bytes" % (len(python), stored))
    return 0


if __name__ == "__main__":
    sys.exit(main())
