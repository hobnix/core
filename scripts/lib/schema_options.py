"""The options of config/schema.toml for the tools that check a value against them (presets, blueprints). Stdlib only, no CLI.

  options()  {key: store}   every kind = "option" item; store is "machine" (machine.toml) or "settings" (runtime settings)
  secrets()  {key}          the options the schema marks `secret = true`
Test knobs: HS_SCHEMA, HS_MACHINE_FILE (the checkout beside it is used when the scripts run from a copy in /nix/store).
"""
import importlib.util
import os
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
ROOT = os.path.dirname(SCRIPTS)


def _beside(*parts):
    machine = os.environ.get("HS_MACHINE_FILE") or "/etc/nixos/machine.toml"
    return os.path.join(os.path.dirname(machine), *parts)


def schema_path():
    for c in (os.environ.get("HS_SCHEMA"), os.path.join(ROOT, "config", "schema.toml"), _beside("config", "schema.toml")):
        if c and os.path.exists(c):
            return c
    return os.path.join(ROOT, "config", "schema.toml")


def _items():
    path = schema_path()
    with open(path, "rb") as f:
        items = tomllib.load(f).get("item", [])
    # options a capability folder owns stand in schema.toml as kind = "include" anchors: schema-gen puts them back
    spec = importlib.util.spec_from_file_location("schema_gen", os.path.join(SCRIPTS, "schema-gen.py"))
    sg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sg)
    return [i for i in sg.expand_includes(items, path) if i.get("kind") == "option"]


def options():
    return {i["key"]: i.get("store", "machine") for i in _items()}


def secrets():
    return {i["key"] for i in _items() if i.get("secret") is True}
